import SwiftUI
@preconcurrency import ScoopCardlink

// MARK: - Per-row status

enum DeleteStatus: Equatable {
    case idle
    case deleting
    case deleted(env: String)
    case failed(message: String)
}

// MARK: - View model

/// Wraps the Kotlin `ErezeptDeleteClient` for the conference demo delete feature.
///
/// The app does not know which gematik environment (DEV or RU) a prescription lives in
/// — that's a backend-only setting. Individual deletes start with `preferredEnv`, falling
/// through to the other env only on HTTP 404. For the "Delete all" batch, the first
/// successful delete locks in the env for the rest of the batch.
///
/// Mutations are performed on the main actor (SwiftUI views `Task { }` defaults to that)
/// so `@Published` updates publish to the main thread.
final class PrescriptionDeleteViewModel: ObservableObject {
    @Published private var statuses: [String: DeleteStatus] = [:]
    @Published private(set) var lastGoodEnv: String?
    @Published private(set) var isDeletingAll: Bool = false

    private let client: ErezeptDeleteClient
    private let onTrace: (String) -> Void

    init(environment: CardlinkEnvironment, username: String, password: String, onTrace: @escaping (String) -> Void = { _ in }) {
        self.client = ErezeptDeleteClient(environment: environment, username: username, password: password)
        self.onTrace = onTrace
    }

    deinit { client.close() }

    func status(for key: String) -> DeleteStatus {
        statuses[key] ?? .idle
    }

    func remainingCount(for keys: [String]) -> Int {
        keys.filter { key in
            if case .deleted = statuses[key] ?? .idle { return false }
            return true
        }.count
    }

    /// Delete a single prescription. No-op if already deleting or deleted.
    func delete(key: String, taskId: String, accessCode: String) async {
        switch statuses[key] ?? .idle {
        case .deleting, .deleted: return
        default: break
        }
        statuses[key] = .deleting
        let env = lastGoodEnv ?? "dev"
        await performDelete(key: key, taskId: taskId, accessCode: accessCode, preferredEnv: env)
    }

    /// Delete every entry in [items] sequentially. The first success sets the preferred env.
    func deleteAll(_ items: [(key: String, taskId: String, accessCode: String)]) async {
        guard !isDeletingAll else { return }
        isDeletingAll = true
        defer { isDeletingAll = false }
        for item in items {
            switch statuses[item.key] ?? .idle {
            case .deleting, .deleted: continue
            default: break
            }
            statuses[item.key] = .deleting
            let env = lastGoodEnv ?? "dev"
            await performDelete(key: item.key, taskId: item.taskId, accessCode: item.accessCode, preferredEnv: env)
        }
    }

    private func performDelete(key: String, taskId: String, accessCode: String, preferredEnv: String) async {
        let shortId = String(taskId.prefix(12))
        do {
            let result = try await client.delete(taskId: taskId, accessCode: accessCode, preferredEnv: preferredEnv)
            statuses[key] = mapResult(result, shortId: shortId)
            if case .deleted(let env) = statuses[key] {
                lastGoodEnv = env
            }
        } catch {
            onTrace("Delete \(shortId)… threw: \(error.localizedDescription)")
            statuses[key] = .failed(message: error.localizedDescription)
        }
    }

    private func mapResult(_ result: ErezeptDeleteClient.DeleteResult, shortId: String) -> DeleteStatus {
        switch onEnum(of: result) {
        case .success(let s):
            onTrace("Deleted \(shortId)… on \(s.envUsed)")
            return .deleted(env: s.envUsed)
        case .notFoundInAnyEnv(let n):
            onTrace("Not found in \(n.triedEnvs.joined(separator: "+")) for \(shortId)…")
            return .failed(message: "Not found in DEV or RU")
        case .httpError(let h):
            onTrace("HTTP \(h.statusCode) on \(h.envUsed): \(h.body.prefix(160))")
            return .failed(message: "HTTP \(h.statusCode) (\(h.envUsed))")
        case .networkError(let n):
            onTrace("Network error on \(n.envUsed): \(n.message)")
            return .failed(message: "Network: \(String(n.message.prefix(80)))")
        case .authFailed(let a):
            onTrace("Auth failed: \(a.message)")
            return .failed(message: "Auth: \(String(a.message.prefix(80)))")
        }
    }
}

// MARK: - Helpers

/// First (taskId, accessCode) pair found in [xml], or `nil`.
func parsePrescriptionMetadata(xml: String) -> (taskId: String, accessCode: String)? {
    guard let meta = PrescriptionMetadataParser.shared.parseFirst(xml: xml) else { return nil }
    return (meta.taskId, meta.accessCode)
}

// MARK: - Small UI components

/// Inline status icon — trash when idle, spinner while deleting, check when done.
struct DeleteStatusButton: View {
    let status: DeleteStatus
    let onDelete: () -> Void

    var body: some View {
        switch status {
        case .idle:
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
        case .deleting:
            ProgressView().scaleEffect(0.7)
        case .deleted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "trash")
                .foregroundColor(.gray)
                .opacity(0.5)
        }
    }
}

/// "Delete all (N)" bar rendered above the prescription list.
struct DeleteAllBar: View {
    let remaining: Int
    let lastGoodEnv: String?
    var isDeletingAll: Bool = false
    let onDeleteAll: () -> Void

    var body: some View {
        if remaining > 0 {
            HStack {
                Text(lastGoodEnv.map { "Env: \($0.uppercased())" } ?? "Env: auto-detect")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onDeleteAll) {
                    if isDeletingAll {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.7)
                            Text("Deleting…")
                                .foregroundColor(.red)
                        }
                    } else {
                        Text("Delete all (\(remaining))")
                            .foregroundColor(.red)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isDeletingAll)
            }
            .padding(.vertical, 4)
        }
    }
}
