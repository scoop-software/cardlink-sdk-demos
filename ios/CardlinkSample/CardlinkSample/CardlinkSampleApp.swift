import SwiftUI

@main
struct CardlinkSampleApp: App {
    @StateObject private var themeStore = BrandThemeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeStore)
                .tint(themeStore.current.tint)
                .brandFont(themeStore.current)
        }
    }
}
