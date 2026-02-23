import WidgetKit
import SwiftUI

@main
struct PharmaAppLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        CriticalDoseLiveActivityWidget()
        RefillLiveActivityWidget()
        CabinetSummaryWidget()
        ScanWidget()
        AddMedicineWidget()
    }
}
