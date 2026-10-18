import SwiftUI

@main
struct CadenceApp: App {
    @State private var library = Library()
    @State private var player = PlayerEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(player)
        }
    }
}
