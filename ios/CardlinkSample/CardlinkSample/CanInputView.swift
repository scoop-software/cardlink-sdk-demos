import SwiftUI

/// Reusable CAN (Card Access Number) input field with camera scanner button.
///
/// Contains:
/// - TextField limited to 6 digits
/// - Camera button that presents CanScannerSheetView for OCR scanning
///
/// Used on both Scan and Upload screens.
struct CanInputView: View {
    @Binding var can: String

    /// Key used to persist the CAN in UserDefaults. Different keys allow
    /// separate storage per flow (e.g. "can_cardlink" vs "can_popp").
    var persistKey: String = "lastCan"

    @State private var isShowingScanner = false

    var body: some View {
        HStack {
            TextField("CAN (6 digits)", text: $can)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .onChange(of: can) { newValue in
                    if newValue.count > 6 { can = String(newValue.prefix(6)) }
                    // Persist valid CAN
                    if newValue.count == 6 {
                        UserDefaults.standard.set(newValue, forKey: persistKey)
                    }
                }

            Button(action: { isShowingScanner = true }) {
                Image(systemName: "camera.fill")
                    .font(.title3)
            }
        }
        .onAppear {
            // Restore last CAN if the binding is empty
            if can.isEmpty, let saved = UserDefaults.standard.string(forKey: persistKey), saved.count == 6 {
                can = saved
            }
        }
        .sheet(isPresented: $isShowingScanner) {
            CanScannerSheetView { scannedCan in
                can = scannedCan
                UserDefaults.standard.set(scannedCan, forKey: persistKey)
                isShowingScanner = false
            } onCancel: {
                isShowingScanner = false
            }
        }
    }
}

/// Sheet wrapper around CanScannerView for OCR scanning of the CAN.
///
/// Shows the camera preview with progress text and a cancel button.
struct CanScannerSheetView: View {
    let onSuccess: (String) -> Void
    let onCancel: () -> Void

    @State private var scanProgress: String = "Point camera at CAN on card"

    var body: some View {
        NavigationView {
            CanScannerView(
                onProgress: { can, count, required in
                    scanProgress = "Detected: \(can) (\(count)/\(required))"
                },
                onResult: { result in
                    switch result {
                    case .success(let can):
                        onSuccess(can)
                    case .failure:
                        onCancel()
                    }
                }
            )
            .navigationTitle("Scan CAN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onCancel() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(scanProgress)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black.opacity(0.7))
            }
        }
    }
}
