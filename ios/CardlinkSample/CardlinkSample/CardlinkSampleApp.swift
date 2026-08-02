import SwiftUI

@main
struct CardlinkSampleApp: App {
    @StateObject private var themeStore = BrandThemeStore()
    @State private var sharedStorageBootstrapComplete = false

    var body: some Scene {
        WindowGroup {
            Group {
                if sharedStorageBootstrapComplete {
                    ContentView()
                } else {
                    ProgressView("Preparing secure storage…")
                        .task {
                            _ = await DemoSharedStorageBootstrap.run()
                            sharedStorageBootstrapComplete = true
                        }
                }
            }
                .environmentObject(themeStore)
                .tint(themeStore.current.tint)
                .brandFont(themeStore.current)
        }
    }
}
