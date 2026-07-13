import Foundation

// MARK: - OpenRegionNotify (web /resource/arm-data)

struct OpenRegionNotify: Decodable, Equatable, Identifiable {
    var id: String { region }
    var region: String = ""
    var architectureType: String = ""
    var openTime: String?
    var openCount: Int = 0
    var lastNotifyTime: String?
    var monthlyOpenCount: Int = 0

    enum CodingKeys: String, CodingKey {
        case region
        case architectureType, architecture_type
        case openTime, open_time
        case openCount, open_count
        case lastNotifyTime, last_notify_time
        case monthlyOpenCount, monthly_open_count
        case id
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        region = (try? c.decode(String.self, forKey: .region)) ?? ""
        architectureType =
            (try? c.decode(String.self, forKey: .architectureType))
            ?? (try? c.decode(String.self, forKey: .architecture_type))
            ?? ""
        openTime = Self.decodeTime(c, .openTime) ?? Self.decodeTime(c, .open_time)
        lastNotifyTime = Self.decodeTime(c, .lastNotifyTime) ?? Self.decodeTime(c, .last_notify_time)
        openCount = Self.decodeInt(c, .openCount) ?? Self.decodeInt(c, .open_count) ?? 0
        monthlyOpenCount = Self.decodeInt(c, .monthlyOpenCount) ?? Self.decodeInt(c, .monthly_open_count) ?? 0
        _ = try? c.decodeIfPresent(Int64.self, forKey: .id)
    }

    private static func decodeInt(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> Int? {
        if let v = try? c.decode(Int.self, forKey: k) { return v }
        if let v = try? c.decode(Int64.self, forKey: k) { return Int(v) }
        if let v = try? c.decode(Double.self, forKey: k) { return Int(v) }
        return nil
    }

    private static func decodeTime(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> String? {
        if let s = try? c.decode(String.self, forKey: k) { return s }
        if let arr = try? c.decode([Int].self, forKey: k), arr.count >= 6 {
            return String(format: "%04d-%02d-%02d %02d:%02d:%02d",
                          arr[0], arr[1], arr[2], arr[3], arr[4], arr[5])
        }
        return nil
    }
}

struct ArmDataPayload: Decodable {
    var armRecords: [OpenRegionNotify] = []
    var regionMap: [String: String] = [:]
}

struct MyRegionsPayload: Decodable {
    var hasRecords: [OpenRegionNotify] = []
}

// MARK: - Row model for table

struct RegionRow: Identifiable, Equatable {
    var id: String { regionCode }
    let regionCode: String
    let name: String
    let isOpen: Bool
    let architectureType: String
    let openTime: String?
    let openCount: Int
    let monthlyOpenCount: Int
    let lastNotifyTime: String?
    let continent: String
}

enum RegionContinent: String, CaseIterable, Identifiable {
    case all = "all"
    case asia = "asia"
    case europe = "europe"
    case americaNorth = "america-north"
    case americaSouth = "america-south"
    case middleEast = "middle-east"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部大洲"
        case .asia: return "亚太地区"
        case .europe: return "欧洲"
        case .americaNorth: return "北美"
        case .americaSouth: return "南美"
        case .middleEast: return "中东/非洲"
        }
    }

    static func of(regionCode: String) -> String {
        let prefixes: [(String, String)] = [
            ("ap-", "asia"),
            ("eu-", "europe"),
            ("uk-", "europe"),
            ("il-", "europe"),
            ("me-", "middle-east"),
            ("af-", "middle-east"),
            ("us-", "america-north"),
            ("ca-", "america-north"),
            ("mx-", "america-north"),
            ("sa-", "america-south")
        ]
        for (p, c) in prefixes where regionCode.hasPrefix(p) { return c }
        return "other"
    }
}

enum RegionStatusFilter: String, CaseIterable, Identifiable {
    case all, open, closed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "全部状态"
        case .open: return "已开机"
        case .closed: return "未放货"
        }
    }
}

enum RegionsMapViewMode: String {
    case arm   // ARM 放货区域
    case mine  // 我的区域
}

// MARK: - Known region codes (web arm_records.js REGION_COORDINATES keys)

enum KnownRegions {
    static let codes: [String] = [
        "af-johannesburg-1", "af-casablanca-1",
        "ap-chuncheon-1", "ap-hyderabad-1", "ap-melbourne-1", "ap-mumbai-1",
        "ap-osaka-1", "ap-seoul-1", "ap-kulai-2", "ap-singapore-1", "ap-singapore-2",
        "ap-sydney-1", "ap-tokyo-1", "ap-batam-1",
        "ca-montreal-1", "ca-toronto-1",
        "eu-amsterdam-1", "eu-frankfurt-1", "eu-jovanovac-1", "eu-madrid-1", "eu-madrid-3",
        "eu-marseille-1", "eu-milan-1", "eu-turin-1", "eu-paris-1", "eu-stockholm-1", "eu-zurich-1",
        "il-jerusalem-1",
        "me-abudhabi-1", "me-dubai-1", "me-jeddah-1",
        "mx-monterrey-1", "mx-queretaro-1",
        "sa-bogota-1", "sa-santiago-1", "sa-saopaulo-1", "sa-vinhedo-1", "sa-valparaiso-1",
        "uk-cardiff-1", "uk-london-1",
        "us-ashburn-1", "us-chicago-1", "us-phoenix-1", "us-sanjose-1"
    ]
}
