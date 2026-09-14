import SwiftUI

@main
struct DecideApp: App {
    @State private var environment: AppEnvironment

    init() {
        // Storage that cannot be opened must never take the app down. `best()`
        // falls back from disk to memory to nothing, and the mode is surfaced to
        // the user rather than swallowed.
        _environment = State(initialValue: AppEnvironment(persistence: PersistenceService.best()))
    }

    var body: some Scene {
        WindowGroup {
            RootView(startupError: environment.storageWarning)
                .environment(environment)
                .tint(DecideColor.accent)
                .task {
                    await environment.subscriptions.refreshEntitlement()
                    await environment.subscriptions.loadProducts()
                    environment.refreshMemoryCandidate()
                }
        }
    }
}
