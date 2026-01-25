import SwiftUI
import UIKit

// Icona calendario con numero del giorno
struct TodayCalendarIcon: View {
    let day: Int

    var body: some View {
        let symbolName = "\(day).calendar"
        if let uiImage = UIImage(systemName: symbolName) {
            Image(uiImage: uiImage)
                .font(.system(size: 18, weight: .regular))
        } else {
            ZStack(alignment: .center) {
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .regular))
                Text("\(day)")
                    .font(.system(size: 11, weight: .semibold))
                    .offset(y: 2)
            }
        }
    }
}

