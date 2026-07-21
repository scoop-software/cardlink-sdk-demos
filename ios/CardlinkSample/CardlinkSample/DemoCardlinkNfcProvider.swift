import CoreNFC
import ScoopCardlink

/// App-owned NFC session provider for the Cardlink flows.
///
/// The SDK's turnkey `IosNfcTransceiverProvider` uses a Kotlin/Native
/// `NFCTagReaderSessionDelegate` whose `didDetectTags:` callback does not fire on
/// current builds — the tag is found by the controller but never delivered, so
/// the system sheet hangs until it burns out. This provider owns the
/// `NFCTagReaderSession` in Swift (the proven NfcDemo pattern), so `didDetect`
/// fires, the tag connects, and a live `IosNfcTransceiver` is returned to the
/// flow. It also implements `NfcSessionController` so the flow drives the sheet's
/// message and dismissal.
///
/// Pass an instance to `CardlinkFlow(config:nfcProvider:)`,
/// `ServerDrivenFlow(config:nfcProvider:)`, or `ErezeptUploadFlow(config:nfcProvider:)`.
final class DemoCardlinkNfcProvider: NSObject, NfcTransceiverProvider,
    NfcSessionController, NFCTagReaderSessionDelegate {

    private let initialMessage: String
    private var session: NFCTagReaderSession?
    private var continuation: CheckedContinuation<any NfcTransceiver, Error>?

    init(initialMessage: String = "Hold your eGK near the top of your iPhone.") {
        self.initialMessage = initialMessage
    }

    // MARK: - NfcTransceiverProvider

    func __awaitTransceiver() async throws -> any NfcTransceiver {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.main.async {
                guard NFCTagReaderSession.readingAvailable else {
                    cont.resume(throwing: NSError(domain: "ScoopNfc", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "NFC reading is not available on this device."]))
                    return
                }
                guard let session = NFCTagReaderSession(
                    pollingOption: .iso14443, delegate: self) else {
                    cont.resume(throwing: NSError(domain: "ScoopNfc", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Could not start the NFC reader session."]))
                    return
                }
                self.continuation = cont
                self.session = session
                session.alertMessage = self.initialMessage
                session.begin()
            }
        }
    }

    // MARK: - NfcSessionController (flow drives the sheet)

    func onNfcSessionHint(action: NfcSessionAction, message: String) {
        DispatchQueue.main.async {
            switch action {
            case .updateMessage:
                self.session?.alertMessage = message
            case .invalidate:
                if !message.isEmpty { self.session?.alertMessage = message }
                self.session?.invalidate()
                self.session = nil
            case .invalidateWithError:
                self.session?.invalidate(errorMessage: message)
                self.session = nil
            case .none:
                break
            }
        }
    }

    // MARK: - NFCTagReaderSessionDelegate

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession,
                          didInvalidateWithError error: Error) {
        guard session === self.session else { return }
        self.session = nil
        resumeOnce(throwing: error)
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard session === self.session else { return }
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No card found.")
            return
        }
        guard case .iso7816(let iso7816Tag) = tag else {
            session.invalidate(errorMessage: "Unsupported card type.")
            return
        }
        session.connect(to: tag) { [weak self] error in
            guard let self = self, session === self.session else { return }
            if let error = error {
                session.invalidate(errorMessage: "Connection failed.")
                self.resumeOnce(throwing: error)
                return
            }
            session.alertMessage = "Reading card…"
            self.resumeOnce(returning: IosNfcTransceiver(tag: iso7816Tag))
        }
    }

    // MARK: - Continuation helpers (resume exactly once)

    private func resumeOnce(returning value: any NfcTransceiver) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(returning: value)
    }

    private func resumeOnce(throwing error: Error) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(throwing: error)
    }
}
