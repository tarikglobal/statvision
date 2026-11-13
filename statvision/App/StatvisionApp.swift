import SwiftUI

@main
struct StatvisionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // NSStatusItem owns the app's primary UI. This scene deliberately creates
        // no launch window; the dedicated settings window is opened from the panel.
        Settings { EmptyView() }
    }
}

