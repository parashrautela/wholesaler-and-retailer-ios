import Supabase
import SwiftUI

// MARK: - Data

/// What `wholesaler_report(period)` answers: the last 7 or 30 days of the
/// wholesaler's own designs, each count beside the period before it.
struct WholesalerReport: Decodable, Sendable {
    enum Period: String, CaseIterable, Identifiable, Sendable {
        case week, month
        var id: String { rawValue }
        var title: String { self == .week ? "This Week" : "This Month" }
        var span: String { self == .week ? "last 7 days" : "last 30 days" }
        var previous: String { self == .week ? "last week" : "last month" }
    }

    struct Design: Decodable, Identifiable, Sendable {
        let productID: String
        let title: String?
        let image: String?
        let likes: Int?
        let views: Int?
        var id: String { productID }
        var imageURL: URL? { image?.trimmed.nilIfEmpty.flatMap(URL.init(string:)) }
        var name: String { title?.trimmed.nilIfEmpty ?? "Your design" }

        enum CodingKeys: String, CodingKey {
            case title, image, likes, views
            case productID = "product_id"
        }
    }

    let likes: Int
    let likesPrev: Int
    let topLiked: [Design]
    let views: Int
    let viewsPrev: Int
    let topViewed: Design?
    let ordersNew: Int
    let ordersNewPrev: Int
    let ordersAccepted: Int
    let ordersCompleted: Int
    let ordersRejected: Int
    let questions: Int
    let questionsPrev: Int
    let conversations: Int
    let stores: Int
    let storesPrev: Int

    enum CodingKeys: String, CodingKey {
        case likes, views, questions, conversations, stores
        case likesPrev = "likes_prev"
        case topLiked = "top_liked"
        case viewsPrev = "views_prev"
        case topViewed = "top_viewed"
        case ordersNew = "orders_new"
        case ordersNewPrev = "orders_new_prev"
        case ordersAccepted = "orders_accepted"
        case ordersCompleted = "orders_completed"
        case ordersRejected = "orders_rejected"
        case questionsPrev = "questions_prev"
        case storesPrev = "stores_prev"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ key: CodingKeys) -> Int { (try? c.decodeIfPresent(Int.self, forKey: key)) ?? 0 }
        likes = int(.likes); likesPrev = int(.likesPrev)
        topLiked = (try? c.decodeIfPresent([Design].self, forKey: .topLiked)) ?? []
        views = int(.views); viewsPrev = int(.viewsPrev)
        topViewed = try? c.decodeIfPresent(Design.self, forKey: .topViewed)
        ordersNew = int(.ordersNew); ordersNewPrev = int(.ordersNewPrev)
        ordersAccepted = int(.ordersAccepted); ordersCompleted = int(.ordersCompleted)
        ordersRejected = int(.ordersRejected)
        questions = int(.questions); questionsPrev = int(.questionsPrev)
        conversations = int(.conversations)
        stores = int(.stores); storesPrev = int(.storesPrev)
    }

    static func fetch(_ period: Period) async throws -> WholesalerReport {
        try await SupabaseManager.client
            .rpc("wholesaler_report", params: ["p_period": period.rawValue])
            .execute()
            .value
    }

    #if DEBUG
    static func sample() -> WholesalerReport {
        let json = """
        {"likes": 34, "likes_prev": 21, "views": 212, "views_prev": 180,
         "orders_new": 6, "orders_new_prev": 4, "orders_accepted": 5, "orders_completed": 3, "orders_rejected": 1,
         "questions": 9, "questions_prev": 12, "conversations": 4, "stores": 11, "stores_prev": 8,
         "top_liked": [
           {"product_id": "a", "title": "Temple Haram", "image": "https://ljxgwiuvdpuarvdszjts.supabase.co/storage/v1/object/public/plant-images/products/processed/ad07ac3e-a6ea-4ded-9b5d-916d8aa570e1_v1.png", "likes": 20},
           {"product_id": "b", "title": "Kundan Choker", "image": null, "likes": 9},
           {"product_id": "c", "title": "Solitaire Pendant", "image": null, "likes": 5}],
         "top_viewed": {"product_id": "a", "title": "Temple Haram", "image": null, "views": 64}}
        """
        return try! JSONDecoder().decode(WholesalerReport.self, from: Data(json.utf8))
    }
    #endif
}

