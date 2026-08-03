import SwiftUI

@main
struct JewelIndiaApp: App {
    var body: some Scene {
        WindowGroup {
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
}
