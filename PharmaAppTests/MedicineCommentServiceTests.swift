import XCTest
import CoreData
@testable import PharmaApp

final class MedicineCommentServiceTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!
    private var rootURL: URL!
    private var service: MedicineCommentService!
    private var medicine: Medicine!

    override func setUpWithError() throws {
        container = try TestCoreDataFactory.makeContainer()
        context = container.viewContext
        medicine = try TestCoreDataFactory.makeMedicine(context: context)
        _ = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)
        try context.save()

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MedicineCommentServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        rootURL = tempRoot
        service = MedicineCommentService(context: context, rootURL: rootURL)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        service = nil
        medicine = nil
        context = nil
        container = nil
    }

    func testCreateCommentTextOnly() throws {
        let comment = try service.createComment(
            medicine: medicine,
            text: "Primo commento",
            newAttachments: []
        )

        XCTAssertEqual(comment.text, "Primo commento")
        XCTAssertEqual(comment.medicine?.objectID, medicine.objectID)
        XCTAssertEqual((comment.attachments ?? []).count, 0)
    }

    func testCreateCommentWithAttachment() throws {
        let input = MedicineCommentAttachmentInput(
            kind: .file,
            filename: "referto.pdf",
            mimeType: "application/pdf",
            uti: "com.adobe.pdf",
            data: Data("ciao".utf8)
        )

        let comment = try service.createComment(
            medicine: medicine,
            text: "",
            newAttachments: [input]
        )

        let attachments = comment.attachments ?? []
        XCTAssertEqual(attachments.count, 1)
        let attachment = try XCTUnwrap(attachments.first)
        let url = try XCTUnwrap(service.fileURL(for: attachment))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testUpdateCommentTextAndAttachments() throws {
        let firstInput = MedicineCommentAttachmentInput(
            kind: .file,
            filename: "old.txt",
            mimeType: "text/plain",
            uti: "public.plain-text",
            data: Data("old".utf8)
        )
        let comment = try service.createComment(
            medicine: medicine,
            text: "old text",
            newAttachments: [firstInput]
        )
        let oldAttachment = try XCTUnwrap(comment.attachments?.first)
        let oldURL = try XCTUnwrap(service.fileURL(for: oldAttachment))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path))

        let secondInput = MedicineCommentAttachmentInput(
            kind: .file,
            filename: "new.txt",
            mimeType: "text/plain",
            uti: "public.plain-text",
            data: Data("new".utf8)
        )

        _ = try service.updateComment(
            comment: comment,
            text: "new text",
            attachmentsToDelete: [oldAttachment],
            newAttachments: [secondInput]
        )

        XCTAssertEqual(comment.text, "new text")
        XCTAssertEqual((comment.attachments ?? []).count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        let newAttachment = try XCTUnwrap(comment.attachments?.first)
        let newURL = try XCTUnwrap(service.fileURL(for: newAttachment))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
    }

    func testDeleteCommentRemovesFiles() throws {
        let input = MedicineCommentAttachmentInput(
            kind: .file,
            filename: "delete-me.txt",
            mimeType: "text/plain",
            uti: "public.plain-text",
            data: Data("to-delete".utf8)
        )
        let comment = try service.createComment(
            medicine: medicine,
            text: "",
            newAttachments: [input]
        )
        let attachment = try XCTUnwrap(comment.attachments?.first)
        let url = try XCTUnwrap(service.fileURL(for: attachment))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        try service.deleteComment(comment)

        let fetch = MedicineComment.fetchRequest(for: medicine)
        let comments = try context.fetch(fetch)
        XCTAssertEqual(comments.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testDeleteAllCommentsCleansDirectory() throws {
        let fileInput = MedicineCommentAttachmentInput(
            kind: .file,
            filename: "note.txt",
            mimeType: "text/plain",
            uti: "public.plain-text",
            data: Data("abc".utf8)
        )
        let _ = try service.createComment(medicine: medicine, text: "uno", newAttachments: [fileInput])
        let _ = try service.createComment(medicine: medicine, text: "due", newAttachments: [])

        try service.deleteAllComments(for: medicine)

        let fetch = MedicineComment.fetchRequest(for: medicine)
        let comments = try context.fetch(fetch)
        XCTAssertEqual(comments.count, 0)

        let medicineDir = rootURL.appendingPathComponent(medicine.id.uuidString, isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: medicineDir.path))
    }
}
