import SwiftUI

struct ChamakFlowCoordinator: View {
    let wholesalerID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var vm = ChamakViewModel()

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
        }
        .task {
            await vm.load(wholesalerID: wholesalerID)
        }
    }
}
