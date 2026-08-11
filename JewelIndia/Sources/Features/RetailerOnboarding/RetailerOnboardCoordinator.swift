import SwiftUI

/// The retailer onboarding stack — the native equivalent of the
/// `/onboard-retailer → step2 → step3 → submitted` routes.
///
/// The previous version of this file *was* the whole flow: a single view with
/// three inline steps collecting a name, a store name and a state, submitting
/// straight to `retailers` with none of the identity/document fields the rest
/// of the schema and every downstream screen assumes exist. It never matched
/// `_spec/06-retailer-screens.md`, which documents the same three-step,
/// five-document shape as the wholesaler side. This is that flow, structured
/// the same way `OnboardCoordinator` is — see `RetailerOnboardFlow` and
/// `RetailerOnboardSteps`.
struct RetailerOnboardCoordinator: View {
    @Environment(SessionStore.self) private var session

    @State private var flow = RetailerOnboardFlow()
    @State private var path: [Step] = []

    enum Step: Hashable { case two, three }

    var body: some View {
        NavigationStack(path: $path) {
            RetailerOnboardStep1View { path.append(.two) }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .two:
                        RetailerOnboardStep2View { path.append(.three) }
                            .toolbar(.hidden, for: .navigationBar)
                    case .three:
                        RetailerOnboardStep3View {
                            Task { await session.refreshDestination() }
                        }
                        .toolbar(.hidden, for: .navigationBar)
                    }
                }
        }
        .environment(flow)
    }
}
