import Foundation
import Combine

/// Coordinates in-window top-nav dropdowns (language / user).
/// Avoids SwiftUI `.popover` which escapes the app window and can glitch when two are adjacent.
enum TopNavDropdown: Equatable {
    case none
    case search
    case appearance
    case language
    case user
}

final class TopNavChromeState: ObservableObject {
    static let shared = TopNavChromeState()

    @Published var open: TopNavDropdown = .none
    @Published var searchActiveIndex = 0
    @Published var searchFocusRequest = 0
    @Published var searchBlurRequest = 0

    func focusSearch() { searchFocusRequest += 1 }
    func blurSearch() { searchBlurRequest += 1 }

    func moveSearchSelection(_ step: Int, count: Int) {
        open = .search
        guard count > 0 else { searchActiveIndex = 0; return }
        searchActiveIndex = (searchActiveIndex + step + count) % count
    }

    func toggle(_ which: TopNavDropdown) {
        open = (open == which) ? .none : which
    }

    func close() {
        open = .none
    }
}
