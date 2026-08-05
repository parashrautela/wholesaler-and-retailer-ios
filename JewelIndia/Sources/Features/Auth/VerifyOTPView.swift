import SwiftUI

/// `/entry_page/signup/verify-otp` — `components/auth/OtpForm.jsx`.
///
/// Eight single-character boxes with a literal `-` between the fourth and
/// fifth, a 60-second validity countdown resumed from `otp_sent_at`, a 30-second
/// resend cooldown, five resends, then a 24-hour lockout.
struct VerifyOTPView: View {
    @Environment(SessionStore.self) private var session
    @Environment(SignupFlow.self) private var flow
    @Binding var path: [AuthRoute]

    @State private var digits = Array(repeating: "", count: Copy.otpDigitCount)
    @State private var isWrongOTP = false
    @State private var error: String?
    @State private var verifying = false
    @State private var resending = false
    @State private var secondsLeft = 0
    @State private var resendCooldown = 0
    @State private var showStopwatch = true

    @FocusState private var focusedBox: Int?

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var code: String { digits.joined() }
    private var isComplete: Bool { digits.allSatisfy { !$0.isEmpty } }
    private var identity: String { flow.identity ?? "" }

    var body: some View {
        AuthLayout(titleView: AnyView(heading)) {
            subLine
                .padding(.bottom, 32)

            boxes

            if let error {
                Text(error)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AuthColor.errorText)
                    .padding(.top, 12)
            }

            if flow.isLocked {
                lockedBanner.padding(.top, 20)
            } else if showStopwatch {
                timerRow.padding(.top, 20)
            }

            infoNote

            AuthPrimaryButton(
                title: verifying ? Copy.otpSubmitBusy : Copy.otpSubmitIdle,
                height: 48,
                cornerRadius: 12,
                fontSize: 14,
                fontWeight: .bold,
                tracking: 0,
                enabledFill: AuthColor.slate,
                usesOpacityWhenDisabled: true,
                isEnabled: isComplete && !verifying
            ) {
                Task { await verify() }
            }
            .padding(.bottom, 16)

            AuthLegalText(
                fontSize: 13,
                emphasisColor: AuthColor.focusBorder,
                trailingPeriod: true
            )
            .padding(.bottom, 32)
        }
        .animation(Motion.fadeIn, value: error)
        .onAppear(perform: restore)
        .onReceive(ticker) { _ in tick() }
    }

    // MARK: - Heading

    /// Two spans, and the second is hard-coded "Wholesaler Account" on the web
    /// even when `?role=retailer`. Preserved verbatim.
    private var heading: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Copy.otpHeadingLine1)
            Text(Copy.otpHeadingLine2)
        }
        // `text-[28px] sm:text-[32px] md:text-[44px]` — an iPhone sits at the
        // base breakpoint, so 28.
        .font(.custom("Georgia", size: 28).weight(.bold))
        .foregroundStyle(AuthColor.ink)
        .padding(.bottom, 8)
    }

    private var subLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Copy.otpSentPrefix)
                .font(.system(size: 14))
                .foregroundStyle(AuthColor.placeholder)
            HStack(spacing: 6) {
                Text(identity)
                    .font(.system(size: 14))
                    .foregroundStyle(AuthColor.text2)
                Button(Copy.otpEdit) {
                    path.removeAll()
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AuthColor.text2)
            }
        }
        .lineSpacing(14 * 0.5)
    }

    // MARK: - Digit boxes

    /// `flex justify-between` with `max-w-[32px]` boxes at the base breakpoint
    /// and `aspect-4/5`, so each box is 32 × 40 and the leftover width becomes
    /// the gaps.
    private var boxes: some View {
        HStack(spacing: 0) {
            ForEach(0..<Copy.otpDigitCount, id: \.self) { index in
                if index > 0 { Spacer(minLength: 2) }
                if index == 4 {
                    Text("-")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(AuthColor.otpBorder)
                        .padding(.horizontal, 2)
                    Spacer(minLength: 2)
                }
                digitBox(index)
            }
        }
    }

    private static let boxWidth: CGFloat = 32
    private static let boxHeight: CGFloat = 40   // aspect-4/5

    private func digitBox(_ index: Int) -> some View {
        TextField("", text: binding(for: index))
            .focused($focusedBox, equals: index)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(isWrongOTP ? AuthColor.errorText : AuthColor.text2)
            .frame(width: Self.boxWidth, height: Self.boxHeight)
            .background(Color.white, in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor(index), lineWidth: 1.5)
            }
            .onKeyPress(.delete) {
                // Backspace on an empty box moves focus back, as on the web.
                if digits[index].isEmpty, index > 0 {
                    focusedBox = index - 1
                    digits[index - 1] = ""
                    return .handled
                }
                return .ignored
            }
    }

    private func borderColor(_ index: Int) -> Color {
        if isWrongOTP { return AuthColor.errorText }
        return focusedBox == index ? AuthColor.focusBorder : AuthColor.otpBorder
    }

    /// Mirrors `handleDigitChange`: strip non-digits, keep the **last**
    /// character, clear the error, auto-advance. A multi-character write (a
    /// paste) is distributed across the remaining boxes.
    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { digits[index] },
            set: { newValue in
                let filtered = newValue.filter(\.isNumber)
                if error != nil { error = nil }
                isWrongOTP = false

                if filtered.count > 1 {
                    distribute(filtered, from: index)
                    return
                }

                digits[index] = String(filtered.suffix(1))
                if !digits[index].isEmpty, index < Copy.otpDigitCount - 1 {
                    focusedBox = index + 1
                }
            }
        )
    }

    /// `handlePaste`: take the first 8 digits, fill from the start, focus
    /// `min(pasted.count, 7)`.
    private func distribute(_ value: String, from index: Int) {
        let pasted = Array(value.prefix(Copy.otpDigitCount))
        let start = pasted.count >= Copy.otpDigitCount ? 0 : index
        for offset in 0..<pasted.count where start + offset < Copy.otpDigitCount {
            digits[start + offset] = String(pasted[offset])
        }
        focusedBox = min(start + pasted.count, Copy.otpDigitCount - 1)
    }

    // MARK: - Timer / resend

    private var timerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Text(Copy.otpValidPrefix)
                    .font(.system(size: 13))
                    .foregroundStyle(AuthColor.placeholder)
                Text(formatted(secondsLeft))
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(AuthColor.text2)
            }

            Button {
                Task { await resend() }
            } label: {
                Text(resending ? Copy.otpResendBusy : Copy.otpResendIdle)
                    .font(.system(size: 13, weight: secondsLeft > 0 ? .regular : .bold))
                    .foregroundStyle(secondsLeft > 0 ? AuthColor.otpBorder : AuthColor.text2)
            }
            .buttonStyle(.plain)
            // Matches the web's disabled expression exactly — `resendCooldown`
            // is deliberately absent here and only guards the handler.
            .disabled(resending || secondsLeft > 0 || flow.remainingResends <= 0)
        }
    }

    private var lockedBanner: some View {
        Text(Copy.otpLocked)
            .font(.system(size: 11, weight: .regular))
            .tracking(11 * 0.1)
            .textCase(.uppercase)
            .foregroundStyle(Color(hex: 0xDC2626))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(hex: 0xFEF2F2))
            .overlay { Rectangle().stroke(Color(hex: 0xFECACA), lineWidth: 1) }
    }

    private var infoNote: some View {
        Text(Copy.otpInfoNote)
            .font(.system(size: 12))
            .foregroundStyle(AuthColor.placeholder)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 40)
            .padding(.bottom, 20)
    }

    private func formatted(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func tick() {
        if secondsLeft > 0 { secondsLeft -= 1 }
        if resendCooldown > 0 { resendCooldown -= 1 }
    }

    /// Mirrors the mount effect: bail to the entry screen with no identity,
    /// honour a live lockout, otherwise resume the countdown from `otp_sent_at`.
    private func restore() {
        guard !identity.isEmpty else {
            path.removeAll()
            return
        }
        if flow.isLocked {
            showStopwatch = false
            return
        }
        secondsLeft = flow.otpSecondsLeft
        showStopwatch = secondsLeft > 0
        focusedBox = 0
    }

    // MARK: - Actions

    private func verify() async {
        guard isComplete else {
            error = Copy.otpIncomplete
            return
        }
        verifying = true
        error = nil

        // Must be latched *before* the call: `verifyOTP` adopts the session
        // internally, and the resulting `authStateChanges` event would re-route
        // the app out of this navigation stack before `.setPassword` is pushed.
        SignupFlow.isCompletingSignup = true

        do {
            let result = try await JewelAPI.verifyOTP(
                identity: identity,
                token: code,
                referralCode: flow.referralCode
            )

            if result.isNewUser {
                verifying = false
                path.append(.setPassword)
                return
            }

            // A returning user is already signed in via the bridged session;
            // the router decides where they land.
            SignupFlow.isCompletingSignup = false
            await session.refreshDestination()
            verifying = false

        } catch let apiError as JewelAPI.APIError {
            SignupFlow.isCompletingSignup = false
            handleWrongOTP(message: apiError.message)
        } catch {
            SignupFlow.isCompletingSignup = false
            handleWrongOTP(message: Copy.otpGenericError)
        }
    }

    /// On failure the web clears every box, returns focus to the first, hides
    /// the stopwatch, and shows its hard-coded message.
    private func handleWrongOTP(message: String) {
        isWrongOTP = true
        showStopwatch = false
        error = message.isEmpty ? Copy.otpGenericError : Copy.otpWrong
        digits = Array(repeating: "", count: Copy.otpDigitCount)
        focusedBox = 0
        verifying = false
    }

    private func resend() async {
        guard !identity.isEmpty, resendCooldown <= 0,
              flow.remainingResends > 0, !flow.isLocked
        else { return }

        resending = true
        do {
            let result = try await JewelAPI.sendOTP(identity: identity)
            flow.otpSentAt = Date()
            flow.remainingResends = result.remainingResends ?? max(0, flow.remainingResends - 1)
            secondsLeft = Copy.otpValiditySeconds
            showStopwatch = true
            isWrongOTP = false
            digits = Array(repeating: "", count: Copy.otpDigitCount)
            focusedBox = 0
            resendCooldown = Copy.otpResendCooldownSeconds
            error = nil
        } catch let apiError as JewelAPI.APIError {
            if apiError.locked {
                flow.lockedUntil = apiError.lockedUntil
                flow.remainingResends = 0
            } else if apiError.cooldown {
                resendCooldown = apiError.waitSeconds ?? Copy.otpResendCooldownSeconds
            }
            error = apiError.message
        } catch {
            self.error = Copy.networkError
        }
        resending = false
    }
}
