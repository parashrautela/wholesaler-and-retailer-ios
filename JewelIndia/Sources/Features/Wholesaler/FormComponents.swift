import SwiftUI

/// Form controls ported from `components/ui/{Input,Select,InputWithSuffix,Toggle}.jsx`
/// and the numbered section headers on the add-product screen.

/// A black circle badge with the step number, plus the section title and blurb.
struct SectionHeader: View {
    let number: Int
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(.black, in: .circle)

                Text(title)
                    .font(.gilroy(20, weight: .bold))
                    .foregroundStyle(Color(hex: 0x111827))
            }
            Text(subtitle)
                .font(.gilroy(13))
                .foregroundStyle(Color(hex: 0x6B7280))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Spacing.sm)
    }
}

/// Label + control + error text.
struct LabelledField<Content: View>: View {
    let label: String
    var error: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.gilroy(13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x374151))
            content
            if let error {
                Text(error)
                    .font(.gilroy(12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xEF4444))
            }
        }
    }
}

extension View {
    /// `h-11 border-#e5e5e5 rounded-lg px-3 text-sm`, focus ring `#3B82F6`,
    /// error ring red.
    func fieldChrome(hasError: Bool) -> some View {
        self
            .font(.system(size: 14))
            .foregroundStyle(Color(hex: 0x111827))
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Color.white, in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        hasError ? Color(hex: 0xEF4444) : Color(hex: 0xE5E5E5),
                        lineWidth: hasError ? 1.5 : 1
                    )
            }
    }
}

/// The headless `Select`. The web renders a button plus a popup list; a native
/// `Menu` is the direct equivalent and gets keyboard/VoiceOver support free.
struct JewelSelect: View {
    let label: String
    let options: [AddProductForm.Option]
    @Binding var selection: String
    var error: String?

    private var selectedLabel: String? {
        options.first { $0.value == selection }?.label
    }

    var body: some View {
        LabelledField(label: label, error: error) {
            Menu {
                ForEach(options) { option in
                    Button {
                        selection = option.value
                    } label: {
                        if selection == option.value {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                HStack {
                    // The web passes `placeholderClassName="text-black"` here,
                    // so the unselected placeholder is black, not grey.
                    Text(selectedLabel ?? "select")
                        .font(.gilroy(14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x111827))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x6B7280))
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Color.white, in: .rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            error != nil ? Color(hex: 0xEF4444) : Color(hex: 0xE5E5E5),
                            lineWidth: error != nil ? 1.5 : 1
                        )
                }
            }
        }
    }
}

/// `InputWithSuffix` — numeric field with a grey unit cell on the trailing edge.
struct InputWithSuffix: View {
    let label: String
    let suffix: String
    var placeholder: String = "0.00"
    @Binding var text: String
    var error: String?

    @FocusState private var focused: Bool

    var body: some View {
        LabelledField(label: label, error: error) {
            HStack(spacing: 0) {
                TextField(placeholder, text: $text)
                    .focused($focused)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: 0x111827))
                    .padding(.horizontal, 12)

                Text(suffix)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: 0x6B7280))
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Color(hex: 0xF9FAFB))
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color(hex: 0xE5E5E5)).frame(width: 1)
                    }
            }
            .frame(height: 44)
            .background(Color.white, in: .rect(cornerRadius: 8))
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        error != nil ? Color(hex: 0xEF4444)
                            : (focused ? Color(hex: 0x3B82F6) : Color(hex: 0xE5E5E5)),
                        lineWidth: error != nil || focused ? 1.5 : 1
                    )
            }
        }
    }
}

/// `Toggle` — 44×24 track, green when on, 20pt white knob.
struct JewelToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Capsule()
                .fill(isOn ? Color(hex: 0x22C55E) : Color(hex: 0xE5E7EB))
                .frame(width: 44, height: 24)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 20, height: 20)
                        .padding(.horizontal, 2)
                }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isOn)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// The submission error banner.
struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("!")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color(hex: 0xEF4444), in: .circle)

            VStack(alignment: .leading, spacing: 4) {
                Text("Submission Error")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: 0x7F1D1D))
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: 0xB91C1C))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.base)
        .background(Color(hex: 0xFEF2F2), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0xFECACA), lineWidth: 1)
        }
        .transition(.opacity)
    }
}

/// The 40×40 ring spinner used by the submit overlay:
/// `border-[1.5px] border-celestique-taupe border-t-black`.
struct SpinnerRing: View {
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(Palette.taupe, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .overlay {
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(.black, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            .frame(width: 40, height: 40)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    spinning = true
                }
            }
    }
}

/// `.skeleton-shimmer` — a highlight sweeping across a taupe base.
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.4),
                            .init(color: Palette.shimmerHighlight, location: 0.5),
                            .init(color: .clear, location: 0.6),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .offset(x: phase * proxy.size.width * 2)
                }
            }
            .clipped()
            .onAppear {
                withAnimation(Motion.shimmer) { phase = 1 }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(ShimmerModifier()) }
}
