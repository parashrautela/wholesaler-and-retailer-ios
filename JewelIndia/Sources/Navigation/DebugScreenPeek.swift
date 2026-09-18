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
        case "entry", "doors":
            RoleChoiceView(path: path, initialError: nil)
        case "entry-error":
            RoleChoiceView(path: path, initialError: Copy.bannedError)
        case "doors-signedin":
            RoleChoiceView(path: path, signedIn: true)
        case "entry-wholesaler":
            EntryView(path: path, mode: .signup(.wholesaler))
        case "entry-retailer":
            EntryView(path: path, mode: .signup(.retailer))
        case "entry-signin":
            EntryView(path: path, mode: .signIn)
        case "invite-code":
            InviteCodeView(path: path)
        case "staff-signin":
            EmployeeSignInView(path: path, initialError: nil)
        case "staff-signin-off":
            EmployeeSignInView(path: path, initialError: Copy.employeeDeactivated)
        case "staff-list":
            NavigationStack { EmployeesListView(onOpenAddEmployee: {}, peekRows: DebugPeekSamples.staff()) }
        case "staff-list-empty":
            NavigationStack { EmployeesListView(onOpenAddEmployee: {}, peekRows: []) }
        case "add-staff":
            AddEmployeeSheet()
        case "staff-created":
            StaffCredentialsView(member: DebugPeekSamples.staff()[0], password: "Kx7#mQ2vRt9!Yn", onDone: {})
        case "unreachable":
            UnreachableView()
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
            RoleChoiceView(path: path, signedIn: true)
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
        case "productdetail":
            ProductDetailSheet(
                product: Product(
                    id: "00000000-0000-0000-0000-000000000001",
                    wholesalerId: nil, wholesalerEmail: nil,
                    title: "Antique Kundan Necklace", jewelleryType: "necklace", category: "gold",
                    style: "antique", size: "m", stockAvailable: true, makeToOrderDays: nil,
                    metalPurity: "22k", netWeight: 18.4, grossWeight: 21.1, stoneWeight: 2.7,
                    rawImageURL: nil, processedImageURL: nil, imageURL: nil, generatedImageURLs: [],
                    isPublished: true, createdAt: nil
                ),
                onUpdated: { _ in }
            )
        case "addproduct":
            NavigationStack { AddProductView() }
        case "wholesaler":
            WholesalerShell()
        case "retailer":
            RetailerShell()
        case "employee":
            EmployeeShell()
        case "employee-retailer":
            EmployeeShell(store: DebugPeekSamples.employeeStore(isRetailer: true))
        case "employee-staff":
            EmployeeShell(store: DebugPeekSamples.employeeStore(isRetailer: false))
        case "employee-maharaja":
            EmployeeShell(store: DebugPeekSamples.employeeStore(isRetailer: true, theme: .maharaja))
        case "employee-designs":
            EmployeeDesignsView(onClose: {})
                .environment(DebugPeekSamples.employeeStore(isRetailer: false))
        case "employee-catalogue":
            EmployeeShell(store: DebugPeekSamples.employeeCatalogueStore(), tab: .catalogue)
        case "employee-product":
            EmployeeShell(store: DebugPeekSamples.employeeCatalogueStore(open: "p1", selected: ["p0", "p2", "p3"]),
                          tab: .catalogue)
        case "employee-product-maharaja":
            EmployeeShell(store: DebugPeekSamples.employeeCatalogueStore(open: "p1", theme: .maharaja), tab: .catalogue)
        case "employee-request":
            EmployeeReviewView(productID: "p1", panelOpen: true)
                .environment(DebugPeekSamples.employeeCatalogueStore())
        case "employee-sent":
            EmployeeReviewView(productID: "p1", panelOpen: false, sent: true)
                .environment(DebugPeekSamples.employeeCatalogueStore())
        case "employee-selection":
            EmployeeShell(store: DebugPeekSamples.employeeCatalogueStore(selected: ["p0", "p2", "p3"], review: true),
                          tab: .catalogue)
        case "employee-selection-empty":
            EmployeeShell(store: DebugPeekSamples.employeeCatalogueStore(review: true), tab: .catalogue)
        case "employee-design-detail":
            EmployeeDesignDetail(design: DebugPeekSamples.retailerDesigns()[0], theme: .indian, onClose: {})
        case "setcreation-picker":
            ChamakFlowCoordinator(wholesalerID: UUID(), mode: .setCreation)
                .environment(CreditStore())
        case "setcreation-styling":
            ChamakSetStylingView(
                vm: {
                    let vm = ChamakViewModel()
                    vm.mode = .setCreation
                    vm.step = .setStyling
                    return vm
                }(),
                wholesalerID: UUID()
            )
            .environment(CreditStore())
        case "chamak-picker":
            ChamakFlowCoordinator(wholesalerID: UUID(), mode: .fusion)
                .environment(CreditStore())
        case "chamak-hub":
            NavigationStack { ChamakHubView(gallery: DebugPeekSamples.galleryVM()) }
                .environment(CreditStore())
        case "chamak-hub-empty":
            NavigationStack { ChamakHubView() }
                .environment(CreditStore())
        case "chamak-result":
            ChamakResultView(vm: DebugPeekSamples.resultVM(), wholesalerID: UUID())
                .environment(CreditStore())
        case "chamak-viewer":
            ChamakImageViewer(images: DebugPeekSamples.viewerImages(), startIndex: 2)
        case "chamak-picker-sample":
            ChamakCatalogPickerView(vm: DebugPeekSamples.pickerVM(), wholesalerID: UUID())
                .environment(CreditStore())
        case "topup":
            TopUpSheet(model: TopUpModel(packs: DebugPeekSamples.topUpPacks()))
                .environment(DebugPeekSamples.creditStore(available: 2008))
        case "topup-checkout":
            TopUpSheet(model: {
                let model = TopUpModel(packs: DebugPeekSamples.topUpPacks())
                model.openCheckoutForPeek(URL(string: "https://razorpay.com/payment-links/")!)
                return model
            }())
            .environment(DebugPeekSamples.creditStore(available: 2008))
        case "topup-confirming":
            TopUpSheet(model: TopUpModel(packs: DebugPeekSamples.topUpPacks(), phase: .confirming))
                .environment(DebugPeekSamples.creditStore(available: 2008))
        case "topup-pending":
            TopUpSheet(model: TopUpModel(packs: DebugPeekSamples.topUpPacks(), phase: .pending))
                .environment(DebugPeekSamples.creditStore(available: 2008))
        case "topup-success":
            TopUpSheet(model: TopUpModel(packs: DebugPeekSamples.topUpPacks(), phase: .succeeded(credits: 10000)))
                .environment(DebugPeekSamples.creditStore(available: 12008))
        case "nocredits":
            InsufficientCreditsSheet(error: .init(required: 200, balance: 80, shortBy: 120))
                .environment(DebugPeekSamples.creditStore(available: 80))
        case "home-lowbalance":
            WholesalerShell(credits: DebugPeekSamples.creditStore(available: 280))
        case "theme":
            StoreThemeView()
                .environment(DebugPeekSamples.creditStore(available: 2000))
        case "theme-short":
            StoreThemeView()
                .environment(DebugPeekSamples.creditStore(available: 300))
        case "plans", "plans-active":
            NavigationStack {
                PlansView(peekPlans: DebugPeekSamples.plans())
            }
            .environment({
                let store = DebugPeekSamples.creditStore(available: 4200)
                if id == "plans-active" {
                    store.seedPlanForPeek(PlanStatus(
                        active: true, planKey: "quarterly",
                        expiresAt: Date().addingTimeInterval(62 * 24 * 60 * 60)))
                }
                return store
            }())
        case "retailer-dashboard":
            NavigationStack {
                ScrollView {
                    NewArrivalsStrip(peekProducts: DebugPeekSamples.products())
                        .padding(Spacing.screenGutter)
                }
                .background(Palette.background)
            }
        case "wishlist":
            NavigationStack {
                CustomerWishlistView(peekRows: [
                    StoreCustomer(id: "1", name: "Ananya Sharma", phone: "98765 43210", note: nil, designCount: 7),
                    StoreCustomer(id: "2", name: "Meera Iyer", phone: nil, note: "Wedding in December", designCount: 1),
                    StoreCustomer(id: "3", name: "Kavita", phone: "99887 76655", note: nil, designCount: 0),
                ])
            }
        case "wishlist-empty":
            NavigationStack { CustomerWishlistView(peekRows: []) }
        case "wishlist-boards":
            NavigationStack {
                CustomerBoardsView(
                    customer: StoreCustomer(id: "1", name: "Ananya Sharma", phone: "98765 43210",
                                            note: "Wedding in December · budget ₹4–5L", designCount: 4),
                    peekBoards: [
                        CustomerBoard(id: "b1", title: "Wishlist", products: Array(DebugPeekSamples.products().prefix(4))),
                        CustomerBoard(id: "b2", title: "Reception", products: []),
                    ]
                )
            }
        case "retailer-shell":
            RetailerShell()
        case "images-live":
            // Loads real URLs through ImageCache + ProtectedImageView, so the
            // caching and downsampling can be checked against production
            // images without a session:
            //   simctl launch … -JewelPeek images-live -JewelPeekURLs "<url> <url>"
            LivePeekImages()
        case "catalogue-cards":
            ScrollView {
                LazyVGrid(columns: CatalogueProductCard.gridColumns, spacing: Spacing.md) {
                    ForEach(DebugPeekSamples.products()) { product in
                        CatalogueProductCard(product: product, onEdit: {}, onDelete: {})
                    }
                }
                .padding(Spacing.screenGutter)
            }
            .background(Palette.background)
        default:
            PhasePlaceholder(title: "Unknown peek", note: id)
        }
    }
}

