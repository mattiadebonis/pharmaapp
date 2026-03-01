import Foundation

public struct CabinetSnapshot: Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let isShared: Bool

    public init(id: UUID, name: String, isShared: Bool) {
        self.id = id
        self.name = name
        self.isShared = isShared
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: CabinetSnapshot, rhs: CabinetSnapshot) -> Bool {
        lhs.id == rhs.id
    }
}