// MARK: - Cards

/// One card in the stack.
private struct ReportCard: Identifiable {
    enum Kind {
        case summary
        case liked(WholesalerReport.Design, rank: Int)
        case orders
        case attention
        case reach
        case end
    }
    let id: String
    let kind: Kind
}

// MARK: - Screen

/// The weekly or monthly report as a stack of cards: swipe either way (or
/// tap) for the next, the way stacked notifications are flicked through.
struct WholesalerReportView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var period: WholesalerReport.Period = .week
    @State private var report: WholesalerReport?
    @State private var isLoading = true
    @State private var failed = false
    @State private var index = 0
    @State private var drag: CGSize = .zero

    #if DEBUG
    var peekReport: WholesalerReport?
    #endif

    private var cards: [ReportCard] {
        guard let report else { return [] }
        var all = [ReportCard(id: "summary", kind: .summary)]
        for (i, design) in report.topLiked.prefix(3).enumerated() where (design.likes ?? 0) > 0 {
            all.append(ReportCard(id: "liked-\(design.id)", kind: .liked(design, rank: i + 1)))
        }
        all.append(ReportCard(id: "orders", kind: .orders))
        all.append(ReportCard(id: "attention", kind: .attention))
        all.append(ReportCard(id: "reach", kind: .reach))
        all.append(ReportCard(id: "end", kind: .end))
        return all
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Picker("Period", selection: $period) {
                    ForEach(WholesalerReport.Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.screenGutter)

                if isLoading && report == nil {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if failed && report == nil {
                    Spacer()
                    ContentUnavailableView {
                        Label("Couldn't load your report", systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("Try Again") { Task { await load() } }
                    }
                    Spacer()
                } else {
                    stack
                    progressDots
                }
            }
            .padding(.vertical, Spacing.md)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Your Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: period) { await load() }
        }
    }

    // MARK: Stack

    private var stack: some View {
        let all = cards
        return ZStack {
            // The next two peek out from behind, like stacked notifications.
            ForEach(Array(all.enumerated()).reversed(), id: \.element.id) { offset, card in
                let depth = offset - index
                if depth >= 0 && depth < 3 {
                    cardView(card)
                        .scaleEffect(1 - CGFloat(depth) * 0.05)
                        .offset(y: CGFloat(depth) * 14)
                        .opacity(depth == 0 ? 1 : 0.9 - Double(depth) * 0.2)
                        .offset(depth == 0 ? drag : .zero)
                        .rotationEffect(.degrees(depth == 0 ? Double(drag.width / 22) : 0))
                        .allowsHitTesting(depth == 0)
                        .gesture(depth == 0 ? swipe(total: all.count) : nil)
                        .onTapGesture { if depth == 0 { advance(total: all.count, direction: 1) } }
                        .accessibilityHidden(depth != 0)
                }
            }
        }
        .padding(.horizontal, Spacing.screenGutter)
        .frame(maxHeight: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: index)
    }

    private func swipe(total: Int) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                let flick = value.predictedEndTranslation.width
                if abs(flick) > 120 {
                    let direction: CGFloat = flick > 0 ? 1 : -1
                    withAnimation(.easeOut(duration: 0.2)) {
                        drag = CGSize(width: direction * 600, height: value.translation.height)
                    }
                    Task {
                        try? await Task.sleep(for: .milliseconds(180))
                        drag = .zero
                        advance(total: total, direction: 1)
                    }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drag = .zero }
                }
            }
    }

    private func advance(total: Int, direction: Int) {
        guard total > 0 else { return }
        // After the last card, start again from the top.
        index = (index + direction + total) % total
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<cards.count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Palette.dark : Palette.border)
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .animation(.easeOut(duration: 0.2), value: index)
        .accessibilityLabel("Card \(index + 1) of \(cards.count)")
    }

    // MARK: Card faces

    @ViewBuilder
    private func cardView(_ card: ReportCard) -> some View {
        if let report {
            switch card.kind {
            case .summary:
                face(tint: [Color(hex: 0x1F1B16), Color(hex: 0x4A3B28)], dark: true) {
                    eyebrow("Your \(period.rawValue) on Jewel India", dark: true)
                    Text(headline(report))
                        .font(.cirka(30))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    HStack(spacing: Spacing.md) {
                        big(report.likes, "likes", dark: true)
                        big(report.ordersNew, "new orders", dark: true)
                        big(report.stores, "stores", dark: true)
                    }
                    swipeHint(dark: true)
                }
            case .liked(let design, let rank):
                face(tint: [Color(hex: 0xFFF7ED), Color(hex: 0xFDE7C7)]) {
                    eyebrow(rank == 1 ? "Top design this \(period.rawValue)" : "#\(rank) most liked")
                    ZStack {
                        Color.white
                        if let url = design.imageURL {
                            CachedImage(url: url)
                        } else {
                            Image(systemName: "photo").font(.largeTitle).foregroundStyle(Palette.muted)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    Text("\(design.name) got \(design.likes ?? 0) \(design.likes == 1 ? "like" : "likes")")
                        .font(.cirka(26))
                        .foregroundStyle(Palette.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(rank == 1 ? "It did really well \(period == .week ? "this week" : "this month"). Stores are noticing it." : "Liked by stores and their staff.")
                        .font(.manrope(13))
                        .foregroundStyle(Palette.muted)
                    Spacer(minLength: 0)
                }
            case .orders:
                face(tint: [Color.white, Color(hex: 0xEEF2FF)]) {
                    eyebrow("Orders")
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(report.ordersNew)").font(.cirka(64)).foregroundStyle(Palette.foreground)
                        Text("new \(report.ordersNew == 1 ? "order" : "orders")")
                            .font(.manrope(16, weight: .semibold)).foregroundStyle(Palette.foreground)
                    }
                    change(report.ordersNew, report.ordersNewPrev)
                    Spacer()
                    VStack(spacing: Spacing.sm) {
                        stat("Accepted", report.ordersAccepted, symbol: "checkmark.circle")
                        stat("Completed", report.ordersCompleted, symbol: "shippingbox")
                        stat("Rejected", report.ordersRejected, symbol: "xmark.circle")
                    }
                }
            case .attention:
                face(tint: [Color.white, Color(hex: 0xECFDF5)]) {
                    eyebrow("Views & questions")
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(report.views)").font(.cirka(64)).foregroundStyle(Palette.foreground)
                        Text("design views").font(.manrope(16, weight: .semibold)).foregroundStyle(Palette.foreground)
                    }
                    change(report.views, report.viewsPrev)
                    if let top = report.topViewed, (top.views ?? 0) > 0 {
                        Text("Most opened: \(top.name) · \(top.views ?? 0) views")
                            .font(.manrope(13))
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    VStack(spacing: Spacing.sm) {
                        stat("Questions from stores", report.questions, symbol: "bubble.left")
                        stat("Conversations", report.conversations, symbol: "bubble.left.and.bubble.right")
                    }
                }
            case .reach:
                face(tint: [Color.white, Color(hex: 0xFDF2F8)]) {
                    eyebrow("Store reach")
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(report.stores)").font(.cirka(64)).foregroundStyle(Palette.foreground)
                        Text(report.stores == 1 ? "store" : "stores")
                            .font(.manrope(16, weight: .semibold)).foregroundStyle(Palette.foreground)
                    }
                    change(report.stores, report.storesPrev)
                    Text("Different stores that liked, opened, asked about or ordered your designs.")
                        .font(.manrope(13))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            case .end:
                face(tint: [Color(hex: 0x1F1B16), Color(hex: 0x4A3B28)], dark: true) {
                    eyebrow("That's your \(period.rawValue)", dark: true)
                    Text("Upload new designs to give stores more to like.")
                        .font(.cirka(28))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text("Swipe to start again")
                        .font(.manrope(12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private func headline(_ r: WholesalerReport) -> String {
        if let top = r.topLiked.first, (top.likes ?? 0) > 0 {
            return "\(top.name) was your star, with \(top.likes ?? 0) \(top.likes == 1 ? "like" : "likes")."
        }
        if r.ordersNew > 0 { return "You received \(r.ordersNew) new \(r.ordersNew == 1 ? "order" : "orders")." }
        return "A quiet \(period.rawValue). Here's where you stand."
    }

    private func face<Content: View>(tint: [Color], dark: Bool = false,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) { content() }
            .padding(Spacing.xl)
            .frame(maxWidth: 440, maxHeight: 520, alignment: .topLeading)
            .background(LinearGradient(colors: tint, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).stroke(dark ? .clear : Palette.border, lineWidth: 1) }
            .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
            .accessibilityElement(children: .combine)
    }

    private func eyebrow(_ text: String, dark: Bool = false) -> some View {
        Text(text.uppercased())
            .font(.manrope(11, weight: .bold))
            .kerning(1)
            .foregroundStyle(dark ? Color(hex: 0xE4CC8F) : Palette.muted)
    }

    private func big(_ value: Int, _ label: String, dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.cirka(34)).foregroundStyle(dark ? .white : Palette.foreground)
            Text(label).font(.manrope(11, weight: .semibold)).foregroundStyle(dark ? .white.opacity(0.7) : Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ label: String, _ value: Int, symbol: String) -> some View {
        HStack {
            Label(label, systemImage: symbol)
                .font(.manrope(14))
                .foregroundStyle(Palette.foreground)
            Spacer()
            Text("\(value)").font(.manrope(16, weight: .bold)).foregroundStyle(Palette.foreground)
        }
        .padding(12)
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func change(_ now: Int, _ before: Int) -> some View {
        let diff = now - before
        if diff != 0 || before > 0 {
            Label(diff == 0 ? "Same as \(period.previous)"
                            : "\(abs(diff)) \(diff > 0 ? "more" : "fewer") than \(period.previous)",
                  systemImage: diff > 0 ? "arrow.up.right" : diff < 0 ? "arrow.down.right" : "equal")
                .font(.manrope(13, weight: .semibold))
                .foregroundStyle(diff > 0 ? Color(hex: 0x047857) : diff < 0 ? Color(hex: 0xB45309) : Palette.muted)
        }
    }

    private func swipeHint(dark: Bool) -> some View {
        Label("Swipe for more", systemImage: "hand.draw")
            .font(.manrope(12, weight: .semibold))
            .foregroundStyle(dark ? .white.opacity(0.6) : Palette.muted)
    }

    private func load() async {
        #if DEBUG
        if let peekReport { report = peekReport; isLoading = false; index = 0; return }
        #endif
        isLoading = true
        defer { isLoading = false }
        do {
            report = try await WholesalerReport.fetch(period)
            failed = false
            index = 0
        } catch {
            if error is CancellationError { return }
            failed = true
        }
    }
}

// MARK: - Home entry

/// The report's doorway on Home: a small stack of cards with this week's
/// headline numbers.
struct WholesalerReportTeaser: View {
    let action: () -> Void
    @State private var report: WholesalerReport?

    #if DEBUG
    var peekReport: WholesalerReport?
    #endif

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .top) {
                // Two cards peeking out underneath.
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: 0xE9DFCF))
                    .padding(.horizontal, 20)
                    .offset(y: 12)
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: 0xD9C9AE))
                    .padding(.horizontal, 10)
                    .offset(y: 6)
                HStack(spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("YOUR WEEKLY REPORT")
                            .font(.manrope(10, weight: .bold))
                            .kerning(1)
                            .foregroundStyle(Color(hex: 0xE4CC8F))
                        Text(line)
                            .font(.manrope(14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Color(hex: 0x1F1B16), Color(hex: 0x4A3B28)],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.bottom, 12)
        }
        .buttonStyle(PressableButtonStyle())
        .task {
            #if DEBUG
            if let peekReport { report = peekReport; return }
            #endif
            report = try? await WholesalerReport.fetch(.week)
        }
        .accessibilityLabel("Your weekly report. \(line)")
    }

    private var line: String {
        guard let report else { return "Likes, orders and store reach — swipe through your week." }
        if let top = report.topLiked.first, (top.likes ?? 0) > 0 {
            return "\(top.name) got \(top.likes ?? 0) likes · \(report.ordersNew) new orders"
        }
        return "\(report.likes) likes · \(report.ordersNew) new orders · \(report.stores) stores"
    }
}