/// Sample Chamak data for the peeks. Images are bundled category photos
/// written to temp files, so `ProtectedImageView` loads real pixels with no
/// network or session.
@MainActor
enum DebugPeekSamples {
    static func fileURL(for asset: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("peek-\(asset).jpg")
        if !FileManager.default.fileExists(atPath: url.path) {
            guard let data = UIImage(named: asset)?.jpegData(compressionQuality: 0.9) else { return nil }
            try? data.write(to: url)
        }
        return url
    }

    static func pickerVM() -> ChamakViewModel {
        let vm = ChamakViewModel()
        vm.mode = .fusion
        vm.catalogProducts = products()
        if let first = vm.catalogProducts.first {
            vm.selectProduct(first)
        }
        return vm
    }

    static func generation(mode: ChamakMode, status: String, source: String, upgrade: String) -> ChamakGeneration? {
        var json: [String: Any] = [
            "id": UUID().uuidString,
            "wholesaler_id": UUID().uuidString,
            "source_image_1_url": fileURL(for: source)?.absoluteString ?? "",
            "source_image_2_url": fileURL(for: upgrade)?.absoluteString ?? "",
            "prompt_version": "v2.0-chamak",
            "output_image_url": "peek/output.png",
            "status": status,
            "created_at": "2026-09-10T10:30:00Z",
            "mode": mode.rawValue
        ]
        if mode == .setCreation { json["set_backdrop"] = SetBackdrop.velvetBust.rawValue }
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? JSONDecoder().decode(ChamakGeneration.self, from: data)
    }

