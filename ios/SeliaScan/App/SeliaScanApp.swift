import SwiftUI
import UIKit

@main struct SeliaScanApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    var body: some Scene { WindowGroup { ContentView().environmentObject(state).onOpenURL { state.handle(url: $0) } } }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) { if shortcutItem.type == SystemIntegrationIdentifier.newScanQuickAction, let url = AppRouteURL.newScan { application.open(url); completionHandler(true) } else { completionHandler(false) } }
}
