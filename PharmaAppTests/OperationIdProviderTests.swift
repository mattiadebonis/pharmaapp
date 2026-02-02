import XCTest
@testable import PharmaApp

final class OperationIdProviderTests: XCTestCase {
    func testOperationIdProviderReuseWithinTTLAndClear() {
        let provider = OperationIdProvider.shared
        let medicineId = UUID()
        let packageId = UUID()
        let key = OperationKey.medicineAction(
            action: .purchase,
            medicineId: medicineId,
            packageId: packageId,
            source: .today
        )

        let first = provider.operationId(for: key, ttl: 60)
        let second = provider.operationId(for: key, ttl: 60)
        XCTAssertEqual(first, second, "OperationId should be reused within TTL")

        provider.clear(key)
        let third = provider.operationId(for: key, ttl: 60)
        XCTAssertNotEqual(first, third, "OperationId should change after clear")
    }
}