    static func galleryVM() -> ChamakViewModel {
        let vm = ChamakViewModel()
        let rows: [(ChamakMode, String, String, String, String)] = [
            (.fusion, "done", "CatNecklace", "CatHaram", "CatPendants"),
            (.setCreation, "done", "CatEarrings", "CatNecklace", "CatMangalsutras"),
            (.fusion, "generating", "CatRings", "CatBangles", ""),
            (.fusion, "failed", "CatChains", "CatNosepins", "")
        ]
        for (mode, status, source, upgrade, output) in rows {
            guard let gen = generation(mode: mode, status: status, source: source, upgrade: upgrade) else { continue }
            vm.galleryGenerations.append(gen)
            if !output.isEmpty { vm.galleryThumbnailURLs[gen.id] = fileURL(for: output) }
        }
        return vm
    }

    static func resultVM() -> ChamakViewModel {
        let vm = ChamakViewModel()
        vm.mode = .fusion
        vm.step = .result
        vm.currentGeneration = generation(mode: .fusion, status: "done", source: "CatNecklace", upgrade: "CatHaram")
        vm.signedOutputImageURL = fileURL(for: "CatPendants")
        return vm
    }

    static func products() -> [Product] {
        let rows: [(String, String, String, Bool, Int?)] = [
            ("Temple Haram with Emerald Drops", "CatHaram", "gold", true, nil),
            ("Kundan Choker", "CatNecklace", "gold", true, nil),
            ("Solitaire Pendant", "CatPendants", "diamond", false, 12),
            ("Traditional Mangalsutra", "CatMangalsutras", "gold", true, nil),
            ("Antique Bangles Pair", "CatBangles", "gold", false, 7),
            ("Cocktail Ring", "CatRings", "diamond", true, nil)
        ]
        return rows.enumerated().map { index, row in
            let (title, asset, category, inStock, days) = row
            return Product(
                id: "00000000-0000-0000-0000-00000000000\(index)",
                wholesalerId: nil, wholesalerEmail: nil,
                title: title, jewelleryType: "necklace", category: category,
                style: nil, size: nil, stockAvailable: inStock, makeToOrderDays: days,
                metalPurity: index.isMultiple(of: 2) ? "22k" : "24k",
                netWeight: 12 + Double(index) * 3.5, grossWeight: nil, stoneWeight: nil,
                rawImageURL: nil, processedImageURL: fileURL(for: asset)?.absoluteString,
                imageURL: nil, generatedImageURLs: [],
                isPublished: true, createdAt: nil
            )
        }
    }

