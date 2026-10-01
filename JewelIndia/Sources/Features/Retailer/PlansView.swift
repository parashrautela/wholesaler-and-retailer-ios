import SwiftUI

struct PlansView: View {
    @Environment(CreditStore.self) private var credits
    #if DEBUG
    var peekPlans: [Plan]?
    #endif
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your retailer access").font(.cirka(30))
                if let plan = credits.plan {
                    Text(plan.temporaryAccess ? "Plan features are included during the daily-credit offer." : "Your existing access is preserved. New plan sales and renewals are paused.")
                        .font(.manrope(15))
                } else {
                    Text("Verified retailers receive temporary access to plan features during the daily-credit offer.")
                        .font(.manrope(15))
                }
                Text("No subscription payment is required. Existing purchased unlocks remain yours.").font(.manrope(14))
                NavigationLink("Daily credits") { TreasureChestView() }
            }.padding(24)
        }
        .navigationTitle("Your access")
        .task { await credits.refreshPlan() }
    }
}
