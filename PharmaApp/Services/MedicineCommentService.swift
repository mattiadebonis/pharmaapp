import Foundation
import CoreData

enum MedicineCommentAttachmentKind: String {
    case photo
    case file
}

struct MedicineCommentAttachmentInput {
    let kind: MedicineCommentAttachmentKind
    let filename: String
    let mimeType: String?
    let uti: String?
    let data: Data
}

enum MedicineCommentServiceError: LocalizedError {
    case emptyComment
    case tooManyAttachments(max: Int)
    case fileTooLarge(name: String, maxBytes: Int)
    case invalidAttachmentFilename

    var errorDescription: String? {
        switch self {
        case .emptyComment:
            return "Inserisci testo o almeno un allegato."
        case let .tooManyAttachments(max):
            return "Puoi allegare al massimo \(max) file."
        case let .fileTooLarge(name, maxBytes):
            let maxMB = max(1, maxBytes / (1024 * 1024))
            return "Il file \(name) supera il limite di \(maxMB) MB."
        case .invalidAttachmentFilename:
            return "Nome file non valido."
        }
    }
}

final class MedicineCommentService {
    static let maxAttachmentsPerComment = 10
    static let maxAttachmentBytes = 15 * 1024 * 1024

    private let context: NSManagedObjectContext
    private let fileManager: FileManager
    private let rootURL: URL