    static func topUpPacks() -> [TopUpPack] {
        [("starter", "Starter", 500.0, 5000),
         ("popular", "Popular", 1000.0, 10000),
         ("pro", "Pro", 2500.0, 25000),
         ("bulk", "Bulk", 5000.0, 50000)]
            .map { key, label, price, credits in
                TopUpPack(key: key, label: label, priceINR: price, gstINR: price * 0.18,
                          totalINR: price * 1.18, credits: credits)
            }
    }

    /// A wallet at `available` credits, with the live rate card's Fusion price.
    static func creditStore(available: Int) -> CreditStore {
        let store = CreditStore()
        let walletJSON = """
            {"ok": true, "available": \(available), "lifetime_granted": \(max(available, 2000)),
             "lifetime_spent": 0, "lifetime_expired": 0, "expiring_soon": 0,
             "low_balance": \(available < 400), "low_balance_threshold": 400}
            """
        let pricesJSON = """
            [{"feature_key": "chamak.generate", "credits": 200, "label": "Chamak Fusion", "is_active": true, "sort_order": 1},
             {"feature_key": "chamak.reroll", "credits": 120, "label": "Re-roll", "is_active": true, "sort_order": 2},
             {"feature_key": "theme.utsav", "credits": 500, "label": "Utsav store theme", "is_active": true, "sort_order": 110},
             {"feature_key": "theme.neelam", "credits": 500, "label": "Neelam store theme", "is_active": true, "sort_order": 120},
             {"feature_key": "plan.monthly", "credits": 3000, "label": "Monthly plan", "is_active": true, "sort_order": 210},
             {"feature_key": "plan.quarterly", "credits": 8000, "label": "Quarterly plan", "is_active": true, "sort_order": 220},
             {"feature_key": "plan.yearly", "credits": 30000, "label": "Yearly plan", "is_active": true, "sort_order": 230}]
            """
        if let wallet = try? JSONDecoder().decode(CreditWallet.self, from: Data(walletJSON.utf8)),
           let prices = try? JSONDecoder().decode([CreditPrice].self, from: Data(pricesJSON.utf8)) {
            store.seedForPeek(wallet: wallet, rateCard: prices)
        }
        return store
    }

