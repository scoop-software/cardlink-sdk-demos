import SwiftUI

@main
struct CardlinkSampleApp: App {
    @StateObject private var themeStore = BrandThemeStore()
    @State private var credentialMigrationComplete = false

    var body: some Scene {
        WindowGroup {
            Group {
                if credentialMigrationComplete {
                    ContentView()
                } else {
                    ProgressView("Preparing secure storage…")
                        .task {
                            DemoCredentialMigrationBootstrap.run()
                            credentialMigrationComplete = true
                        }
                }
            }
                .environmentObject(themeStore)
                .tint(themeStore.current.tint)
                .brandFont(themeStore.current)
        }
    }
}
