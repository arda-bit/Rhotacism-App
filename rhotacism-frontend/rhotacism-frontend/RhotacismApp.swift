import SwiftUI

@main
struct RhotacismApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    Task { await store.checkServer() }
                }
        }
    }
}
