import Foundation
import UIKit
import SwiftUI

enum AppConfiguration {
    static let productName = AppIdentity.productName
    static let bundleIdentifier = AppIdentity.bundleIdentifier
    static let maximumRecentDocuments = 8
    static let maximumScanPages = 20
    static let maximumSourcePageBytes: Int64 = 128 * 1_024 * 1_024
    static let maximumEditStrokes = 256
    static let maximumStrokePoints = 8_192
    static let maximumMarkStrokes = 128
    static let appGroupIdentifier: String? = nil
    static let supportedLanguages = DocumentLanguage.allCases.map(\.appIdentifier)
    static var defaultShareSubject: String { String(localized: "FruitySelia document") }
}

enum DocumentLanguage: CaseIterable {
    case english, czech, german, spanish, simplifiedChinese

    var appIdentifier: String {
        switch self {
        case .english: "en"
        case .czech: "cs"
        case .german: "de"
        case .spanish: "es"
        case .simplifiedChinese: "zh-Hans"
        }
    }

    var recognitionIdentifier: String {
        switch self {
        case .english: "en-US"
        case .czech: "cs-CZ"
        case .german: "de-DE"
        case .spanish: "es-ES"
        case .simplifiedChinese: appIdentifier
        }
    }
}

enum SpeechLanguage {
    case automatic
    case document(DocumentLanguage)

    var identifier: String? {
        switch self {
        case .automatic: nil
        case .document(let language): language.recognitionIdentifier
        }
    }
}

enum UserDefaultsKey {
    static let protectRecent = "protectRecent"
    static let shareSubject = "shareSubject"
    static let pendingNewScanIntent = "pendingNewScanIntent"
    static let defaultPDFFolderBookmark = "defaultPDFFolderBookmark"
    static let defaultImageFolderBookmark = "defaultImageFolderBookmark"
}

enum StorageLayout {
    static let appDirectory = "SeliaScan"
    static let recentDirectory = "Recent"
    static let marksDirectory = "Marks"
    static let originalsDirectory = "originals"
    static let revisionsDirectory = "revisions"
    static let thumbnailsDirectory = "thumbnails"
    static let revisionMarksDirectory = "revisions/marks"
    static let manifestFilename = "manifest.json"
    static let temporaryManifestFilename = "manifest.json.tmp"

    static func originalPageFilename(index: Int, extension fileExtension: String) -> String {
        "page-\(index + 1).\(fileExtension)"
    }

    static func thumbnailReference(index: Int) -> RelativeFileReference {
        RelativeFileReference("\(thumbnailsDirectory)/page-\(index + 1).\(FileExtension.jpeg)")
    }

    static func revisionReference(id: UUID, extension fileExtension: String) -> RelativeFileReference {
        RelativeFileReference("\(revisionsDirectory)/\(id.uuidString).\(fileExtension)")
    }

    static func markReference(id: UUID, extension fileExtension: String) -> RelativeFileReference {
        RelativeFileReference("\(revisionMarksDirectory)/\(id.uuidString).\(fileExtension)")
    }

    static func savedMarkMetadataFilename(id: UUID) -> String {
        "\(id.uuidString).\(FileExtension.json)"
    }
}

enum FileExtension {
    static let pdf = "pdf"
    static let jpeg = "jpg"
    static let png = "png"
    static let json = "json"
    static let drawing = "drawing"
    static let temporary = "tmp"
}

enum TemporaryFile {
    static let scanDirectoryPrefix = "seliascan-scan-"
    static let importPrefix = "seliascan-import-"
    static let pdfPagePrefix = "seliascan-pdf-page-"
    static let exportDirectoryPrefix = "seliascan-export-"
    static let imageExportDirectoryPrefix = "seliascan-images-"
    static let fixturePrefix = "seliascan-fixture-"

    static func importURL(extension fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(importPrefix)\(UUID().uuidString).\(fileExtension)")
    }
}

enum AppKeyboardShortcut {
    static let undo: KeyEquivalent = "z"
}

enum FilenameSanitizer {
    static func sanitize(_ filename: String) -> String {
        filename.replacingOccurrences(of: "/", with: "-")
    }
}

enum FileProtection {
    static let attributes: [FileAttributeKey: Any] = [
        .protectionKey: FileProtectionType.complete,
    ]
}

extension UIWindowScene { var keyWindow: UIWindow? { windows.first(where: \.isKeyWindow) } }
