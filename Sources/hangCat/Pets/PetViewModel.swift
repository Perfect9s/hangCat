import Combine
import SwiftUI

enum PetPose {
    /// Cat draped over a window edge.
    case idle
    /// Cat being dragged by the user — full-body pose.
    case dragging
}

final class PetViewModel: ObservableObject {
    @Published var pose: PetPose = .idle
}
