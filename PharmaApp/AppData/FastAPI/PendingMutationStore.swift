import Foundation

// MARK: - PendingMutation

/// Represents a single write operation that needs to be sent to the FastAPI backend.
/// Stored as JSON in a local file for persistence across app restarts.
struct PendingMutation: Codable, Identifiable, Sendable {
    let id: UUID
    let operationId: UUID?
    let endpoint: String
    let method: HTTPMethod
    let bodyJSON: Data?
    let createdAt: Date
    var retryCount: Int
    var lastError: String?
    var status: MutationStatus

    enum HTTPMethod: String, Codable, Sendable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    enum MutationStatus: String, Codable, Sendable {
        case pending
        case syncing
        case failed
        case synced
    }

    init(
        endpoint: String,
        method: HTTPMethod,
        body: (some Encodable)? = nil as Data?,
        operationId: UUID? = nil
    ) {
        self.id = UUID()
        self.operationId = operationId
        self.endpoint = endpoint
        self.method = method
        self.createdAt = Date()
        self.retryCount = 0
        self.lastError = nil
        self.status = .pending

        if let body {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            self.bodyJSON = try? encoder.encode(body)
        } else {
            self.bodyJSON = nil
        }
    }

    /// Init with raw JSON data (for non-Encodable callers).
    init(
        endpoint: String,
        method: HTTPMethod,
        rawBodyJSON: Data?,
        operationId: UUID? = nil
    ) {
        self.id = UUID()
        self.operationId = operationId
        self.endpoint = endpoint
        self.method = method
        self.bodyJSON = rawBodyJSON
        self.createdAt = Date()
        self.retryCount = 0
        self.lastError = nil
        self.status = .pending
    }
}

// MARK: - PendingMutationStore

/// Persists a FIFO queue of pending mutations to a JSON file.
/// Thread-safe via actor isolation.
actor PendingMutationStore {

    // MARK: - Constants

    private static let maxRetries = 5
    private let fileURL: URL

    // MARK: - State

    private var mutations: [PendingMutation] = []

    // MARK: - Init

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("PharmaApp", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        self.fileURL = dir.appendingPathComponent("pending_mutations.json")
    }

    // MARK: - Load / Save

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            mutations = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            mutations = try JSONDecoder().decode([PendingMutation].self, from: data)
            // Remove already-synced items that may have been left over
            mutations.removeAll { $0.status == .synced }
        } catch {
            print("[PendingMutationStore] Failed to load: \(error)")
            mutations = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(mutations)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[PendingMutationStore] Failed to save: \(error)")
        }
    }

    // MARK: - Queue Operations

    /// Add a mutation to the end of the queue.
    func enqueue(_ mutation: PendingMutation) {
        // Dedup by operation_id if present
        if let opId = mutation.operationId,
           mutations.contains(where: { $0.operationId == opId }) {
            return
        }
        mutations.append(mutation)
        save()
    }

    /// Returns the next pending mutation (FIFO order), or nil if the queue is empty.
    func peek() -> PendingMutation? {
        mutations.first { $0.status == .pending || $0.status == .failed }
    }

    /// Returns all pending/failed mutations in FIFO order.
    func allPending() -> [PendingMutation] {
        mutations.filter { $0.status == .pending || $0.status == .failed }
    }

    /// Mark a mutation as currently syncing.
    func markSyncing(id: UUID) {
        guard let idx = mutations.firstIndex(where: { $0.id == id }) else { return }
        mutations[idx].status = .syncing
        save()
    }

    /// Mark a mutation as successfully synced and remove it from the queue.
    func markSynced(id: UUID) {
        mutations.removeAll { $0.id == id }
        save()
    }

    /// Mark a mutation as failed with an error message. Increments retry count.
    func markFailed(id: UUID, error: String) {
        guard let idx = mutations.firstIndex(where: { $0.id == id }) else { return }
        mutations[idx].status = .failed
        mutations[idx].retryCount += 1
        mutations[idx].lastError = error
        // Remove permanently failed mutations
        if mutations[idx].retryCount >= Self.maxRetries {
            print("[PendingMutationStore] Mutation \(id) exceeded max retries, discarding")
            mutations.remove(at: idx)
        }
        save()
    }

    /// Number of pending + failed mutations.
    var count: Int {
        mutations.filter { $0.status != .synced }.count
    }

    /// Whether there are any unsynced mutations.
    var hasPending: Bool {
        mutations.contains { $0.status == .pending || $0.status == .failed }
    }

    /// Clears all mutations.
    func clearAll() {
        mutations.removeAll()
        save()
    }
}
