import SafariServices
import SwiftUI
import StoreKit
import Supabase

// Release builds buy fixed credit packs through StoreKit. The old Razorpay
// model remains below only for the debug screen previews; it is never offered
// by the app's normal Top Up entry points.

/// Top Up presented on its own, from Home or the Treasure Chest.
public struct TopUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: TopUpModel
    private let usesStoreKit: Bool

    public init() {
        _model = State(initialValue: TopUpModel())
        usesStoreKit = true
    }

    init(model: TopUpModel) {
        _model = State(initialValue: model)
        usesStoreKit = false
    }

    public var body: some View {
        NavigationStack {
            Group {
                if usesStoreKit {
                    AppleTopUpView(doneTitle: "Done") { dismiss() }
                } else {
                    TopUpView(model: model, doneTitle: "Done") { dismiss() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(.manrope(14, weight: .semibold))
                        .foregroundStyle(Palette.dark)
                }
            }
        }
    }
}

// MARK: - App Store credit purchases

enum AppleCreditPurchases {
    static let packs: [(id: String, name: String, credits: Int)] = [
        ("com.jewelindia.credits.starter", "Starter", 5000),
        ("com.jewelindia.credits.popular", "Popular", 10000),
        ("com.jewelindia.credits.pro", "Pro", 25000),
        ("com.jewelindia.credits.bulk", "Bulk", 50000),
    ]

    struct Confirmation: Decodable {
        let ok: Bool
        let credits: Int
        let replayed: Bool
    }

    private struct Delivery: Encodable {
        let signed_transaction: String
    }

    enum PurchaseError: LocalizedError {
        case unverified, notSignedIn, pendingCredits
        var errorDescription: String? {
            switch self {
            case .unverified: "Apple could not verify this purchase."
            case .notSignedIn: "Please sign in again before buying credits."
            case .pendingCredits: "Apple confirmed the payment. Your credits are pending; reopen Buy Credits to check again."
            }
        }
    }

    @MainActor
    static func purchase(_ product: StoreKit.Product) async throws -> Int? {
        guard let userID = SupabaseManager.client.auth.currentSession?.user.id else {
            throw PurchaseError.notSignedIn
        }
        let outcome = try await product.purchase(options: [.appAccountToken(userID)])
        switch outcome {
        case .success(let result):
            guard case .verified = result else { throw PurchaseError.unverified }
            return try await deliver(result)
        case .pending, .userCancelled:
            return nil
        @unknown default:
            return nil
        }
    }

    /// StoreKit may complete while the app is closed. Keep the transaction
    /// unfinished until the server confirms the credit grant, then retry it.
    @MainActor
    static func reconcileUnfinished() async {
        for await result in StoreKit.Transaction.unfinished {
            guard case .verified = result else { continue }
            _ = try? await deliver(result)
        }
    }

    @MainActor
    static func observeUpdates() async {
        for await result in StoreKit.Transaction.updates {
            guard case .verified = result else { continue }
            _ = try? await deliver(result)
        }
    }

    @MainActor
    private static func deliver(_ result: StoreKit.VerificationResult<StoreKit.Transaction>) async throws -> Int {
        guard case .verified(let transaction) = result else { throw PurchaseError.unverified }
        guard let session = try? await SupabaseManager.client.auth.session else {
            throw PurchaseError.notSignedIn
        }
        do {
            let confirmation: Confirmation = try await SupabaseManager.client.functions.invoke(
                "apple-iap",
                options: FunctionInvokeOptions(
                    headers: ["Authorization": "Bearer \(session.accessToken)"],
                    body: Delivery(signed_transaction: result.jwsRepresentation)
                ),
                decoder: JSONDecoder()
            )
            guard confirmation.ok else { throw PurchaseError.pendingCredits }
            await transaction.finish()
            return confirmation.credits
        } catch {
            // Finishing here would lose a paid consumable if the grant failed.
            throw PurchaseError.pendingCredits
        }
    }
}

struct AppleTopUpView: View {
    @Environment(CreditStore.self) private var credits
    let doneTitle: String
    let onDone: () -> Void

    @State private var products: [StoreKit.Product] = []
    @State private var loading = true
    @State private var buyingID: String?
    @State private var error: String?
    @State private var addedCredits: Int?

