import Foundation
import XCTest

final class ArchitectureGuardTests: XCTestCase {
    func testCoreDataImportsStayWithinAllowlist() throws {
        try assertImportsStayWithinAllowlist(
            regexPattern: #"^import\s+CoreData\b"#,
            allowlistFileName: "coredata-import-allowlist.txt",
            label: "CoreData"
        )
    }

    func testFirebaseImportsStayWithinAllowlist() throws {
        try assertImportsStayWithinAllowlist(
            regexPattern: #"^import\s+Firebase(Auth|Core)\b"#,
            allowlistFileName: "firebase-import-allowlist.txt",
            label: "Firebase"
        )
    }

    func testCriticalViewsAvoidFetchRequestAndManagedObjectID() throws {
        let criticalFiles = [
            "PharmaApp/Feature/Medicines/Cabinet/CabinetView.swift",
            "PharmaApp/Feature/Medicines/Medicine/MedicineDetail/MedicineDetailView.swift",
            "PharmaApp/Feature/Search/GlobalSearchView.swift",
            "PharmaApp/Feature/Adherence/AdherenceDashboardView.swift",
            "PharmaApp/Feature/Medicines/Medicine/MedicineDetail/TherapyForm/TherapyFormView.swift"
        ]

        for relativePath in criticalFiles {
            let fileURL = repoRootURL.appendingPathComponent(relativePath, isDirectory: false)
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertFalse(content.contains("@FetchRequest"), "\(relativePath) must not use @FetchRequest.")
            XCTAssertFalse(content.contains("NSManagedObjectID"), "\(relativePath) must not use NSManagedObjectID.")
        }
    }

    func testFeatureAndSettingsAvoidDirectContextSave() throws {
        let regex = try NSRegularExpression(
            pattern: #"\b(managedObjectContext|context)\.save\("#,
            options: []
        )

        let targetDirectories = [
            repoRootURL.appendingPathComponent("PharmaApp/Feature", isDirectory: true),
            repoRootURL.appendingPathComponent("PharmaApp/Settings", isDirectory: true)
        ]

        var offenders: [String] = []
        for directory in targetDirectories {
            offenders.append(contentsOf: try scanPatternMatches(in: directory, regex: regex))
        }

        XCTAssertTrue(
            offenders.isEmpty,
            """
            Direct context.save() usage is forbidden in Feature/Settings:
            \(offenders.sorted().joined(separator: "\n"))
            """
        )
    }

    func testFeatureAndSettingsAvoidFetchRequestAndObjectIDPatterns() throws {
        let forbiddenPatterns = [
            #"\b@FetchRequest\b"#,
            #"\bNSManagedObjectID\b"#,
            #"\bobjectID\b"#
        ]

        let targetDirectories = [
            repoRootURL.appendingPathComponent("PharmaApp/Feature", isDirectory: true),
            repoRootURL.appendingPathComponent("PharmaApp/Settings", isDirectory: true)
        ]

        var offenders: [String] = []
        for pattern in forbiddenPatterns {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            for directory in targetDirectories {
                offenders.append(contentsOf: try scanPatternMatches(in: directory, regex: regex))
            }
        }

        let uniqueOffenders = Array(Set(offenders)).sorted()
        XCTAssertTrue(
            uniqueOffenders.isEmpty,
            """
            Feature/Settings contain forbidden CoreData UI patterns:
            \(uniqueOffenders.joined(separator: "\n"))
            """
        )
    }

    func testSettingsAvoidCoreDataImports() throws {
        let regex = try NSRegularExpression(
            pattern: #"^import\s+CoreData\b"#,
            options: [.anchorsMatchLines]
        )
        let settingsDirectory = repoRootURL.appendingPathComponent("PharmaApp/Settings", isDirectory: true)
        let offenders = try scanPatternMatches(in: settingsDirectory, regex: regex).sorted()

        XCTAssertTrue(
            offenders.isEmpty,
            """
            Settings module must not import CoreData directly:
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    private func assertImportsStayWithinAllowlist(
        regexPattern: String,
        allowlistFileName: String,
        label: String
    ) throws {
        let regex = try NSRegularExpression(pattern: regexPattern, options: [.anchorsMatchLines])
        let sourceRoot = repoRootURL.appendingPathComponent("PharmaApp", isDirectory: true)
        let allowlistURL = repoRootURL
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent("architecture-baseline", isDirectory: true)
            .appendingPathComponent(allowlistFileName, isDirectory: false)

        let allowedImports = try loadAllowlist(from: allowlistURL)
        let currentImports = try scanImports(in: sourceRoot, regex: regex)
        let unexpectedImports = currentImports.subtracting(allowedImports).sorted()

        XCTAssertTrue(
            unexpectedImports.isEmpty,
            """
            Unexpected \(label) imports outside allowlist:
            \(unexpectedImports.joined(separator: "\n"))
            """
        )
    }

    private func scanImports(in sourceRoot: URL, regex: NSRegularExpression) throws -> Set<String> {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw NSError(
                domain: "ArchitectureGuardTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to enumerate source files."]
            )
        }

        var importedPaths = Set<String>()
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            guard regex.firstMatch(in: content, options: [], range: range) != nil else { continue }
            importedPaths.insert(relativePath(from: fileURL))
        }
        return importedPaths
    }

    private func scanPatternMatches(in sourceRoot: URL, regex: NSRegularExpression) throws -> [String] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw NSError(
                domain: "ArchitectureGuardTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to enumerate feature/settings files."]
            )
        }

        var matches: [String] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            if regex.firstMatch(in: content, options: [], range: range) != nil {
                matches.append(relativePath(from: fileURL))
            }
        }
        return matches
    }

    private func loadAllowlist(from url: URL) throws -> Set<String> {
        let raw = try String(contentsOf: url, encoding: .utf8)
        return Set(
            raw
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private func relativePath(from url: URL) -> String {
        let absolutePath = url.path
        let rootPrefix = repoRootURL.path + "/"
        if absolutePath.hasPrefix(rootPrefix) {
            return String(absolutePath.dropFirst(rootPrefix.count))
        }
        return absolutePath
    }

    private var repoRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
