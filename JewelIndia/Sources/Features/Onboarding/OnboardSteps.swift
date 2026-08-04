import SwiftUI

/// `/onboard` — Step 1, identity + Aadhaar.
struct OnboardStep1View: View {
    @Environment(OnboardFlow.self) private var flow
    let onNext: () -> Void

    var body: some View {
        @Bindable var flow = flow

        OnboardLayout(
            step: 1,
            heading: "Let me get to know you",
            subheading: "We need a few details to verify who you are. This keeps your account and your business safe.",
            showsBack: false
        ) {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                OnboardTextField(
                    label: "Name*",
                    placeholder: "Parash Rautela",
                    text: $flow.name,
                    error: flow.nameError,
                    filter: OnboardFlow.filterName
                )

                OnboardTextField(
                    label: "Aadhar Number*",
                    placeholder: "**** **** ****",
                    text: $flow.aadhar,
                    error: flow.aadharError,
                    keyboard: .numberPad,
                    filter: OnboardFlow.formatAadhar
                )

                HStack(alignment: .top, spacing: Spacing.base) {
                    ImageUploadBox(
                        label: "Aadhar Front*",
                        file: $flow.frontImage,
                        error: flow.frontError
                    )
                    ImageUploadBox(
                        label: "Aadhar Back*",
                        file: $flow.backImage,
                        error: flow.backError
                    )
                }

                OnboardLegalNote()

                OnboardPrimaryButton(title: "Next", isEnabled: flow.step1Valid) {
                    advance()
                }
            }
            .motion(Motion.fadeInUp)
        }
    }

    private func advance() {
        guard flow.step1Valid else {
            flow.submitAttempted = true
            return
        }
        flow.submitAttempted = false
        onNext()
    }
}

/// `/onboard/step2` — business details.
struct OnboardStep2View: View {
    @Environment(OnboardFlow.self) private var flow
    let onNext: () -> Void

    var body: some View {
        @Bindable var flow = flow

        OnboardLayout(
            step: 2,
            heading: "Tell us about your business",
            subheading: "This is how retailers will find and recognise you on the platform."
        ) {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                OnboardTextField(
                    label: "Business name*",
                    placeholder: "Pc jewellers",
                    text: $flow.businessName,
                    error: flow.businessNameError
                )

                statePicker(flow: flow)

                OnboardTextField(
                    label: "City*",
                    placeholder: "select",
                    text: $flow.selectedCity,
                    error: flow.cityError,
                    // The web disables the city input until a state is chosen.
                    disabled: flow.selectedState.isEmpty
                )

                ImageUploadBox(
                    label: "Business Logo",
                    file: $flow.logoImage,
                    error: flow.logoError,
                    contentMode: .fit          // objectFit="contain"
                )

                OnboardLegalNote()

                OnboardPrimaryButton(title: "Next", isEnabled: flow.step2Valid) {
                    advance()
                }
            }
            .motion(Motion.fadeInUp)
        }
    }

    /// The web uses a native `<select>` whose first option is a disabled
    /// placeholder reading "select".
    private func statePicker(flow: OnboardFlow) -> some View {
        @Bindable var flow = flow
        return VStack(alignment: .leading, spacing: 8) {
            Text("State*")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardColor.text)

            Menu {
                ForEach(OnboardFlow.states, id: \.self) { state in
                    Button(state) { flow.selectedState = state }
                }
            } label: {
                HStack {
                    Text(flow.selectedState.isEmpty ? "select" : flow.selectedState)
                        .font(.system(size: 15))
                        .foregroundStyle(
                            flow.selectedState.isEmpty ? OnboardColor.subtle : OnboardColor.text
                        )
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(
                            flow.selectedState.isEmpty ? OnboardColor.subtle : OnboardColor.text
                        )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white, in: .rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            flow.stateError != nil ? OnboardColor.danger : OnboardColor.border,
                            lineWidth: 1
                        )
                }
            }

            if let error = flow.stateError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(OnboardColor.danger)
            }
        }
    }

    private func advance() {
        guard flow.step2Valid else {
            flow.submitAttempted = true
            return
        }
        flow.submitAttempted = false
        onNext()
    }
}

/// `/onboard/step3` — PAN + GST, then submit.
struct OnboardStep3View: View {
    @Environment(OnboardFlow.self) private var flow
    @Environment(SessionStore.self) private var session
    let onSubmitted: () -> Void

    var body: some View {
        @Bindable var flow = flow

        OnboardLayout(
            step: 3,
            heading: "Almost there one last step",
            subheading: "Upload your PAN and GST certificate so we can verify your business. This is a one-time process."
        ) {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack(alignment: .top, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        ImageUploadBox(
                            label: "PAN Card*",
                            file: $flow.panFile,
                            error: flow.panError,
                            allowsPDF: true
                        )
                        OnboardLegalNote()
                    }
                    ImageUploadBox(
                        label: "GST Certificate*",
                        file: $flow.gstFile,
                        error: flow.gstError,
                        allowsPDF: true
                    )
                }

                if let error = flow.submitError {
                    Text(error)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: 0xDC2626))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(hex: 0xFEF2F2), in: .rect(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(hex: 0xFECACA), lineWidth: 1)
                        }
                }

                OnboardPrimaryButton(
                    title: "Submit",
                    busyTitle: "Submitting...",
                    isBusy: flow.isSubmitting,
                    isEnabled: flow.step3Valid
                ) {
                    submit()
                }
            }
            .motion(Motion.fadeInUp)
        }
    }

    private func submit() {
        guard flow.step3Valid else {
            flow.submitAttempted = true
            return
        }
        guard let user = session.user else { return }
        Task {
            if await flow.submit(user: user) {
                onSubmitted()
            }
        }
    }
}
