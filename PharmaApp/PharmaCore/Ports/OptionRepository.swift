import Foundation

public protocol OptionRepository {
    func fetchCurrentOption() throws -> OptionSnapshot?
}
