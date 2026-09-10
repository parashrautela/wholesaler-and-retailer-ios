import SwiftUI

@main
struct JewelIndiaApp: App {

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            rootContent
                // Touching the singleton at launch registers its notification
                // observers now, so `isCaptured` is already correct on the
                // first frame of any protected view rather than flicking on a
                // beat after one appears.
                .task { _ = CaptureMonitor.shared }
                // Deliberately not animated, and deliberately keyed on anything
                // other than `.active`: iOS snapshots the scene for the app
                // switcher as it leaves the active state, so the cover has to
                // be fully opaque the instant that happens. A transition here
                // would put a half-faded cover in the thumbnail.
                .overlay {
                    if scenePhase != .active {
                        AppSwitcherCover()
                    }
                }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        #if DEBUG
        if let peek = DebugScreenPeek.requested {
            DebugPeekHost(id: peek)
                .task { FontAudit.verify() }
        } else {
            RootView().task { FontAudit.verify() }
        }
        #else
        RootView()
        #endif
    }
}