    static func plans() -> [Plan] {
        [
            Plan(key: "monthly", label: "Monthly", periodDays: 30, perks: ["Every store theme unlocked"]),
            Plan(key: "quarterly", label: "Quarterly", periodDays: 90,
                 perks: ["Every store theme unlocked", "Save 11% against monthly"]),
            Plan(key: "yearly", label: "Yearly", periodDays: 365,
                 perks: ["Every store theme unlocked", "Save 17% against monthly"]),
        ]
    }

    static func retailerDesigns() -> [RetailerDesign] {
        let rows: [(String, String, String?, String?, Double?, Bool?, Int?)] = [
            ("Temple Haram", "CatHaram", "haram", "22k", 42.5, false, 14),
            ("Kundan Choker", "CatNecklace", "necklace", "22k", 18.2, true, nil),
            ("Solitaire Pendant", "CatPendants", "pendants", "18k", 4.1, true, nil),
            ("Everyday Mangalsutra", "CatMangalsutras", "mangalsutras", "22k", 9.8, false, 7),
            ("Antique Bangles", "CatBangles", "bangles", "24k", 31.0, false, 21),
            ("Cocktail Ring", "CatRings", "rings", "18k", 6.4, true, nil),
            ("Jhumka Earrings", "CatEarrings", "earrings", "22k", 12.3, true, nil),
        ]
        return rows.enumerated().map { i, row in
            RetailerDesign(id: "d\(i)", imageURL: fileURL(for: row.1)?.absoluteString, title: row.0,
                           category: row.2, type: row.2, purity: row.3, netWeight: row.4,
                           grossWeight: row.4.map { $0 + 1.2 }, stoneWeight: 1.2,
                           styleAesthetic: i.isMultiple(of: 2) ? "Traditional" : "Contemporary",
                           isInStock: row.5, productionTimeDays: row.6)
        }
    }

    static func employeeStore(isRetailer: Bool, theme: EmployeeTheme = .indian) -> EmployeeStore {
        let store = EmployeeStore()
        store.seedForPeek(
            designs: retailerDesigns(),
            EmployeeSession(
                identity: isRetailer ? .store : .employee(id: "3f2b8c1e-9d4a-4e6b-8a7c-2d1e0f9b5a34"),
                retailerID: "b8b1a1d2-0000-4000-8000-000000000001",
                isRetailer: isRetailer,
                storeName: "Parash The Dev",
                storeLogoURL: nil,
                theme: theme
            ),
            unreadQueries: true,
            unreadOrders: true
        )
        return store
    }

    /// A store with a shortlist of ten pieces, one page and a bit.
    static func employeeCatalogueStore(open productID: String? = nil, selected: [String] = [],
                                       review: Bool = false, theme: EmployeeTheme = .indian) -> EmployeeStore {
        let store = employeeStore(isRetailer: true, theme: theme)
        var routes: [EmployeeRoute] = []
        if let productID { routes.append(.review(productID: productID)) }
        if review { routes.append(.review(productID: nil)) }
        store.seedForPeek(products: employeeProducts(), selected: selected, routes: routes)
        return store
    }

