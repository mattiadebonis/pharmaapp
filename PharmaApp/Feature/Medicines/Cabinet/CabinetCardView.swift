import SwiftUI
import CoreData

struct CabinetCardView: View {
    let cabinet: Cabinet

    static let textIndent: CGFloat = Layout.leadingIconWidth + Layout.leadingSpacing

    private enum Layout {
        static let leadingIconWidth: CGFloat = 24
        static let leadingSpacing: CGFloat = 18
        static let contentSpacing: CGFloat = 4
        static let subtitleBlockSpacing: CGFloat = 2
        static let therapyLineSpacing: CGFloat = 3
    }
    
    var body: some View {
        let subtitle = makeDrawerSubtitle(drawer: cabinet, now: Date())
        HStack(alignment: .top, spacing: Layout.leadingSpacing) {
            leadingIcon
            VStack(alignment: .leading, spacing: Layout.contentSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(cabinet.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .layoutPriority(1)
                    Spacer(minLength: 6)
                    HStack(spacing: 4) {
                        Text("\(therapyCount)")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                }
                if let subtitle {
                    VStack(alignment: .leading, spacing: Layout.subtitleBlockSpacing) {
                        Text(subtitle.line1)
                            .font(subtitleFont)
                            .foregroundStyle(subtitleColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        VStack(alignment: .leading, spacing: Layout.therapyLineSpacing) {
                            ForEach(Array(subtitle.therapyLines.enumerated()), id: \.offset) { _, line in
                                therapyLineText(line)
                                    .font(subtitleFont)
                                    .foregroundStyle(subtitleColor)
                                    .lineLimit(nil)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.trailing, 4)
        .contentShape(Rectangle())
        .background(Color.clear)
    }
    
    private var leadingIcon: some View {
        Image(systemName: "cross.case.fill")
            .font(.system(size: 19, weight: .regular))
            .foregroundStyle(baseAccentColor)
            .frame(width: Layout.leadingIconWidth, height: Layout.leadingIconWidth, alignment: .center)
    }
    
    private var subtitleColor: Color {
        Color.primary.opacity(0.45)
    }

    private var subtitleFont: Font {
        .system(size: 15, weight: .regular)
    }

    private func therapyLineText(_ line: TherapyLine) -> Text {
        if let prefix = line.prefix, !prefix.isEmpty {
            return Text(prefix)
                + Text(" ")
                + Text(Image(systemName: "repeat"))
                + Text(" ")
                + Text(line.description)
        }
        return Text(line.description)
    }
    
    private var baseAccentColor: Color {
        .accentColor
    }

    private var therapyCount: Int {
        let unique = Set(therapiesInCabinet.map(\.objectID))
        return unique.count
    }
    
    // MARK: - Helpers
    private var entries: [MedicinePackage] {
        Array(cabinet.medicinePackages ?? [])
    }

    private var entriesWithTherapy: [MedicinePackage] {
        entries.filter { !therapies(for: $0).isEmpty }
    }

    private var therapiesInCabinet: [Therapy] {
        entriesWithTherapy.flatMap { therapies(for: $0) }
    }

    private func therapies(for entry: MedicinePackage) -> [Therapy] {
        if let set = entry.therapies, !set.isEmpty {
            return Array(set)
        }
        let all = entry.medicine.therapies as? Set<Therapy> ?? []
        return all.filter { $0.package == entry.package }
    }
}
