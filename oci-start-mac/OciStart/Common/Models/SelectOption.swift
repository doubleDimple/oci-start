import Foundation

struct SelectOption: Identifiable, Hashable {
    let id: String
    let title: String
    var subtitle: String? = nil
    var enabled: Bool = true

    init(id: String, title: String, subtitle: String? = nil, enabled: Bool = true) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.enabled = enabled
    }

    /// Convenience for Int ids (tenant id, etc.)
    init(id: Int64, title: String, subtitle: String? = nil) {
        self.init(id: String(id), title: title, subtitle: subtitle)
    }

    init(id: Int, title: String, subtitle: String? = nil) {
        self.init(id: String(id), title: title, subtitle: subtitle)
    }
}