    init(
        context: NSManagedObjectContext,
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) {
        self.context = context
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.rootURL = base.appendingPathComponent("MedicineCommentAttachments", isDirectory: true)
        }
    }

    func createComment(
        medicine: Medicine,
        text: String,
        newAttachments: [MedicineCommentAttachmentInput]
    ) throws -> MedicineComment {
        let medicine = inContext(medicine)
        let normalizedText = normalized(text)
        try validateInputs(text: normalizedText, existingAttachmentCount: 0, newAttachments: newAttachments)

        let now = Date()
        let comment = try makeComment()
        comment.id = UUID()
        comment.text = normalizedText
        comment.created_at = now
        comment.updated_at = now
        comment.medicine = medicine
        comment.source = "local"
        comment.operation_id = OperationIdProvider.shared.newOperationId()
        comment.actor_user_id = UserIdentityProvider.shared.userId
        comment.actor_device_id = UserIdentityProvider.shared.deviceId

        var writtenURLs: [URL] = []
        do {
            try ensureRootDirectory()
            try writeAttachments(
                newAttachments,
                medicineId: medicine.id,
                commentId: comment.id,
                to: comment,
                writtenURLs: &writtenURLs
            )
            try context.save()
            return comment
        } catch {
            for url in writtenURLs {
                try? removeFileIfExists(at: url)
            }
            context.delete(comment)
            throw error
        }
    }

    func updateComment(
        comment: MedicineComment,
        text: String,
        attachmentsToDelete: [MedicineCommentAttachment],
        newAttachments: [MedicineCommentAttachmentInput]
    ) throws -> MedicineComment {
        let comment = inContext(comment)
        let normalizedText = normalized(text)
        let existing = (comment.attachments ?? []).filter { attachment in
            !attachmentsToDelete.contains { $0.objectID == attachment.objectID }
        }
        try validateInputs(
            text: normalizedText,
            existingAttachmentCount: existing.count,
            newAttachments: newAttachments
        )

        let attachmentsToDeleteInContext = attachmentsToDelete.compactMap { attachment -> MedicineCommentAttachment? in
            guard attachment.managedObjectContext != nil else { return nil }
            guard let resolved = context.object(with: attachment.objectID) as? MedicineCommentAttachment else { return nil }
            guard resolved.comment?.objectID == comment.objectID else { return nil }
            return resolved
        }

        let staleURLs = attachmentsToDeleteInContext.compactMap { fileURL(for: $0) }
        let now = Date()
        var writtenURLs: [URL] = []

        do {
            comment.text = normalizedText
            comment.updated_at = now
            comment.operation_id = OperationIdProvider.shared.newOperationId()
            comment.actor_user_id = UserIdentityProvider.shared.userId
            comment.actor_device_id = UserIdentityProvider.shared.deviceId
            comment.source = "local"

            for attachment in attachmentsToDeleteInContext {
                context.delete(attachment)
            }

            try ensureRootDirectory()
            try writeAttachments(
                newAttachments,
                medicineId: comment.medicine?.id ?? UUID(),
                commentId: comment.id,
                to: comment,
                writtenURLs: &writtenURLs
            )
            try context.save()
        } catch {
            for url in writtenURLs {
                try? removeFileIfExists(at: url)
            }
            context.rollback()
            throw error
        }

        for url in staleURLs {
            try? removeFileIfExists(at: url)
            cleanupEmptyParentDirectories(startingAt: url.deletingLastPathComponent())
        }
        return comment
    }

    func deleteComment(_ comment: MedicineComment) throws {
        let comment = inContext(comment)
        let urls = (comment.attachments ?? []).compactMap { fileURL(for: $0) }
        let folderURL = commentDirectoryURL(
            medicineId: comment.medicine?.id ?? UUID(),
            commentId: comment.id
        )
        context.delete(comment)

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        for url in urls {
            try? removeFileIfExists(at: url)
        }
        cleanupEmptyParentDirectories(startingAt: folderURL)
    }

    func deleteAllComments(for medicine: Medicine) throws {
        let medicine = inContext(medicine)
        let request = MedicineComment.fetchRequest(for: medicine)
        let comments = try context.fetch(request)
        guard !comments.isEmpty else {
            cleanupEmptyParentDirectories(startingAt: medicineDirectoryURL(medicineId: medicine.id))
            return
        }

        let urls = comments.flatMap { comment in
            (comment.attachments ?? []).compactMap { fileURL(for: $0) }
        }
        for comment in comments {
            context.delete(comment)
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        for url in urls {
            try? removeFileIfExists(at: url)
            cleanupEmptyParentDirectories(startingAt: url.deletingLastPathComponent())
        }
        cleanupEmptyParentDirectories(startingAt: medicineDirectoryURL(medicineId: medicine.id))
    }

    func fileURL(for attachment: MedicineCommentAttachment) -> URL? {
        guard let relativePath = attachment.relative_path, !relativePath.isEmpty else { return nil }
        return rootURL.appendingPathComponent(relativePath, isDirectory: false)
    }

    private func inContext<T: NSManagedObject>(_ object: T) -> T {
        if object.managedObjectContext === context {
            return object
        }
        return context.object(with: object.objectID) as! T
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validateInputs(
        text: String,
        existingAttachmentCount: Int,
        newAttachments: [MedicineCommentAttachmentInput]
    ) throws {
        if text.isEmpty && existingAttachmentCount + newAttachments.count == 0 {
            throw MedicineCommentServiceError.emptyComment
        }

        if existingAttachmentCount + newAttachments.count > Self.maxAttachmentsPerComment {
            throw MedicineCommentServiceError.tooManyAttachments(max: Self.maxAttachmentsPerComment)
        }

        for input in newAttachments {
            if input.data.count > Self.maxAttachmentBytes {
                throw MedicineCommentServiceError.fileTooLarge(
                    name: input.filename,
                    maxBytes: Self.maxAttachmentBytes
                )
            }
            if sanitizedFilename(input.filename).isEmpty {
                throw MedicineCommentServiceError.invalidAttachmentFilename
            }
        }
    }

    private func writeAttachments(
        _ inputs: [MedicineCommentAttachmentInput],
        medicineId: UUID,
        commentId: UUID,
        to comment: MedicineComment,
        writtenURLs: inout [URL]
    ) throws {
        for input in inputs {
            let attachmentId = UUID()
            let filename = sanitizedFilename(input.filename)
            let prefixedName = "\(attachmentId.uuidString)_\(filename)"
            let relativePath = "\(medicineId.uuidString)/\(commentId.uuidString)/\(prefixedName)"
            let destination = rootURL.appendingPathComponent(relativePath, isDirectory: false)
            let directory = destination.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try input.data.write(to: destination, options: .atomic)
            writtenURLs.append(destination)

            let attachment = try makeAttachment()
            attachment.id = attachmentId
            attachment.kind = input.kind.rawValue
            attachment.filename = input.filename
            attachment.mime_type = input.mimeType
            attachment.uti = input.uti
            attachment.byte_size = Int64(input.data.count)
            attachment.relative_path = relativePath
            attachment.created_at = Date()
            attachment.comment = comment
        }
    }

    private func makeComment() throws -> MedicineComment {
        guard let entity = NSEntityDescription.entity(forEntityName: "MedicineComment", in: context) else {
            throw NSError(
                domain: "MedicineCommentService",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Entity MedicineComment non trovata nel modello Core Data."]
            )
        }
        return MedicineComment(entity: entity, insertInto: context)
    }

    private func makeAttachment() throws -> MedicineCommentAttachment {
        guard let entity = NSEntityDescription.entity(forEntityName: "MedicineCommentAttachment", in: context) else {
            throw NSError(
                domain: "MedicineCommentService",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "Entity MedicineCommentAttachment non trovata nel modello Core Data."]
            )
        }
        return MedicineCommentAttachment(entity: entity, insertInto: context)
    }

    private func ensureRootDirectory() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private func sanitizedFilename(_ filename: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? "attachment" : trimmed
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let scalarView = source.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let sanitized = String(scalarView).replacingOccurrences(of: "__", with: "_")
        let normalized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return normalized.isEmpty ? "attachment" : String(normalized.prefix(80))
    }

    private func removeFileIfExists(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func medicineDirectoryURL(medicineId: UUID) -> URL {
        rootURL.appendingPathComponent(medicineId.uuidString, isDirectory: true)
    }

    private func commentDirectoryURL(medicineId: UUID, commentId: UUID) -> URL {
        medicineDirectoryURL(medicineId: medicineId).appendingPathComponent(commentId.uuidString, isDirectory: true)
    }

    private func cleanupEmptyParentDirectories(startingAt startURL: URL) {
        var currentURL = startURL
        let rootPath = rootURL.path
        while currentURL.path.hasPrefix(rootPath) && currentURL.path != rootPath {
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: currentURL.path)
                if contents.isEmpty {
                    try fileManager.removeItem(at: currentURL)
                    currentURL.deleteLastPathComponent()
                } else {
                    break
                }
            } catch {
                break
            }
        }
        if let rootContents = try? fileManager.contentsOfDirectory(atPath: rootURL.path), rootContents.isEmpty {
            try? fileManager.removeItem(at: rootURL)
        }
    }
}
