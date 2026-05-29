import SwiftUI
import CoreNFC
import ScoopCardlink

struct ContentView: View {
    @State private var can: String = ""
    @State private var statusMessage: String = "Enter CAN and tap Read Card"
    @State private var resultText: String = ""
    @State private var isReading: Bool = false

    @StateObject private var nfcReader = NFCReader()

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("CAN (6 digits)", text: $can)
                    .keyboardType(.numberPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: 200)
                    .disabled(isReading)

                Button(action: startReading) {
                    Text("Read Card")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isReading || can.count != 6)

                Text(statusMessage)
                    .foregroundColor(.secondary)

                ScrollView {
                    Text(resultText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)

                Spacer()
            }
            .padding()
            .navigationTitle("Cardlink Sample")
        }
        .onReceive(nfcReader.$result) { result in
            handleResult(result)
        }
    }

    private func startReading() {
        guard can.count == 6, can.allSatisfy({ $0.isNumber }) else {
            statusMessage = "Please enter a valid 6-digit CAN"
            return
        }

        isReading = true
        statusMessage = "Hold your eGK near the iPhone..."
        resultText = ""

        nfcReader.startReading(can: can)
    }

    private func handleResult(_ result: NFCReader.ReadResult?) {
        guard let result = result else { return }

        isReading = false

        switch result {
        case .success(let data):
            statusMessage = "Card read successfully!"
            resultText = """
            === Card Data ===

            ATR (\(data.atr.count) bytes):
            \(data.atr.hexString)

            GDO (\(data.gdo.count) bytes):
            \(data.gdo.hexString)

            CVC Auth Certificate (\(data.cvcAuth.count) bytes):
            \(data.cvcAuth.hexString)

            CVC CA Certificate (\(data.cvcCA.count) bytes):
            \(data.cvcCA.hexString)
            """

            if let x509RSA = data.x509AuthRSA {
                resultText += "\n\nX.509 Auth RSA (\(x509RSA.count) bytes):\n\(x509RSA.hexString)"
            }

            if let x509ECC = data.x509AuthECC {
                resultText += "\n\nX.509 Auth ECC (\(x509ECC.count) bytes):\n\(x509ECC.hexString)"
            }

        case .failure(let error):
            statusMessage = "Error: \(error.localizedDescription)"
            resultText = ""

        case .cancelled:
            statusMessage = "Reading cancelled"
            resultText = ""
        }
    }
}

class NFCReader: NSObject, ObservableObject, NFCTagReaderSessionDelegate {
    @Published var result: ReadResult?

    private var session: NFCTagReaderSession?
    private var can: String = ""

    enum ReadResult {
        case success(CardData)
        case failure(Error)
        case cancelled
    }

    struct CardData {
        let atr: Data
        let gdo: Data
        let cvcAuth: Data
        let cvcCA: Data
        let x509AuthRSA: Data?
        let x509AuthECC: Data?
    }

    func startReading(can: String) {
        guard NFCTagReaderSession.readingAvailable else {
            result = .failure(NSError(domain: "NFC", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "NFC not available"]))
            return
        }

        self.can = can
        session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self)
        session?.alertMessage = "Hold your eGK near the iPhone"
        session?.begin()
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // Session is active
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let nsError = error as NSError
        if nsError.code == NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue {
            DispatchQueue.main.async {
                self.result = .cancelled
            }
        } else if nsError.code != NFCReaderError.readerSessionInvalidationErrorFirstNDEFTagRead.rawValue {
            DispatchQueue.main.async {
                self.result = .failure(error)
            }
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No tag found")
            return
        }

        guard case .iso7816(let iso7816Tag) = tag else {
            session.invalidate(errorMessage: "Unsupported tag type")
            return
        }

        session.connect(to: tag) { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                session.invalidate(errorMessage: "Connection failed")
                DispatchQueue.main.async {
                    self.result = .failure(error)
                }
                return
            }

            // Use Cardlink SDK to read the card
            Task {
                do {
                    session.alertMessage = "Reading card data..."

                    // Create transceiver
                    let transceiver = IosNfcTransceiver(tag: iso7816Tag)

                    // Read card using the SDK
                    let cardData = try await CardlinkKt.cardlink(can: self.can, transceiver: transceiver)

                    session.alertMessage = "Card read successfully!"
                    session.invalidate()

                    // Convert KotlinByteArray to Data
                    let atr = Data(cardData.atr.toSwiftArray())
                    let gdo = Data(cardData.gdo.toSwiftArray())
                    let cvcAuth = Data(cardData.cvcAuth.toSwiftArray())
                    let cvcCA = Data(cardData.cvcCA.toSwiftArray())
                    let x509RSA = cardData.x509AuthRSA?.toSwiftArray().map { Data($0) }
                    let x509ECC = cardData.x509AuthECC?.toSwiftArray().map { Data($0) }

                    DispatchQueue.main.async {
                        self.result = .success(CardData(
                            atr: atr,
                            gdo: gdo,
                            cvcAuth: cvcAuth,
                            cvcCA: cvcCA,
                            x509AuthRSA: x509RSA,
                            x509AuthECC: x509ECC
                        ))
                    }
                } catch {
                    session.invalidate(errorMessage: "Failed to read card")
                    DispatchQueue.main.async {
                        self.result = .failure(error)
                    }
                }
            }
        }
    }
}

// Helper extension to convert Kotlin ByteArray to Swift Array
extension KotlinByteArray {
    func toSwiftArray() -> [UInt8] {
        var result = [UInt8]()
        for i in 0..<size {
            result.append(UInt8(bitPattern: Int8(get(index: i))))
        }
        return result
    }
}

// Helper extension for hex display
extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}

#Preview {
    ContentView()
}
