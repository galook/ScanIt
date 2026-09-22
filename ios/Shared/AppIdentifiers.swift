import Foundation

enum AppIdentity {
    // Keep the historical bundle identifier and URL scheme for compatibility.
    static let productName = "FruitySelia"
    static let bundleIdentifier = "com.majkeylab.seliascan"
}

enum AppRouteURL {
    static let scheme = "seliascan"
    static let newScanHost = "new-scan"

    static var newScan: URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = newScanHost
        return components.url
    }
}

enum SystemIntegrationIdentifier {
    static let newScanQuickAction = "\(AppIdentity.bundleIdentifier).newscan"
    static let scanControl = "\(AppIdentity.bundleIdentifier).scan"
}

enum SystemImageName {
    static let scanDocument = "doc.viewfinder"
    static let signature = "signature"
}

enum LaunchArgument {
    static let uiTesting = "-ui-testing"
    static let fixtureScanner = "-fixture-scanner"
}

enum AutomationIdentifier {
    enum Result {
        static let openViewer = "result.openViewer"
        static let pageIndicator = "result.pageIndicator"
        static let recent = "result.recent"
        static let fileDetails = "result.fileDetails"
        static let signStamp = "result.signStamp"
        static let actions = "result.actions"
        static let share = "result.share"
        static let pagePreview = "result.pagePreview"
    }

    enum Viewer {
        static let done = "viewer.done"
        static let pageIndicator = "viewer.pageIndicator"
    }

    enum Recent {
        static let list = "recent.list"
    }

    enum FileDetails {
        static let cancel = "fileDetails.cancel"
        static let save = "fileDetails.save"
    }

    enum Actions {
        static let reorderPages = "actions.reorderPages"
        static let done = "actions.done"
    }

    enum Organizer {
        static let list = "organizer.list"
        static let done = "organizer.done"
    }

    enum MarkEditor {
        static let cancel = "markEditor.cancel"
    }
}
