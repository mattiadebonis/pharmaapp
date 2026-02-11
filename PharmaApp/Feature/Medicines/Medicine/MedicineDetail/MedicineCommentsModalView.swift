import SwiftUI
import CoreData
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct MedicineCommentsModalView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.openURL) private var openURL

    @ObservedObject var medicine: Medicine
    @FetchRequest private var comments: FetchedResults<MedicineComment>

    @State private var draftText = ""
    @State private var editingCommentID: NSManagedObjectID?
    @State private var existingAttachments: [MedicineCommentAttachment] = []
    @State private var existingAttachmentsToDelete: Set<NSManagedObjectID> = []
    @State private var newAttachments: [DraftAttachment] = []

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showAttachmentOptions = false
    @State private var showFileImporter = false
    @State private var pendingDeleteComment: MedicineComment?
    @State private var errorMessage: String?

    private var commentService: MedicineCommentService {
        MedicineCommentService(context: context)
    }

    init(medicine: Medicine) {
        _medicine = ObservedObject(wrappedValue: medicine)
        _comments = FetchRequest(
            entity: MedicineComment.entity(),
            sortDescriptors: [NSSortDescriptor(key: "created_at", ascending: true)],
            predicate: NSPredicate(format: "medicine == %@", medicine)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            commentsList
            composer
        }
        .background(Color(.systemGroupedBackground))
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: max(0, MedicineCommentService.maxAttachmentsPerComment - totalDraftAttachmentCount),
            matching: .images
        )
        .onChange(of: selectedPhotoItems.count) { _ in
            processSelectedPhotos()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleImportedFiles(result)
        }
        .confirmationDialog("Aggiungi allegato", isPresented: $showAttachmentOptions) {
            Button("Foto") { showPhotoPicker = true }
            Button("File") { showFileImporter = true }
            Button("Annulla", role: .cancel) {}
        }
        .alert("Elimina commento", isPresented: deleteAlertBinding) {
            Button("Elimina", role: .destructive) {
                deletePendingComment()
            }
            Button("Annulla", role: .cancel) {
                pendingDeleteComment = nil
            }
        } message: {
            Text("Questa azione elimina anche gli allegati.")
        }
        .alert("Errore", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Operazione non riuscita.")
        }
    }

    private var commentsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if comments.isEmpty {
                        Text("Nessun commento")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(comments, id: \.objectID) { comment in
                            commentCard(comment)
                                .id(comment.objectID)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onChange(of: comments.count) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if isEditing {
                HStack {
                    Text("Modifica commento")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Annulla") {
                        resetDraft()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                }
            }

            if !activeExistingAttachments.isEmpty || !newAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(activeExistingAttachments, id: \.objectID) { attachment in
                            attachmentChip(
                                title: attachment.filename ?? "Allegato",
                                image: previewImage(for: attachment),
                                onRemove: { existingAttachmentsToDelete.insert(attachment.objectID) }
                            )
                        }
                        ForEach(newAttachments) { attachment in
                            attachmentChip(
                                title: attachment.filename,
                                image: attachment.previewImage,
                                onRemove: { newAttachments.removeAll { $0.id == attachment.id } }
                            )
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Scrivi un commento", text: $draftText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)

                Button {
                    showAttachmentOptions = true
                } label: {
                    Image(systemName: "paperclip.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(totalDraftAttachmentCount >= MedicineCommentService.maxAttachmentsPerComment)

                Button {
                    submitDraft()
                } label: {
                    Image(systemName: isEditing ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func commentCard(_ comment: MedicineComment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(Color(.systemBlue).opacity(0.2))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    if let text = comment.text, !text.isEmpty {
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    let attachments = sortedAttachments(for: comment)
                    if !attachments.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(attachments, id: \.objectID) { attachment in
                                Button {
                                    openAttachment(attachment)
                                } label: {
                                    HStack(spacing: 6) {
                                        if let image = previewImage(for: attachment) {
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 26, height: 26)
                                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                        } else {
                                            Image(systemName: "doc")
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(attachment.filename ?? "Allegato")
                                            .font(.caption)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Text(timestampLabel(for: comment))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                Button("Modifica") {
                    startEditing(comment)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)

                Button("Elimina", role: .destructive) {
                    pendingDeleteComment = comment
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
            }
            .padding(.leading, 38)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func attachmentChip(title: String, image: UIImage?, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: "doc")
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.caption)
                .lineLimit(1)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(.tertiarySystemBackground))
        )
    }

    private var isEditing: Bool {
        editingComment != nil
    }

    private var editingComment: MedicineComment? {
        guard let editingCommentID else { return nil }
        return comments.first { $0.objectID == editingCommentID }
    }

    private var activeExistingAttachments: [MedicineCommentAttachment] {
        existingAttachments.filter { !existingAttachmentsToDelete.contains($0.objectID) }
    }

    private var totalDraftAttachmentCount: Int {
        activeExistingAttachments.count + newAttachments.count
    }

    private var canSubmit: Bool {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty || totalDraftAttachmentCount > 0
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteComment != nil },
            set: { newValue in
                if !newValue {
                    pendingDeleteComment = nil
                }
            }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }

    private func submitDraft() {
        let inputs = newAttachments.map {
            MedicineCommentAttachmentInput(
                kind: $0.kind,
                filename: $0.filename,
                mimeType: $0.mimeType,
                uti: $0.uti,
                data: $0.data
            )
        }

        do {
            if let editing = editingComment {
                let deleting = existingAttachments.filter { existingAttachmentsToDelete.contains($0.objectID) }
                _ = try commentService.updateComment(
                    comment: editing,
                    text: draftText,
                    attachmentsToDelete: deleting,
                    newAttachments: inputs
                )
            } else {
                _ = try commentService.createComment(
                    medicine: medicine,
                    text: draftText,
                    newAttachments: inputs
                )
            }
            resetDraft()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startEditing(_ comment: MedicineComment) {
        editingCommentID = comment.objectID
        draftText = comment.text ?? ""
        existingAttachments = sortedAttachments(for: comment)
        existingAttachmentsToDelete = []
        newAttachments = []
    }

    private func resetDraft() {
        editingCommentID = nil
        draftText = ""
        existingAttachments = []
        existingAttachmentsToDelete = []
        newAttachments = []
        selectedPhotoItems = []
    }

    private func deletePendingComment() {
        guard let comment = pendingDeleteComment else { return }
        do {
            try commentService.deleteComment(comment)
            if editingCommentID == comment.objectID {
                resetDraft()
            }
            pendingDeleteComment = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func processSelectedPhotos() {
        let items = selectedPhotoItems
        guard !items.isEmpty else { return }
        let initialCount = totalDraftAttachmentCount

        Task {
            var imported: [DraftAttachment] = []
            for item in items {
                if initialCount + imported.count >= MedicineCommentService.maxAttachmentsPerComment {
                    break
                }
                guard let loadedData = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: loadedData),
                      let jpegData = image.jpegData(compressionQuality: 0.85) else {
                    continue
                }
                if jpegData.count > MedicineCommentService.maxAttachmentBytes {
                    continue
                }
                imported.append(
                    DraftAttachment(
                        kind: .photo,
                        filename: "photo_\(Int(Date().timeIntervalSince1970)).jpg",
                        mimeType: "image/jpeg",
                        uti: UTType.jpeg.identifier,
                        data: jpegData
                    )
                )
            }

            await MainActor.run {
                newAttachments.append(contentsOf: imported)
                selectedPhotoItems = []
            }
        }
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case let .failure(error):
            errorMessage = error.localizedDescription
        case let .success(urls):
            importFiles(urls)
        }
    }

    private func importFiles(_ urls: [URL]) {
        var imported: [DraftAttachment] = []
        for url in urls {
            if totalDraftAttachmentCount + imported.count >= MedicineCommentService.maxAttachmentsPerComment {
                break
            }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let data = try Data(contentsOf: url)
                if data.count > MedicineCommentService.maxAttachmentBytes {
                    continue
                }
                let type = UTType(filenameExtension: url.pathExtension)
                imported.append(
                    DraftAttachment(
                        kind: .file,
                        filename: url.lastPathComponent,
                        mimeType: type?.preferredMIMEType,
                        uti: type?.identifier,
                        data: data
                    )
                )
            } catch {
                errorMessage = "Impossibile leggere \(url.lastPathComponent)."
            }
        }
        newAttachments.append(contentsOf: imported)
    }

    private func previewImage(for attachment: MedicineCommentAttachment) -> UIImage? {
        guard attachment.kind == MedicineCommentAttachmentKind.photo.rawValue,
              let url = commentService.fileURL(for: attachment),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }

    private func openAttachment(_ attachment: MedicineCommentAttachment) {
        guard let url = commentService.fileURL(for: attachment) else { return }
        openURL(url)
    }

    private func sortedAttachments(for comment: MedicineComment) -> [MedicineCommentAttachment] {
        (comment.attachments ?? []).sorted {
            ($0.created_at ?? .distantPast) < ($1.created_at ?? .distantPast)
        }
    }

    private func timestampLabel(for comment: MedicineComment) -> String {
        guard let created = comment.created_at else { return "" }
        let createdText = Self.dateFormatter.string(from: created)
        if let updated = comment.updated_at, updated.timeIntervalSince(created) > 1 {
            return "Creato \(createdText) • Modificato \(Self.dateFormatter.string(from: updated))"
        }
        return createdText
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = comments.last else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.objectID, anchor: .bottom)
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private struct DraftAttachment: Identifiable {
        let id = UUID()
        let kind: MedicineCommentAttachmentKind
        let filename: String
        let mimeType: String?
        let uti: String?
        let data: Data

        var previewImage: UIImage? {
            guard kind == .photo else { return nil }
            return UIImage(data: data)
        }
    }
}
