import SwiftUI

@main
struct CadenceApp: App {
    @State private var library = Library()
    @State private var player = PlayerEngine()
    @State private var taste = TasteStore()
    @State private var tags = TagStore()
    @State private var ai = ServerAI()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(player)
                .environment(taste)
                .environment(tags)
                .environment(ai)
        }
    }
}
