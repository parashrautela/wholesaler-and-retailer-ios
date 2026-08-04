import SwiftUI

/// The wholesaler onboarding stack — the native equivalent of the
/// `/onboard → /onboard/step2 → /onboard/step3 → /onboard/submitted` routes.
///
/// It lives outside the `TabView` (there is no tab bar during onboarding), and
/// the form state is owned here so leaving the flow discards it, matching the
/// web's in-memory `OnboardContext`.
struct OnboardCoordinator: View {
    @Environment(SessionStore.self) private var session

    @State private var flow = OnboardFlow()
    @State private var path: [Step] = []

    enum Step: Hashable { case two, three }

    var body: some View {
        NavigationStack(path: $path) {
            OnboardStep1View { path.append(.two) }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .two:
                        OnboardStep2View { path.append(.three) }
                            .toolbar(.hidden, for: .navigationBar)
                    case .three:
                        OnboardStep3View {
                            // The row now exists with status "pending", so the
                            // router moves the whole app to the submitted gate.
                            Task { await session.refreshDestination() }
                        }
                        .toolbar(.hidden, for: .navigationBar)
                    }
                }
        }
        .environment(flow)
    }
}
