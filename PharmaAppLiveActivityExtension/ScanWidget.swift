import WidgetKit
import SwiftUI

struct ScanWidgetView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "viewfinder")
                .font(.system(size: 24, weight: .semibold))
        }
        .widgetURL(URL(string: "pharmaapp://scan"))
    }
}

struct ScanWidget: Widget {
    let kind = "ScanWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StaticWidgetProvider()) { _ in
            if #available(iOSApplicationExtension 17.0, *) {
                ScanWidgetView()
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                ScanWidgetView()
            }
        }
        .configurationDisplayName("Scansiona")
        .description("Scansiona un farmaco")
        .supportedFamilies([.accessoryCircular])
    }
}
