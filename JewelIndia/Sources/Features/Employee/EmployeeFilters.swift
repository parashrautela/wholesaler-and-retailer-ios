import SwiftUI

// Pieces shared by the employee Designs and Catalogue screens.

/// The web's category tile artwork (`PREDEFINED_ICONS`), keyed by the
/// lowercased category. They are SVGs, so Cloudinary serves them as WebP.
/// Haram's lives on the web server rather than Cloudinary, so the app's own
/// Haram artwork stands in for it.
enum EmployeeCategoryArt {
    static let names = ["Necklace", "Haram", "Pendants", "Mangalsutras", "Chains",
                        "Bangles", "Rings", "Earrings", "Nosepins"]

    private static let assets: [String: String] = [
        "necklace": "v1777351898/necklace_jqvgjm.svg", "necklaces": "v1777351898/necklace_jqvgjm.svg",
        "pendants": "v1777351894/pendants_d9uvap.svg", "pendant": "v1777351894/pendants_d9uvap.svg",
        "mangalsutras": "v1777351896/mangalsutra_dmoj14.svg", "mangalsutra": "v1777351896/mangalsutra_dmoj14.svg",
        "chain": "v1777351896/chains_tqfmhp.svg", "chains": "v1777351896/chains_tqfmhp.svg",
        "bangles": "v1777351896/bracelets_t1etxd.svg", "bangle": "v1777351896/bracelets_t1etxd.svg",
        "ring": "v1777351897/rings_mbtqqr.svg", "rings": "v1777351897/rings_mbtqqr.svg",
        "earring": "v1777351897/earrings_m7kzmd.svg", "earrings": "v1777351897/earrings_m7kzmd.svg",
        "nosepin": "v1777351899/acessiories_vgm6lr.svg", "nosepins": "v1777351899/acessiories_vgm6lr.svg",
    ]

    static let fallback = CloudinaryArt.url("v1778318368/emp_static4_q0ysjt.svg", width: 200)

    static func url(for key: String) -> URL? {
        assets[key].flatMap { CloudinaryArt.url($0, width: 200) }
    }

    static func isHaram(_ key: String) -> Bool { key == "haram" || key == "harams" }
}

