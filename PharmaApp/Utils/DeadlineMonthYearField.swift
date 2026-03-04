import SwiftUI

struct DeadlineMonthYearField: View {
    @Binding var month: String
    @Binding var year: String

    var placeholder: String = "MM/YYYY"
    var onChange: (() -> Void)? = nil

    var body: some View {
        TextField(
            placeholder,
            text: Binding(
                get: { formattedValue(month: month, year: year) },
                set: applyInput(_:)
            )
        )
        .keyboardType(.numberPad)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(.body.monospacedDigit())
    }

    private func applyInput(_ value: String) {
        let digits = value.filter(\.isNumber)
        let nextMonth = String(digits.prefix(2))
        let nextYear = String(digits.dropFirst(min(2, digits.count)).prefix(4))

        if month != nextMonth {
            month = nextMonth
        }
        if year != nextYear {
            year = nextYear
        }

        onChange?()
    }

    private func formattedValue(month: String, year: String) -> String {
        guard !month.isEmpty || !year.isEmpty else { return "" }
        return year.isEmpty ? "\(month)/" : "\(month)/\(year)"
    }
}
