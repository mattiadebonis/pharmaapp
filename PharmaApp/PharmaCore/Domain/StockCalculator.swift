import Foundation

public struct StockCalculator {
    public init() {}

    public func deltaUnits(for logType: LogType, packageNumero: Int) -> Int {
        let packSize = max(1, packageNumero)
        switch logType {
        case .purchase:
            return packSize
        case .purchaseUndo:
            return -packSize
        case .intake, .stockAdjustment:
            return -1
        case .intakeUndo:
            return 1
        default:
            return 0
        }
    }

    public func unitsFromLogs(_ logs: [LogEntry], packageId: PackageId, packageNumero: Int, singlePackage: Bool) -> Int {
        let packSize = max(1, packageNumero)
        let matchesPackage: (LogEntry) -> Bool = { log in
            if let logPackageId = log.packageId { return logPackageId == packageId }
            return singlePackage
        }

        let purchases = logs.filter { $0.type == .purchase && matchesPackage($0) }.count
        let purchaseUndo = logs.filter { $0.type == .purchaseUndo && matchesPackage($0) }.count
        let increments = logs.filter {
            ($0.type == .intakeUndo) && matchesPackage($0)
        }.count
        let decrements = logs.filter {
            ($0.type == .intake || $0.type == .stockAdjustment) && matchesPackage($0)
        }.count

        return purchases * packSize + increments - decrements - (purchaseUndo * packSize)
    }

    public func autonomyDays(
        leftoverUnits: Double,
        dailyUsage: Double
    ) -> Int? {
        guard leftoverUnits > 0 else { return leftoverUnits <= 0 ? 0 : nil }
        guard dailyUsage > 0 else { return nil }
        return max(0, Int(floor(leftoverUnits / dailyUsage)))
    }
}
