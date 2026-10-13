import WidgetKit
import SwiftUI
@main
struct LittleLogWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LittleLogWidgets()
        CareSummaryWidget()
        HomeQuickLogWidget()
        PeeLockScreenWidget()
        PooLockScreenWidget()
        BothLockScreenWidget()
        BottleLockScreenWidget()
    }
}
