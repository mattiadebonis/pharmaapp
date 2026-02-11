import Foundation
import UIKit

enum PdfReportError: Error {
    case writeFailed
}

struct PdfReportBuilder {
    func buildReport(data: ReportData) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Report Aderenza",
            kCGPDFContextCreator as String: "PharmaApp"
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let pdfData = renderer.pdfData { context in
            var y: CGFloat = 0
            func beginPage() {
                context.beginPage()
                y = 36
            }

            beginPage()

            let titleFont = UIFont.systemFont(ofSize: 22, weight: .semibold)
            let headerFont = UIFont.systemFont(ofSize: 15, weight: .semibold)
            let bodyFont = UIFont.systemFont(ofSize: 12, weight: .regular)
            let noteFont = UIFont.systemFont(ofSize: 10, weight: .regular)

            let contentWidth = pageRect.width - 72
            let leftX: CGFloat = 36

            y += drawText("Report Aderenza", font: titleFont, atX: leftX, y: y, width: contentWidth)
            y += 8

            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "it_IT")
            dateFormatter.dateStyle = .long
            let dateLine = "Data: \(dateFormatter.string(from: data.generatedAt)) • Periodo: \(data.period.reportLabel)"
            y += drawText(dateLine, font: bodyFont, color: .secondaryLabel, atX: leftX, y: y, width: contentWidth)
            y += 16

            y += drawText("Aderenza generale", font: headerFont, atX: leftX, y: y, width: contentWidth)
            y += 8

            let planned = data.generalPlanned
            let taken = data.generalTaken
            let percentText: String
            if planned > 0 {
                let percent = Int(round(Double(taken) / Double(planned) * 100))
                percentText = "Aderenza: \(percent)%"
            } else {
                percentText = "Aderenza: —"
            }

            y += drawText("Dosi previste: \(planned)", font: bodyFont, atX: leftX, y: y, width: contentWidth)
            y += 4
            y += drawText("Dosi assunte: \(taken)", font: bodyFont, atX: leftX, y: y, width: contentWidth)
            y += 4
            y += drawText(percentText, font: bodyFont, atX: leftX, y: y, width: contentWidth)
            y += 6
            y += drawText(data.trendLabel, font: bodyFont, color: .secondaryLabel, atX: leftX, y: y, width: contentWidth)
            y += 20

            y += drawText("Terapie", font: headerFont, atX: leftX, y: y, width: contentWidth)
            y += 8

            let tableWidth = contentWidth
            let colName = tableWidth * 0.5
            let colAdherence = tableWidth * 0.3
            let colParam = tableWidth * 0.2

            func drawTableHeader() {
                let headerHeight: CGFloat = 22
                let rect = CGRect(x: leftX, y: y, width: tableWidth, height: headerHeight)
                context.cgContext.setFillColor(UIColor.systemGray6.cgColor)
                context.cgContext.fill(rect)
                drawText("Terapia", font: bodyFont, atX: leftX + 6, y: y + 4, width: colName - 12)
                drawText("Aderenza", font: bodyFont, atX: leftX + colName, y: y + 4, width: colAdherence - 6)
                drawText("Parametri", font: bodyFont, atX: leftX + colName + colAdherence, y: y + 4, width: colParam - 6)
                y += headerHeight + 4
            }

            drawTableHeader()

            for row in data.rows {
                let rowHeight: CGFloat = 18
                let totalHeight = rowHeight + 6

                if y + totalHeight > pageRect.height - 36 {
                    beginPage()
                    drawTableHeader()
                }

                let adherenceText: String
                if row.planned > 0 {
                    let percent = Int(round(Double(row.taken) / Double(row.planned) * 100))
                    adherenceText = "\(row.taken)/\(row.planned) (\(percent)%)"
                } else {
                    adherenceText = "—"
                }

                _ = drawText(row.name, font: bodyFont, atX: leftX + 6, y: y, width: colName - 12)
                _ = drawText(adherenceText, font: bodyFont, atX: leftX + colName, y: y, width: colAdherence - 6)
                _ = drawText(row.hasMeasurements ? "Sì" : "No", font: bodyFont, atX: leftX + colName + colAdherence, y: y, width: colParam - 6)

                y += rowHeight

                y += 6
            }

            let comments: [String] = data.rows.compactMap { row in
                guard let note = row.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else {
                    return nil
                }
                return "\(row.name): \(note)"
            }

            if !comments.isEmpty {
                let sectionGap: CGFloat = 10
                let sectionHeaderHeight = textHeight("Commenti", font: headerFont, width: contentWidth)
                if y + sectionGap + sectionHeaderHeight + 8 > pageRect.height - 36 {
                    beginPage()
                }

                y += sectionGap
                y += drawText("Commenti", font: headerFont, atX: leftX, y: y, width: contentWidth)
                y += 8

                for comment in comments {
                    let line = "• \(comment)"
                    let lineHeight = textHeight(line, font: noteFont, width: contentWidth)
                    if y + lineHeight + 4 > pageRect.height - 36 {
                        beginPage()
                    }
                    y += drawText(line, font: noteFont, color: .secondaryLabel, atX: leftX, y: y, width: contentWidth)
                    y += 4
                }
            }
        }

        let fileName = "adherence-report-\(UUID().uuidString).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try pdfData.write(to: url, options: .atomic)
            return url
        } catch {
            throw PdfReportError.writeFailed
        }
    }

    @discardableResult
    private func drawText(
        _ text: String,
        font: UIFont,
        color: UIColor = .label,
        atX x: CGFloat,
        y: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let size = text.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).size
        let rect = CGRect(x: x, y: y, width: width, height: ceil(size.height))
        (text as NSString).draw(in: rect, withAttributes: attributes)
        return ceil(size.height)
    }

    private func textHeight(
        _ text: String,
        font: UIFont,
        width: CGFloat
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
        let size = text.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).size
        return ceil(size.height)
    }
}
