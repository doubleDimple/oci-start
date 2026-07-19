import Foundation

struct AiChatModelOption: Identifiable, Equatable, Hashable {
    var id: String
    var displayName: String
    var version: String

    var title: String {
        let v = version.isEmpty ? "latest" : version
        return "\(displayName) (\(v))"
    }
}

struct AiChatMessage: Identifiable, Equatable {
    var id: UUID = UUID()
    var role: Role
    var text: String
    var createdAt: Date = Date()
    var isStreaming: Bool = false

    enum Role: String, Equatable {
        case user
        case assistant
        case system
    }
}

struct AiChatTenantOption: Identifiable, Equatable, Hashable {
    var id: Int64
    var name: String
    var region: String
    var supportAI: Bool
}
