import Foundation
import Combine

/// Coordinates in-window top-nav dropdowns (language / user).
/// Avoids SwiftUI `.popover` which escapes the app window and can glitch when two are adjacent.
enum TopNavDropdown: Equatable {
    case none
    case language
    case user
}

final class TopNavChromeState: ObservableObject {
    static let shared = TopNavChromeState()

    @Published var open: TopNavDropdown = .none

    func toggle(_ which: TopNavDropdown) {
        open = (open == which) ? .none : which
    }

    func close() {
        open = .none
    }
}
