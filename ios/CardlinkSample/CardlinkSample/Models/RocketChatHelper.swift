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
            try? await RocketChatReporter.report(
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

/// Demo-only telemetry: posts scan statistics to a RocketChat channel.
///
/// This lives in the demo app, NOT in the SDK — it exfiltrates scan data to a
/// configured server, which is an application decision, not SDK behaviour.
/// Uses URLSession only; consumes the SDK's public metrics types
/// (`ScanRecord`, `MetricsFormatting`).
enum RocketChatReporter {

    /// Default RocketChat server URL for the demo.
    static let defaultServerURL = "https://rocketchat.scoop-gmbh.de/"

    private struct AuthInfo { let userId: String; let authToken: String }

    // Cached auth token to avoid logging in on every scan.
    private static var cachedAuth: AuthInfo?

    /// Posts scan results to RocketChat. Silently fails on any error.
    static func report(
        serverUrl: String,
        username: String,
        password: String,
        channel: String,
        record: ScanRecord,
        success: Bool = true,
        traceLog: [String] = []
    ) async throws {
        do {
            let auth = try await getOrLogin(serverUrl: serverUrl, username: username, password: password)
            try await postMessage(serverUrl: serverUrl, auth: auth, channel: channel,
                                  text: formatMessage(record: record, success: success))

            if !traceLog.isEmpty, let roomId = try? await resolveRoomId(serverUrl: serverUrl, auth: auth, channel: channel) {
                let content = Data(traceLog.joined(separator: "\n").utf8)
                try? await uploadFile(serverUrl: serverUrl, auth: auth, roomId: roomId, fileName: "trace.log", fileBytes: content)
            }
        } catch {
            // Silent failure — never interrupt the app flow.
        }
    }

    /// Tests the connection by logging in. Returns nil on success, else an error message.
    /// Declared `throws` (though it never does) to match the call sites' `try`/`catch`.
    static func testConnection(serverUrl: String, username: String, password: String) async throws -> String? {
        cachedAuth = nil
        do {
            _ = try await getOrLogin(serverUrl: serverUrl, username: username, password: password)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Clears any cached auth. Call when settings change.
    static func clearAuth() {
        cachedAuth = nil
    }

    // MARK: - REST

    private static func getOrLogin(serverUrl: String, username: String, password: String) async throws -> AuthInfo {
        if let cached = cachedAuth { return cached }
        let baseUrl = trimmed(serverUrl)
        let body = try JSONSerialization.data(withJSONObject: ["user": username, "password": password])
        let (status, data) = try await request(url: "\(baseUrl)/api/v1/login", method: "POST", jsonBody: body)
        guard (200..<300).contains(status) else { throw ReporterError.http("RocketChat login failed: \(status)") }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = root["data"] as? [String: Any],
              let userId = d["userId"] as? String,
              let authToken = d["authToken"] as? String
        else { throw ReporterError.http("RocketChat login: unexpected response") }
        let auth = AuthInfo(userId: userId, authToken: authToken)
        cachedAuth = auth
        return auth
    }

    private static func resolveRoomId(serverUrl: String, auth: AuthInfo, channel: String) async throws -> String? {
        let baseUrl = trimmed(serverUrl)
        let encoded = channel.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? channel
        for (endpoint, key) in [("channels.info", "channel"), ("groups.info", "group")] {
            let (status, data) = try await request(
                url: "\(baseUrl)/api/v1/\(endpoint)?roomName=\(encoded)", method: "GET", auth: auth)
            if (200..<300).contains(status),
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let room = root[key] as? [String: Any],
               let id = room["_id"] as? String {
                return id
            }
        }
        return nil
    }

    private static func postMessage(serverUrl: String, auth: AuthInfo, channel: String, text: String) async throws {
        let baseUrl = trimmed(serverUrl)
        let body = try JSONSerialization.data(withJSONObject: ["channel": channel, "text": text])
        let (status, _) = try await request(url: "\(baseUrl)/api/v1/chat.postMessage", method: "POST", jsonBody: body, auth: auth)
        if !(200..<300).contains(status) { cachedAuth = nil }
    }

    private static func uploadFile(serverUrl: String, auth: AuthInfo, roomId: String, fileName: String, fileBytes: Data) async throws {
        let baseUrl = trimmed(serverUrl)
        let boundary = "----CardlinkDemoBoundary"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/plain\r\n\r\n".data(using: .utf8)!)
        body.append(fileBytes)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: URL(string: "\(baseUrl)/api/v1/rooms.upload/\(roomId)")!)
        req.httpMethod = "POST"
        req.setValue(auth.authToken, forHTTPHeaderField: "X-Auth-Token")
        req.setValue(auth.userId, forHTTPHeaderField: "X-User-Id")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (_, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { cachedAuth = nil }
    }

    private static func request(
        url: String, method: String, jsonBody: Data? = nil, auth: AuthInfo? = nil
    ) async throws -> (Int, Data) {
        guard let u = URL(string: url) else { throw ReporterError.http("Invalid URL") }
        var req = URLRequest(url: u, timeoutInterval: 15)
        req.httpMethod = method
        if let auth = auth {
            req.setValue(auth.authToken, forHTTPHeaderField: "X-Auth-Token")
            req.setValue(auth.userId, forHTTPHeaderField: "X-User-Id")
        }
        if let body = jsonBody {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (status, data)
    }

    private static func trimmed(_ url: String) -> String {
        var s = url
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private enum ReporterError: Error { case http(String) }

    // MARK: - Formatting

    private struct Category { let name: String; let ms: Int64 }

    private static func formatMessage(record: ScanRecord, success: Bool) -> String {
        let total = record.totalTimeMs
        let icon = success ? "✅" : "❌"
        var out = "\(icon) *Cardlink Scan* — \(MetricsFormatting.shared.formatMs(ms: total)) total\n```\n"

        for cat in buildCategories(record: record) where cat.ms > 0 {
            let pct = total > 0 ? Int(Double(cat.ms) / Double(total) * 100) : 0
            let barLen = max(0, min(20, pct / 5))
            let bar = String(repeating: "█", count: barLen).padding(toLength: 20, withPad: "░", startingAt: 0)
            let label = cat.name.padding(toLength: 8, withPad: " ", startingAt: 0)
            let time = leftPad(MetricsFormatting.shared.formatMs(ms: cat.ms), to: 6)
            out += "\(label) \(bar) \(time) (\(pct)%)\n"
        }
        out += "```"

        let exchanges = record.apduExchanges
        if !exchanges.isEmpty {
            out += "\n\nAPDU Log (\(exchanges.count) exchanges)\n```\n"
            for (i, apdu) in exchanges.enumerated() {
                out += "\(leftPad(String(i + 1), to: 2)). \(apdu.label) — \(apdu.durationMs)ms\n"
            }
            out += "```"
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func buildCategories(record: ScanRecord) -> [Category] {
        let exchanges = record.apduExchanges
        var pace: Int64 = 0, popp: Int64 = 0, network: Int64 = 0, otherNfc: Int64 = 0

        for ex in exchanges {
            if ex.label.hasPrefix("Network:") {
                network += ex.durationMs
            } else if ex.label.contains("MSE:SET AT") || ex.label.contains("GENERAL AUTHENTICATE") || ex.label.contains("CardAccess") {
                pace += ex.durationMs
            } else if ex.label.hasPrefix("PoPP:") {
                popp += ex.durationMs
            } else {
                otherNfc += ex.durationMs
            }
        }
        if exchanges.isEmpty { otherNfc = record.nfcTimeMs }

        let hasPoPP = popp > 0 || exchanges.contains { $0.label.hasPrefix("PoPP:") }
        let adjustedOther = max(0, record.otherTimeMs - network)

        if hasPoPP {
            return [
                Category(name: "PACE", ms: pace),
                Category(name: "PoPP", ms: popp),
                Category(name: "NFC", ms: otherNfc),
                Category(name: "Network", ms: network),
                Category(name: "Crypto", ms: record.cryptoTimeMs),
                Category(name: "Gzip", ms: record.gzipTimeMs),
                Category(name: "Other", ms: adjustedOther),
            ]
        }
        return [
            Category(name: "NFC", ms: otherNfc),
            Category(name: "Crypto", ms: record.cryptoTimeMs),
            Category(name: "Gzip", ms: record.gzipTimeMs),
            Category(name: "Other", ms: record.otherTimeMs),
        ]
    }

    private static func leftPad(_ s: String, to width: Int) -> String {
        s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var cs = CharacterSet.urlQueryAllowed
        cs.remove(charactersIn: "&+=?")
        return cs
    }()
}