/// A black square category tile with its label, as on the web.
struct EmployeeCategoryTile: View {
    let name: String
    let imageURL: URL?
    let isActive: Bool
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Color.black
                    if EmployeeCategoryArt.isHaram(name.lowercased()) {
                        Image("CatHaram").resizable().scaledToFill()
                    } else {
                        CachedImage(url: imageURL)
                    }
                }
                .opacity(0.9)
                .frame(width: size, height: size)
                .background(Color.black)
                .clipShape(.rect(cornerRadius: 14))
                .padding(2)
                .overlay {
                    if isActive {
                        RoundedRectangle(cornerRadius: 16).stroke(.black, lineWidth: 2)
                    }
                }
                .scaleEffect(isActive ? 1.05 : 1)

                Text(name)
                    .font(.manrope(12, weight: isActive ? .bold : .medium))
                    .foregroundStyle(isActive ? Color(hex: 0x111827) : Color(hex: 0x99A1AF))
                    .lineLimit(1)
            }
            .animation(.easeOut(duration: 0.2), value: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Filter dropdown

/// A 130pt pill that opens a multi-select list which stays open while you
/// tick several options (`FilterDropdown`).
struct EmployeeFilterDropdown: View {
    let label: String
    let options: [String]
    @Binding var selected: Set<String>

    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Text(label)
                    .font(.manrope(13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x4A5565))
                if !selected.isEmpty {
                    Text("\(selected.count)")
                        .font(.manrope(10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .frame(minWidth: 18)
                        .background(.black, in: Capsule())
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: 0x99A1AF))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(width: 130)
            .background(Color.white, in: Capsule())
            .overlay { Capsule().stroke(Color(hex: 0xE5E7EB), lineWidth: 1) }
            .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(options, id: \.self) { option in
                    Button {
                        if selected.contains(option) { selected.remove(option) } else { selected.insert(option) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected.contains(option) ? "checkmark.square.fill" : "square")
                                .font(.system(size: 16))
                                .foregroundStyle(selected.contains(option) ? Color(hex: 0x2B7FFF) : Color(hex: 0x99A1AF))
                            Text(option.capitalized)
                                .font(.manrope(13))
                                .foregroundStyle(Color(hex: 0x364153))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
            .frame(width: 192)
            .background(Color.white)
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("\(label) filter" + (selected.isEmpty ? "" : ", \(selected.count) selected"))
    }
}

/// The four filters and the web's matching rules. AND across groups, OR
/// within one.
struct EmployeeFilterState: Equatable {
    var size: Set<String> = []
    var weight: Set<String> = []
    var availability: Set<String> = []
    var purity: Set<String> = []

    static let sizeOptions = ["small", "medium", "large", "adjustable"]
    static let weightOptions = ["0-2g", "3-5g", "5-10g", "11-20g", "20-30g", "30g+"]
    static let availabilityOptions = ["in stock", "within 5 days", "within 15 days", "within 30 days", "more than 30 days"]
    static let purityOptions = ["18k", "22k", "24k"]

    var isEmpty: Bool { size.isEmpty && weight.isEmpty && availability.isEmpty && purity.isEmpty }

    /// `tags` are matched too, as the web does.
    func matches(size itemSize: String?, purity itemPurity: String?, netWeight: Double?,
                 inStock: Bool?, productionDays: Int?, tags: [String]) -> Bool {
        let lowerTags = tags.map { $0.lowercased() }

        if !size.isEmpty {
            let direct = itemSize.map { size.contains($0.lowercased()) } ?? false
            guard direct || size.contains(where: lowerTags.contains) else { return false }
        }
        if !purity.isEmpty {
            let direct = itemPurity.map { purity.contains($0.lowercased()) } ?? false
            guard direct || purity.contains(where: lowerTags.contains) else { return false }
        }
        if !weight.isEmpty {
            guard let w = netWeight, w > 0 else { return false }
            guard weight.contains(where: { Self.weightMatches($0, w) }) else { return false }
        }
        if !availability.isEmpty {
            guard availability.contains(where: { Self.availabilityMatches($0, inStock: inStock, days: productionDays) }) else {
                return false
            }
        }
        return true
    }

    static func weightMatches(_ option: String, _ w: Double) -> Bool {
        switch option {
        case "0-2g": w <= 2
        case "3-5g": w > 2 && w <= 5
        case "5-10g": w > 5 && w <= 10
        case "11-20g": w > 10 && w <= 20
        case "20-30g": w > 20 && w <= 30
        case "30g+": w > 30
        default: false
        }
    }

    /// The web turns a missing production time into 0 days (`Number(null)`),
    /// so a made-to-order piece with no time set counts as "within 5 days".
    /// Kept as-is so both apps list the same pieces.
    static func availabilityMatches(_ option: String, inStock: Bool?, days: Int?) -> Bool {
        if option == "in stock" { return inStock == true }
        if inStock == true { return false }
        let d = days ?? 0
        switch option {
        case "within 5 days": return d <= 5
        case "within 15 days": return d > 5 && d <= 15
        case "within 30 days": return d > 15 && d <= 30
        case "more than 30 days": return d > 30
        default: return false
        }
    }
}

struct EmployeeFilterRow: View {
    @Binding var state: EmployeeFilterState

    var body: some View {
        FlowRow(spacing: 12) {
            EmployeeFilterDropdown(label: "Size", options: EmployeeFilterState.sizeOptions, selected: $state.size)
            EmployeeFilterDropdown(label: "Weight", options: EmployeeFilterState.weightOptions, selected: $state.weight)
            EmployeeFilterDropdown(label: "Availability", options: EmployeeFilterState.availabilityOptions,
                                   selected: $state.availability)
            EmployeeFilterDropdown(label: "Purity", options: EmployeeFilterState.purityOptions, selected: $state.purity)
        }
    }
}

/// `flex-wrap`: children left to right, wrapping onto new lines.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Smart header

/// The web's sticky header: full at the top, collapsed to the filters while
/// scrolling down, and gone entirely while scrolling back up.
enum SmartHeaderState: Equatable {
    case top, down, up

    static func next(offset: CGFloat, previous: CGFloat) -> SmartHeaderState {
        if offset < 50 { return .top }
        return offset > previous ? .down : .up
    }
}

/// Numbered pages with a centred Next button. The web shows the numbers only
/// on wider screens, which leaves a phone no way back to an earlier page;
/// here they show everywhere.
struct EmployeePager: View {
    let page: Int
    let totalPages: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Button { onSelect(min(totalPages, page + 1)) } label: {
                Text("Next")
                    .font(.manrope(14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                    .background(.black, in: .rect(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.15), radius: 7, y: 4)
            }
            .buttonStyle(PressScaleStyle(scale: 0.97))
            .disabled(page >= totalPages)
            .opacity(page >= totalPages ? 0.4 : 1)

            HStack(spacing: 8) {
                ForEach(1...max(totalPages, 1), id: \.self) { n in
                    if n <= 4 || n == totalPages || abs(n - page) <= 1 {
                        Button { onSelect(n) } label: {
                            Text("\(n)")
                                .font(.manrope(14, weight: n == page ? .heavy : .medium))
                                .foregroundStyle(n == page ? Color(hex: 0x111827) : Color(hex: 0x99A1AF))
                                .padding(.horizontal, 4)
                        }
                        .buttonStyle(.plain)
                    } else if n == 5 && totalPages > 6 {
                        Text(".....")
                            .font(.manrope(14, weight: .medium))
                            .kerning(2.8)
                            .foregroundStyle(Color(hex: 0xD1D5DC))
                    }
                }
            }
        }
        .padding(.top, 80)
        .padding(.bottom, 8)
    }
}
