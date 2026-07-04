import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            TherapyView()
                .tabItem { Label("Therapy", systemImage: "mic.fill") }
                .tag(1)

            AssessmentView()
                .tabItem { Label("Assessment", systemImage: "chart.bar.fill") }
                .tag(2)
        }
        .tint(.indigo)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppStore())
}