    var body: some View {
        VStack(spacing: Spacing.lg) {
            if let addedCredits {
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(TopUpStyle.gold)
                Text("\(TopUpStyle.count(addedCredits)) credits added")
                    .font(.cirka(26, weight: .bold))
                Spacer()
                Button(doneTitle, action: onDone)
                    .buttonStyle(.borderedProminent)
            } else if loading {
                Spacer()
                ProgressView("Loading App Store packs…")
                Spacer()
            } else {
                Text("Add credits")
                    .font(.cirka(25, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Choose a pack. Credits bought through the App Store never expire.")
                    .font(.manrope(13))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(products, id: \.id) { product in
                    Button { Task { await buy(product) } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(product.displayName).font(.manrope(15, weight: .bold))
                                Text("\(quantity(for: product.id)) credits")
                                    .font(.manrope(12)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            if buyingID == product.id { ProgressView() }
                            else { Text(product.displayPrice).font(.manrope(15, weight: .bold)) }
                        }
                        .padding(Spacing.base)
                        .foregroundStyle(Palette.dark)
                        .background(Palette.cream, in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(buyingID != nil)
                }
                if let error {
                    Text(error).font(.manrope(12)).foregroundStyle(Palette.statusRejected)
                }
                Spacer(minLength: 0)
                Button("Check pending purchases") { Task { await reconcile() } }
                    .font(.manrope(13, weight: .semibold))
            }
        }
        .padding(Spacing.base)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
        .navigationTitle("Buy Credits")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func quantity(for id: String) -> Int {
        AppleCreditPurchases.packs.first { $0.id == id }?.credits ?? 0
    }

    private func load() async {
        await reconcile()
        do {
            let fetched = try await StoreKit.Product.products(for: AppleCreditPurchases.packs.map(\.id))
            products = AppleCreditPurchases.packs.compactMap { pack in
                fetched.first { $0.id == pack.id }
            }
            if products.isEmpty { error = "App Store credit packs are not available yet." }
        } catch {
            self.error = "Could not load the App Store credit packs. Try again."
        }
        loading = false
    }

    private func buy(_ product: StoreKit.Product) async {
        buyingID = product.id
        error = nil
        defer { buyingID = nil }
        do {
            if let quantity = try await AppleCreditPurchases.purchase(product) {
                addedCredits = quantity
                await credits.refresh()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reconcile() async {
        await AppleCreditPurchases.reconcileUnfinished()
        await credits.refresh()
    }
}

/// The Top Up screen itself, without a navigation stack, so the
/// out-of-credits sheet can push it onto its own.
struct TopUpView: View {
    @Environment(CreditStore.self) private var credits
    @Bindable var model: TopUpModel
    /// The success screen's button, e.g. "Done" or "Back to Editor".
    var doneTitle: String
    var onDone: () -> Void

    @FocusState private var isAmountFocused: Bool

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loadFailed(let message):
                statusScreen(
                    symbol: "wifi.exclamationmark",
                    tint: Palette.muted,
                    title: "Couldn't load the packs",
                    message: message,
                    primary: ("Try Again", { Task { await model.load() } }),
                    secondary: nil
                )
            case .choosing:
                choosing
            case .confirming:
                confirming
            case .pending:
                statusScreen(
                    symbol: "clock",
                    tint: Palette.statusPending,
                    title: "Payment not confirmed yet",
                    message: "If money left your account, your credits will arrive in a few minutes. You don't need to pay again. They'll show up in your Treasure Chest.",
                    primary: ("Check Again", { model.checkAgain() }),
                    secondary: ("Back to Packs", { model.backToPacks() })
                )
            case .succeeded(let added):
                succeeded(added)
            }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .navigationTitle("Buy Credits")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onDisappear { model.stopWatching() }
        .onChange(of: model.phase) { _, phase in
            if case .succeeded = phase {
                Task { await credits.refresh() }
            }
        }
        .sensoryFeedback(.success, trigger: model.phase) { _, phase in
            if case .succeeded = phase { return true }
            return false
        }
        .fullScreenCover(isPresented: $model.isShowingCheckout, onDismiss: { model.checkoutClosed() }) {
            if let url = model.link?.url {
                SafariCheckoutView(url: url) { model.isShowingCheckout = false }
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Choosing a pack

    private var choosing: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add credits")
                        .font(.cirka(24, weight: .bold))
                        .foregroundStyle(Palette.dark)

                    Text("Pick a pack or type your own amount. Credits are added as soon as your payment goes through.")
                        .font(.gilroy(14, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let wallet = credits.wallet {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TopUpStyle.gold)
                        Text("Balance: \(TopUpStyle.count(wallet.available)) credits")
                            .font(.manrope(13, weight: .semibold))
                            .foregroundStyle(Palette.dark)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Palette.cream, in: Capsule())
                }

                VStack(spacing: Spacing.sm) {
                    ForEach(model.packs) { pack in
                        packCard(pack)
                    }
                    if model.customRange != nil {
                        customCard
                    }
                }
            }
            .padding(Spacing.base)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { payBar }
    }

    /// Any amount the wholesaler likes, priced the same way as a pack.
    private var customCard: some View {
        let isSelected = model.isCustomSelected
        let fusionCost = credits.cost(for: "chamak.generate") ?? 0
        let quote = model.customQuote

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Palette.dark : Palette.border)

                Text("Choose your own amount")
                    .font(.manrope(15, weight: .bold))
                    .foregroundStyle(Palette.dark)

                Spacer(minLength: 8)

                if let quote, isSelected {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(TopUpStyle.count(quote.credits))
                            .font(.cirka(22, weight: .bold))
                            .foregroundStyle(TopUpStyle.gold)
                        if fusionCost > 0 {
                            Text("≈ \(TopUpStyle.count(quote.credits / fusionCost)) combines")
                                .font(.manrope(11, weight: .semibold))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                }
            }
            .contentShape(.rect)
            .onTapGesture {
                model.selectedKey = TopUpModel.customKey
                isAmountFocused = true
            }

            if isSelected {
                HStack(spacing: 6) {
                    Text("₹")
                        .font(.cirka(20, weight: .bold))
                        .foregroundStyle(Palette.dark)

                    TextField("0", text: $model.customAmountText)
                        .font(.cirka(20, weight: .bold))
                        .foregroundStyle(Palette.dark)
                        .keyboardType(.numberPad)
                        .focused($isAmountFocused)
                        .onChange(of: model.customAmountText) { _, text in
                            let digits = String(text.filter(\.isNumber).prefix(6))
                            if digits != text { model.customAmountText = digits }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white, in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10).stroke(Palette.border, lineWidth: 1)
                }

                Text(customFootnote(quote))
                    .font(.manrope(12))
                    .foregroundStyle(quote == nil && !model.customAmountText.isEmpty ? Palette.statusRejected : Palette.muted)
            }
        }
        .padding(Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Palette.cream.opacity(0.6) : Color(hex: 0xFAFAFA), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Palette.dark : Color(hex: 0xE5E7EB), lineWidth: isSelected ? 1.5 : 1)
        }
    }

    private func customFootnote(_ quote: (gstINR: Double, totalINR: Double, credits: Int)?) -> String {
        if let quote, let amount = model.customAmountINR {
            return "\(TopUpStyle.rupees(Double(amount))) + \(TopUpStyle.rupees(quote.gstINR)) GST = \(TopUpStyle.rupees(quote.totalINR)) to pay"
        }
        guard let range = model.customRange else { return "" }
        return "Enter a whole amount between \(TopUpStyle.rupees(Double(range.minINR))) and \(TopUpStyle.rupees(Double(range.maxINR))), before GST."
    }

    private func packCard(_ pack: TopUpPack) -> some View {
        let isSelected = model.selectedKey == pack.key
        let fusionCost = credits.cost(for: "chamak.generate") ?? 0

        return Button {
            model.selectedKey = pack.key
        } label: {
            HStack(alignment: .center, spacing: Spacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Palette.dark : Palette.border)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(pack.label)
                            .font(.manrope(15, weight: .bold))
                            .foregroundStyle(Palette.dark)

                        if pack.key == TopUpModel.featuredKey {
                            Text("Recommended")
                                .font(.manrope(10, weight: .bold))
                                .foregroundStyle(TopUpStyle.gold)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color(hex: 0xFFFBF4), in: Capsule())
                                .overlay { Capsule().stroke(Color(hex: 0xF3E8D6), lineWidth: 1) }
                        }
                    }

                    Text("\(TopUpStyle.rupees(pack.priceINR)) + \(TopUpStyle.rupees(pack.gstINR)) GST")
                        .font(.manrope(12))
                        .foregroundStyle(Palette.muted)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(TopUpStyle.count(pack.credits))
                        .font(.cirka(22, weight: .bold))
                        .foregroundStyle(TopUpStyle.gold)
                    Text(fusionCost > 0 ? "≈ \(TopUpStyle.count(pack.credits / fusionCost)) combines" : "credits")
                        .font(.manrope(11, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(Spacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Palette.cream.opacity(0.6) : Color(hex: 0xFAFAFA), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Palette.dark : Color(hex: 0xE5E7EB), lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var payBar: some View {
        VStack(spacing: Spacing.sm) {
            if let error = model.errorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Palette.statusRejected)
                    Text(error)
                        .font(.manrope(12, weight: .medium))
                        .foregroundStyle(Palette.dark)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Color(hex: 0xFEF2F2), in: .rect(cornerRadius: 10))
            }

            Button {
                isAmountFocused = false
                Task { await model.pay() }
            } label: {
                HStack(spacing: 8) {
                    if model.isCreatingLink {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13))
                    }
                    Text(model.payableTotalINR.map { "Pay \(TopUpStyle.rupees($0))" }
                         ?? (model.isCustomSelected ? "Enter an amount" : "Choose a pack"))
                        .font(.manrope(15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(model.payableTotalINR == nil ? Palette.muted : Palette.dark, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(model.payableTotalINR == nil || model.isCreatingLink)

            Text("Secure payment by Razorpay: UPI, cards or netbanking")
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
        .background(.white)
    }

    // MARK: - After paying

    private var confirming: some View {
        VStack(spacing: Spacing.base) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Checking your payment…")
                .font(.cirka(22, weight: .bold))
                .foregroundStyle(Palette.dark)
            Text("This usually takes a few seconds.")
                .font(.manrope(13))
                .foregroundStyle(Palette.muted)
            Spacer()
            Button("I didn't pay. Back to packs") { model.backToPacks() }
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .padding(.bottom, Spacing.lg)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.base)
    }

    private func succeeded(_ added: Int) -> some View {
        VStack(spacing: Spacing.base) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Palette.cream)
                    .frame(width: 88, height: 88)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(TopUpStyle.gold)
            }
            Text("\(TopUpStyle.count(added)) credits added")
                .font(.cirka(26, weight: .bold))
                .foregroundStyle(Palette.dark)
                .multilineTextAlignment(.center)
            if let wallet = credits.wallet {
                Text("New balance: \(TopUpStyle.count(wallet.available)) credits")
                    .font(.manrope(14, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            primaryButton(doneTitle, action: onDone)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.base)
    }

    // MARK: - Pieces

    private func statusScreen(
        symbol: String,
        tint: Color,
        title: String,
        message: String,
        primary: (String, () -> Void),
        secondary: (String, () -> Void)?
    ) -> some View {
        VStack(spacing: Spacing.base) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 36))
                .foregroundStyle(tint)
            Text(title)
                .font(.cirka(22, weight: .bold))
                .foregroundStyle(Palette.dark)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.manrope(13))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            primaryButton(primary.0, action: primary.1)
            if let secondary {
                Button(secondary.0, action: secondary.1)
                    .font(.manrope(14, weight: .semibold))
                    .foregroundStyle(Palette.dark)
                    .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.base)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.manrope(15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Palette.dark, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Model

@MainActor
@Observable
final class TopUpModel {
    enum Phase: Equatable {
        case loading
        case loadFailed(String)
        case choosing
        /// Razorpay's page was closed; looking for the purchase for a while.
        case confirming
        /// Not seen in time. The payment may still land.
        case pending
        case succeeded(credits: Int)
    }

    /// Picked by default and badged.
    static let featuredKey = "popular"
    /// The "type your own amount" row, and what the server calls it.
    static let customKey = "custom"
    /// How long to keep looking after Razorpay's page closes.
    private static let confirmWindow: Duration = .seconds(20)
    private static let pollInterval: Duration = .milliseconds(2500)

    var phase: Phase = .loading
    private(set) var packs: [TopUpPack] = []
    private(set) var options = TopUpOptions(packs: [])
    var selectedKey: String?
    /// Digits only, excluding GST.
    var customAmountText: String = ""
    private(set) var isCreatingLink = false
    private(set) var errorMessage: String?
    private(set) var link: TopUpLink?
    var isShowingCheckout = false

    private var watchTask: Task<Void, Never>?

    init() {}

    /// A model already showing `packs`, for previews and peeks.
    init(packs: [TopUpPack], phase: Phase = .choosing) {
        self.packs = packs
        self.options = TopUpOptions(packs: packs, custom: .init(minINR: 1, maxINR: 100_000))
        self.phase = phase
        selectedKey = packs.first { $0.key == Self.featuredKey }?.key ?? packs.first?.key
    }

    #if DEBUG
    /// Peeks only: open a page as if `pay()` had made it.
    func openCheckoutForPeek(_ url: URL) {
        let link = TopUpLink(linkID: "plink_peek", url: url, credits: 5000, totalINR: 590)
        self.link = link
        isShowingCheckout = true
        watch(link, for: nil)
    }
    #endif

    var selectedPack: TopUpPack? {
        packs.first { $0.key == selectedKey }
    }

    var isCustomSelected: Bool { selectedKey == Self.customKey }

    var customRange: TopUpOptions.CustomAmountRange? { options.custom }

    /// The typed amount, only when it is one the server will accept.
    var customAmountINR: Int? {
        guard let range = customRange, let amount = Int(customAmountText) else { return nil }
        return (range.minINR...range.maxINR).contains(amount) ? amount : nil
    }

    /// What the typed amount costs and buys, worked out the server's way.
    var customQuote: (gstINR: Double, totalINR: Double, credits: Int)? {
        guard let amount = customAmountINR else { return nil }
        return TopUpQuote.of(amountExGST: amount, gstPercent: options.gstPercent, creditsPerRupee: options.creditsPerRupee)
    }

    /// What the Pay button charges: a pack's total, or the typed amount's.
    var payableTotalINR: Double? {
        isCustomSelected ? customQuote?.totalINR : selectedPack?.totalINR
    }

    func load() async {
        guard packs.isEmpty else { return }
        phase = .loading
        do {
            options = try await CreditsAPI.fetchTopUpOptions()
            packs = options.packs
            selectedKey = packs.first { $0.key == Self.featuredKey }?.key ?? packs.first?.key ?? Self.customKey
            phase = packs.isEmpty && options.custom == nil
                ? .loadFailed("No packs are on sale right now. Please try again later.")
                : .choosing
        } catch {
            phase = .loadFailed(error.localizedDescription)
        }
    }

    func pay() async {
        guard !isCreatingLink else { return }
        isCreatingLink = true
        errorMessage = nil
        defer { isCreatingLink = false }
        do {
            let link: TopUpLink
            if isCustomSelected {
                guard let amount = customAmountINR else { return }
                link = try await CreditsAPI.createTopUpLink(amountINR: amount)
            } else {
                guard let pack = selectedPack else { return }
                link = try await CreditsAPI.createTopUpLink(packKey: pack.key)
            }
            self.link = link
            isShowingCheckout = true
            // Watch while the page is open too: a UPI payment finishes in
            // another app, and the credits can land before anyone taps Done.
            watch(link, for: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Razorpay's page closed, by the user or by `landed`.
    func checkoutClosed() {
        guard let link, !hasSucceeded else { return }
        phase = .confirming
        watch(link, for: Self.confirmWindow)
    }

    func checkAgain() {
        guard let link else { return }
        phase = .confirming
        watch(link, for: Self.confirmWindow)
    }

    func backToPacks() {
        stopWatching()
        link = nil
        phase = .choosing
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }

    private var hasSucceeded: Bool {
        if case .succeeded = phase { return true }
        return false
    }

    private func watch(_ link: TopUpLink, for window: Duration?) {
        watchTask?.cancel()
        let deadline = window.map { ContinuousClock.now.advanced(by: $0) }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                if let receipt = try? await CreditsAPI.purchase(forLink: link.linkID) {
                    self?.landed(receipt.credits)
                    return
                }
                if let deadline, ContinuousClock.now >= deadline {
                    self?.phase = .pending
                    return
                }
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private func landed(_ credits: Int) {
        phase = .succeeded(credits: credits)
        isShowingCheckout = false
        watchTask = nil
    }
}

// MARK: - Razorpay's page

/// Razorpay's hosted checkout in an in-app Safari view: the app never sees
/// card or UPI details, and UPI apps can be opened from it.
struct SafariCheckoutView: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.barCollapsingEnabled = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = UIColor(Palette.dark)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onFinish() }
    }
}

// MARK: - Formatting

enum TopUpStyle {
    static let gold = Color(hex: 0xBB8651)

    private static let india = Locale(identifier: "en_IN")

    /// 50000 → "50,000"; 100000 → "1,00,000".
    static func count(_ value: Int) -> String {
        value.formatted(.number.locale(india))
    }

    /// 590 → "₹590"; 1.18 → "₹1.18".
    static func rupees(_ value: Double) -> String {
        value.formatted(.currency(code: "INR").locale(india).precision(.fractionLength(0...2)))
    }
}