    static func employeeProducts() -> [Product] {
        let rows: [(String, String, String, String?, String?, Bool, Int?, Double)] = [
            ("Temple Haram with Emerald Drops", "CatHaram", "haram", "temple", "large", false, 14, 42.5),
            ("Kundan Choker Necklace", "CatNecklace", "necklace", "kundan", "medium", true, nil, 18.2),
            ("Solitaire Pendant", "CatPendants", "pendants", "contemporary", "small", false, 12, 4.1),
            ("Everyday Mangalsutra", "CatMangalsutras", "mangalsutras", "traditional", "medium", true, nil, 9.8),
            ("Antique Bangles Pair", "CatBangles", "bangles", "antique", "adjustable", false, 21, 31),
            ("Cocktail Ring", "CatRings", "rings", "contemporary", "small", true, nil, 6.4),
            ("Jhumka Earrings", "CatEarrings", "earrings", "traditional", "small", true, nil, 12.3),
            ("Rope Chain", "CatChains", "chains", nil, "medium", false, 5, 22),
            ("Diamond Nosepin", "CatNosepins", "nosepin", nil, "small", true, nil, 0.8),
            ("Lakshmi Coin Necklace", "CatNecklace", "necklace", "temple", "large", false, 30, 55),
        ]
        return rows.enumerated().map { index, row in
            let (title, asset, category, style, size, inStock, days, weight) = row
            let image = fileURL(for: asset)?.absoluteString
            let second = fileURL(for: index.isMultiple(of: 2) ? "CatPendants" : "CatHaram")?.absoluteString
            return Product(
                id: "p\(index)",
                wholesalerId: nil, wholesalerEmail: nil,
                title: title, jewelleryType: category, category: category,
                style: style, size: size, stockAvailable: inStock, makeToOrderDays: days,
                metalPurity: index.isMultiple(of: 3) ? "18k" : "22k",
                netWeight: weight, grossWeight: weight + 1.5, stoneWeight: index.isMultiple(of: 2) ? 1.2 : nil,
                rawImageURL: nil, processedImageURL: image,
                imageURL: nil, generatedImageURLs: [image, second].compactMap { $0 },
                isPublished: true, createdAt: nil
            )
        }
    }

    static func staff() -> [StaffMember] {
        [
            StaffMember(id: "s1", fullName: "Priya Sharma", email: "priya.pinejewels@jewelindia.shop",
                        designation: "Store Manager", phone: "9876543210", status: .active, joinMethod: "password"),
            StaffMember(id: "s2", fullName: "Ravi Kumar", email: "ravi.kumar@gmail.com", inviteEmail: "ravi.kumar@gmail.com",
                        designation: "Sales Associate", status: .invited, joinMethod: "google"),
            StaffMember(id: "s3", fullName: "Meena Iyer", email: "meena.pinejewels@jewelindia.shop",
                        designation: "Sales Associate", status: .inactive, joinMethod: "password"),
        ]
    }

    static func viewerImages() -> [ChamakViewerImage] {
        [("source", "Source", "CatNecklace", false),
         ("upgrade", "Upgrade", "CatHaram", false),
         ("result", "Result", "CatPendants", true)]
            .compactMap { id, label, asset, isResult in
                fileURL(for: asset).map {
                    ChamakViewerImage(id: id, label: label, url: $0, isResult: isResult)
                }
            }
    }
}

/// A grid of real remote images, for checking the loading path end to end.
/// URLs come from `-JewelPeekURLs "<url> <url>"`, so none are baked in here.
private struct LivePeekImages: View {
    private var urls: [URL] {
        (UserDefaults.standard.string(forKey: "JewelPeekURLs") ?? "")
            .split(whereSeparator: \.isWhitespace)
            .compactMap { URL(string: String($0)) }
    }

    var body: some View {
        ScrollView {
            if urls.isEmpty {
                Text("Pass -JewelPeekURLs \"<url> <url>\"")
                    .font(.manrope(13))
                    .foregroundStyle(Palette.muted)
                    .padding(Spacing.xl)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.md)], spacing: Spacing.md) {
                ForEach(urls, id: \.self) { url in
                    Color(hex: 0xF3F4F6)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay { ProtectedImageView(url: url) }
                        .clipShape(.rect(cornerRadius: 12))
                }
            }
            .padding(Spacing.screenGutter)
        }
        .background(Palette.background)
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
