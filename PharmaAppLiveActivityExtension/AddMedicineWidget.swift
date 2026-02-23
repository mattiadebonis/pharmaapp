import WidgetKit
import SwiftUI

struct AddMedicineWidgetView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
        }
        .widgetURL(URL(string: "pharmaapp://add"))
    }
}

struct AddMedicineWidget: Widget {
    let kind = "AddMedicineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StaticWidgetProvider()) { _ in
            if #available(iOSApplicationExtension 17.0, *) {
                AddMedicineWidgetView()
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                AddMedicineWidgetView()
            }
        }
        .configurationDisplayName("Aggiungi")
        .description("Aggiungi un farmaco")
        .supportedFamilies([.accessoryCircular])
    }
}
