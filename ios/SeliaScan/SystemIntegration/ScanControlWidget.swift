import WidgetKit
import SwiftUI
import AppIntents

@available(iOS 18.0, *)
struct ScanControlWidget: ControlWidget {
    private var scanURL: URL { AppRouteURL.newScan ?? URL(fileURLWithPath: "/") }
    var body: some ControlWidgetConfiguration { StaticControlConfiguration(kind: SystemIntegrationIdentifier.scanControl) { ControlWidgetButton(action: OpenURLIntent(scanURL)) { Label("Scan Document", systemImage: SystemImageName.scanDocument) } }.displayName("Scan Document").description("Open FruitySelia scanner") }
}
