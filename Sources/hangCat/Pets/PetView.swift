import SwiftUI

struct PetView: View {
    @ObservedObject var viewModel: PetViewModel

    var body: some View {
        Image(nsImage: currentImage)
            .resizable()
            .interpolation(.none)
            .aspectRatio(contentMode: .fit)
    }

    private var currentImage: NSImage {
        switch viewModel.pose {
        case .idle:     return CatImage.draping
        case .dragging: return CatImage.full
        }
    }
}
