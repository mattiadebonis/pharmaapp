import Foundation
import Combine

// MARK: - SyncState

/// Observable state of the sync system.
@MainActor
final class SyncState: ObservableObject {
    @Published var status: SyncStatus = .idle
    @Published var pendingCount: Int = 0
    @Published var lastSyncAt: Date?
    @Published var lastError: String?

    enum SyncStatus: String, Equatable {
        case idle          // No sync in progress, fully up to date
        case syncing       // Currently flushing the mutation queue
        case offline       // Device is offline, mutations are queued
        case error         // Last sync attempt failed
    }
}

// MARK: - SyncCoordinator

/// Orchestrates offline mutation queuing and background sync with the FastAPI backend.
///
/// Behavior:
/// - **Online writes**: Enqueue mutation + immediately attempt flush.
/// - **Offline writes**: Enqueue mutation; flush automatically when connectivity restores.
/// - **Conflicts**: Server wins — a full bootstrap refresh is triggered after any failed mutation
///   to resync the local Core Data mirror.
/// - **Queue order**: Strict FIFO — mutations are flushed in creation order.
@MainActor
final class SyncCoordinator {

    // MARK: - Dependencies

    private let client: FastAPIClient
    private let dataSync: FastAPIDataSync
    private let mutationStore: PendingMutationStore
    private let networkMonitor: NetworkMonitor
    let state: SyncState

    // MARK: - Private State

    private var isFlushing = false
    private var connectivityTask: Task<Void, Never>?

    // MARK: - Init

    init(
        client: FastAPIClient,
        dataSync: FastAPIDataSync,
        networkMonitor: NetworkMonitor,
        mutationStore: PendingMutationStore? = nil
    ) {
        self.client = client
        self.dataSync = dataSync
        self.networkMonitor = networkMonitor
        self.mutationStore = mutationStore ?? PendingMutationStore()
        self.state = SyncState()
    }

    // MARK: - Lifecycle

    /// Start the coordinator: load persisted queue, start listening for connectivity changes.
    func start() async {
        await mutationStore.load()
        let pendingCount = await mutationStore.count
        state.pendingCount = pendingCount
        if pendingCount > 0 && !networkMonitor.isOnline {
            state.status = .offline
        }

        // Listen for connectivity restoration
        connectivityTask = Task { [weak self] in
            guard let self else { return }
            for await _ in self.networkMonitor.onConnectivityRestored() {
                await self.flushQueue()
            }
        }

        // If already online and there are pending mutations, flush immediately
        if networkMonitor.isOnline && pendingCount > 0 {
            await flushQueue()
        }
    }

    /// Stop the coordinator and cancel listeners.
    func stop() {
        connectivityTask?.cancel()
        connectivityTask = nil
    }

    // MARK: - Enqueue Mutation

    /// Enqueue a write operation. If online, immediately attempts to flush.
    func enqueue(
        endpoint: String,
        method: PendingMutation.HTTPMethod,
        body: (some Encodable)? = nil as Data?,
        operationId: UUID? = nil
    ) {
        let mutation = PendingMutation(
            endpoint: endpoint,
            method: method,
            body: body,
            operationId: operationId
        )
        Task {
            await mutationStore.enqueue(mutation)
            state.pendingCount = await mutationStore.count
            if networkMonitor.isOnline {
                await flushQueue()
            } else {
                state.status = .offline
            }
        }
    }

    /// Enqueue a write operation with pre-encoded JSON data.
    func enqueueRaw(
        endpoint: String,
        method: PendingMutation.HTTPMethod,
        bodyJSON: Data?,
        operationId: UUID? = nil
    ) {
        let mutation = PendingMutation(
            endpoint: endpoint,
            method: method,
            rawBodyJSON: bodyJSON,
            operationId: operationId
        )
        Task {
            await mutationStore.enqueue(mutation)
            state.pendingCount = await mutationStore.count
            if networkMonitor.isOnline {
                await flushQueue()
            } else {
                state.status = .offline
            }
        }
    }

    // MARK: - Queue Flushing

    /// Attempts to flush all pending mutations in FIFO order.
    /// On any failure, stops and triggers a bootstrap refresh.
    func flushQueue() async {
        guard !isFlushing else { return }
        isFlushing = true
        state.status = .syncing

        defer {
            isFlushing = false
        }

        var didFlushAny = false

        while let mutation = await mutationStore.peek() {
            guard networkMonitor.isOnline else {
                state.status = .offline
                return
            }

            await mutationStore.markSyncing(id: mutation.id)

            do {
                try await executeMutation(mutation)
                await mutationStore.markSynced(id: mutation.id)
                didFlushAny = true
                state.pendingCount = await mutationStore.count
                fastAPISyncLog("Flushed: \(mutation.method.rawValue) \(mutation.endpoint)")
            } catch {
                let errorMessage = error.localizedDescription
                await mutationStore.markFailed(id: mutation.id, error: errorMessage)
                state.pendingCount = await mutationStore.count
                state.lastError = errorMessage
                state.status = .error
                fastAPISyncLog("Flush failed: \(mutation.endpoint) — \(errorMessage)")

                // On conflict, pull fresh data from server to reconcile
                do {
                    try await dataSync.refreshFromBootstrap()
                    fastAPISyncLog("Bootstrap refresh after conflict completed")
                } catch {
                    fastAPISyncLog("Bootstrap refresh failed: \(error)")
                }
                return
            }
        }

        // All mutations flushed — refresh from server for full consistency
        if didFlushAny {
            do {
                try await dataSync.refreshFromBootstrap()
                state.lastSyncAt = Date()
                fastAPISyncLog("Post-flush bootstrap refresh completed")
            } catch {
                fastAPISyncLog("Post-flush bootstrap refresh failed: \(error)")
            }
        }

        state.status = .idle
        state.lastError = nil
    }

    /// Force a full bootstrap refresh, discarding any conflict state.
    func forceRefresh() async {
        state.status = .syncing
        do {
            try await dataSync.performBootstrapSync()
            state.lastSyncAt = Date()
            state.status = .idle
            state.lastError = nil
        } catch {
            state.lastError = error.localizedDescription
            state.status = .error
        }
    }

    // MARK: - Mutation Execution

    /// Execute a single mutation against the FastAPI backend.
    private func executeMutation(_ mutation: PendingMutation) async throws {
        switch mutation.method {
        case .post:
            if let body = mutation.bodyJSON {
                let _: IgnoredResponse = try await client.postRaw(mutation.endpoint, bodyData: body)
            } else {
                let _: IgnoredResponse = try await client.postRaw(mutation.endpoint, bodyData: Data())
            }

        case .put:
            if let body = mutation.bodyJSON {
                let _: IgnoredResponse = try await client.putRaw(mutation.endpoint, bodyData: body)
            } else {
                let _: IgnoredResponse = try await client.putRaw(mutation.endpoint, bodyData: Data())
            }

        case .delete:
            try await client.delete(mutation.endpoint)

        case .get:
            break // Reads are never queued
        }
    }
}

// MARK: - IgnoredResponse

/// A decodable type that accepts any JSON response when we don't need the response body.
private struct IgnoredResponse: Decodable {
    init(from decoder: Decoder) throws {
        // Accept anything — we only care that the request succeeded (2xx)
        _ = try? decoder.singleValueContainer()
    }
}

// MARK: - Logging

private func fastAPISyncLog(_ message: String) {
    print("[SyncCoordinator] \(message)")
}
