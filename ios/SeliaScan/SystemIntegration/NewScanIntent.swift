import AppIntents

struct NewScanIntent: AppIntent {
    static let title: LocalizedStringResource = "New Scan"
    static let description = IntentDescription("Open FruitySelia directly into document scanning.")
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult { UserDefaults.standard.set(true, forKey: UserDefaultsKey.pendingNewScanIntent); return .result() }
}
struct SeliaScanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] { AppShortcut(intent: NewScanIntent(), phrases: ["New scan in \(.applicationName)", "Scan a document with \(.applicationName)"], shortTitle: "New Scan", systemImageName: "doc.viewfinder") }
}
