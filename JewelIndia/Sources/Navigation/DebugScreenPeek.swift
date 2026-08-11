#if DEBUG
import SwiftUI

/// Debug-only screen jump, so any screen can be rendered in isolation without
/// walking the whole flow — used to capture parity screenshots against the web.
///
/// Launch with `-JewelPeek <id>`, e.g.
/// `xcrun simctl launch <dev> com.jewelindia.app -JewelPeek otp`
enum DebugScreenPeek {
    static var requested: String? {
        UserDefaults.standard.string(forKey: "JewelPeek")
    }

    @MainActor
    @ViewBuilder
    static func view(for id: String, path: Binding<[AuthRoute]>) -> some View {
        switch id {
        case "entry":
            EntryView(path: path, initialError: nil)
        case "entry-error":
            EntryView(path: path, initialError: Copy.bannedError)
        case "signin":
            SignInView(path: path, identity: "+919876543210")
        case "otp":
            VerifyOTPView(path: path)
        case "setpassword":
            SetPasswordView(path: path)
        case "forgot":
            ForgotPasswordView(path: path)
        case "update":
            UpdatePasswordView(path: path)
        case "selectrole":
            SelectRoleView()
        case "onboard":
            OnboardCoordinator()
        case "onboard2":
            OnboardStep2View {}.environment(OnboardFlow())
        case "onboard3":
            OnboardStep3View {}.environment(OnboardFlow())
        case "submitted":
            OnboardSubmittedView()
        case "retailer-onboard":
            RetailerOnboardCoordinator()
        case "retailer-onboard2":
            RetailerOnboardStep2View {}.environment(RetailerOnboardFlow())
        case "retailer-onboard3":
            RetailerOnboardStep3View {}.environment(RetailerOnboardFlow())
        case "retailer-submitted":
            RetailerOnboardSubmittedView()
        case "addproduct":
            NavigationStack { AddProductView() }
        case "wholesaler":
            WholesalerShell()
        case "retailer":
            RetailerShell()
        case "employee":
            EmployeeShell()
        default:
            PhasePlaceholder(title: "Unknown peek", note: id)
        }
    }
}

/// Host that supplies the environment objects the screens expect.
struct DebugPeekHost: View {
    let id: String
    @State private var session = SessionStore()
    @State private var flow = SignupFlow()
    @State private var path: [AuthRoute] = []

    init(id: String) {
        self.id = id
        // Seed before the screen's own `onAppear` runs, so the OTP screen
        // restores a live countdown instead of bouncing to the entry screen.
        let seeded = SignupFlow()
        if seeded.identity == nil { seeded.identity = "+919876543210" }
        if id == "otp" { seeded.otpSentAt = Date() }
        _flow = State(initialValue: seeded)
    }

    var body: some View {
        DebugScreenPeek.view(for: id, path: $path)
            .environment(session)
            .environment(flow)
    }
}
#endif
