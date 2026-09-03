import SwiftUI

struct ChamakFlowCoordinator: View {
    let wholesalerID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ChamakViewModel

    init(wholesalerID: UUID, mode: ChamakMode = .fusion) {
        self.wholesalerID = wholesalerID
        let viewModel = ChamakViewModel()
        viewModel.mode = mode
        _vm = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch vm.step {
                case .catalogPicker:
                    ChamakCatalogPickerView(vm: vm, wholesalerID: wholesalerID)
                case .analyzing, .generating:
                    ChamakGeneratingView(vm: vm)
                case .sliderForm:
                    ChamakSliderFormView(vm: vm, wholesalerID: wholesalerID)
                case .setStyling:
                    ChamakSetStylingView(vm: vm, wholesalerID: wholesalerID)
                case .result, .failed:
                    ChamakResultView(vm: vm, wholesalerID: wholesalerID)
                case .gallery:
                    ChamakGalleryView(vm: vm, wholesalerID: wholesalerID)
                }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Exit") {
                        dismiss()
                    }
                    .font(.manrope(13, weight: .semibold))
                    .foregroundStyle(Palette.dark)
                }
            }
            .overlay(alignment: .top) {
                if vm.showToast, let msg = vm.toastMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xBB8651))

                        Text(msg)
                            .font(.manrope(13, weight: .bold))
                            .foregroundStyle(Palette.dark)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white, in: Capsule())
                    .overlay {
                        Capsule().stroke(Palette.border, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            withAnimation {
                                vm.showToast = false
                            }
                        }
                    }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: vm.showToast)
        }
        .task {
            await vm.load(wholesalerID: wholesalerID)
        }
    }
}
