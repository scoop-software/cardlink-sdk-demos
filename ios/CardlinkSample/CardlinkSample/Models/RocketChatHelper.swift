import Foundation
import ScoopCardlink

/// Reads RocketChat settings from UserDefaults and posts scan results.
/// Silently fails on any error — never interrupts the app flow.
enum RocketChatHelper {

    /// Posts scan results to RocketChat if enabled in settings.
    static func reportIfEnabled(record: ScanRecord, success: Bool = true, traceLog: [String] = []) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "rcEnabled") else { return }

        let serverUrl = defaults.string(forKey: "rcServerUrl").flatMap({ $0.isEmpty ? nil : $0 }) ?? "https://rocketchat.scoop-gmbh.de"
        let username = RocketChatKeychain.load(key: "rcUsername") ?? ""
        let password = RocketChatKeychain.load(key: "rcPassword") ?? ""
        let channel = defaults.string(forKey: "rcChannel").flatMap({ $0.isEmpty ? nil : $0 }) ?? "PoPP-Demo"

        guard !serverUrl.isEmpty, !username.isEmpty else { return }

        Task {
            try? await RocketChatReporter.shared.report(
                serverUrl: serverUrl,
                username: username,
                password: password,
                channel: channel,
                record: record,
                success: success,
                traceLog: traceLog
            )
        }
    }
}
