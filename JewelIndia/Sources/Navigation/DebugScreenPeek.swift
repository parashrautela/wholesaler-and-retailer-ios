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
        case "employeehome":
            NavigationStack { EmployeeHomeView(onSelectTab: { _ in }) }
        case "employeegallery":
            NavigationStack { EmployeeGalleryView() }
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

    static func generation(mode: ChamakMode, status: String, source: String, upgrade: String) -> ChamakGeneration? {
        let json: [String: Any] = [
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
