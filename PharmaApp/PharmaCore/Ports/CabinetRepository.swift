import Foundation

public protocol CabinetRepository {
    func fetchAll() throws -> [CabinetSnapshot]
}
