import Foundation

/// Server-aligned pagination (0-based page index).
struct PageState: Equatable {
    var page: Int = 0
    var size: Int = 20
    var totalElements: Int64 = 0
    var totalPages: Int = 0

    static let sizeOptions: [Int] = [10, 20, 30, 50]

    var isFirst: Bool { page <= 0 }
    var isLast: Bool { totalPages <= 0 || page >= totalPages - 1 }
    var displayPage: Int { page + 1 } // 1-based for UI

    var rangeText: String {
        guard totalElements > 0 else { return "共 0 条" }
        let start = page * size + 1
        let end = min(Int64(page * size + size), totalElements)
        return "第 \(start)–\(end) 条 / 共 \(totalElements) 条"
    }

    mutating func apply(totalElements: Int64, totalPages: Int? = nil) {
        self.totalElements = totalElements
        if let totalPages = totalPages {
            self.totalPages = max(totalPages, 0)
        } else if size > 0 {
            self.totalPages = Int((totalElements + Int64(size) - 1) / Int64(size))
        } else {
            self.totalPages = 0
        }
        if self.totalPages > 0, page >= self.totalPages {
            page = self.totalPages - 1
        }
    }

    mutating func goFirst() { page = 0 }
    mutating func goPrev() { if !isFirst { page -= 1 } }
    mutating func goNext() { if !isLast { page += 1 } }
    mutating func goLast() { if totalPages > 0 { page = totalPages - 1 } }
    mutating func go(to newPage: Int) {
        guard totalPages > 0 else { page = 0; return }
        page = min(max(0, newPage), totalPages - 1)
    }
    mutating func changeSize(_ newSize: Int) {
        size = newSize
        page = 0
    }
}
