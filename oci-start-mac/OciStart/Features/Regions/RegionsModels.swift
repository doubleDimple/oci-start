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
    let id: String
    let regionCode: String
    let name: String
    let isOpen: Bool
    let isMine: Bool
    let architectureType: String
    let openTime: String?
    let openCount: Int
    let monthlyOpenCount: Int
    let lastNotifyTime: String?
    let continent: String
    var coordinate: RegionCoordinate? { KnownRegions.coordinates[regionCode] }
    var displayName: String {
        regionText(name, KnownRegions.englishName(regionCode))
    }
}

enum RegionContinent: String, CaseIterable, Identifiable {
    case all, asia, europe
    case americaNorth = "america-north"
    case americaSouth = "america-south"
    case middleEast = "middle-east"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return regionText("全部大洲", "All continents")
        case .asia: return regionText("亚太地区", "Asia Pacific")
        case .europe: return regionText("欧洲", "Europe")
        case .americaNorth: return regionText("北美", "North America")
        case .americaSouth: return regionText("南美", "South America")
        case .middleEast: return regionText("中东 / 非洲", "Middle East / Africa")
        }
    }
    static func of(regionCode: String) -> String {
        for (prefix, name) in [("ap-", "asia"), ("eu-", "europe"), ("uk-", "europe"), ("il-", "europe"),
                               ("me-", "middle-east"), ("af-", "middle-east"), ("us-", "america-north"),
                               ("ca-", "america-north"), ("mx-", "america-north"), ("sa-", "america-south")] {
            if regionCode.hasPrefix(prefix) { return name }
        }
        return "other"
    }
}

enum RegionStatusFilter: String, CaseIterable, Identifiable {
    case all, open, closed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return regionText("全部状态", "All statuses")
        case .open: return regionText("有开机记录", "Has launch history")
        case .closed: return regionText("无开机记录", "No launch history")
        }
    }
}

struct RegionCoordinate: Equatable {
    let lat: Double
    let lng: Double
}

func regionText(_ zh: String, _ en: String) -> String {
    (UserDefaults.standard.string(forKey: "appLocale") ?? "").hasPrefix("en") ? en : zh
}

/// Copied from the current Vue regionCoords.ts and dotWorldScene.ts, September 2026.
/// These simplified silhouettes are dot artwork, not political boundaries.
enum KnownRegions {
    static var codes: [String] { coordinates.keys.sorted() }
    static let coordinates: [String: RegionCoordinate] = [
        "af-johannesburg-1": RegionCoordinate(lat: -26.2041, lng: 28.0473),
        "af-casablanca-1": RegionCoordinate(lat: 33.5731, lng: -7.5898),
        "ap-chuncheon-1": RegionCoordinate(lat: 37.8747, lng: 127.7342),
        "ap-hyderabad-1": RegionCoordinate(lat: 17.385, lng: 78.4867),
        "ap-melbourne-1": RegionCoordinate(lat: -37.8136, lng: 144.9631),
        "ap-mumbai-1": RegionCoordinate(lat: 19.076, lng: 72.8777),
        "ap-osaka-1": RegionCoordinate(lat: 34.6937, lng: 135.5023),
        "ap-seoul-1": RegionCoordinate(lat: 37.5665, lng: 126.978),
        "ap-kulai-2": RegionCoordinate(lat: 1.6629, lng: 103.5999),
        "ap-singapore-1": RegionCoordinate(lat: 1.3521, lng: 103.8198),
        "ap-singapore-2": RegionCoordinate(lat: 1.3, lng: 103.75),
        "ap-sydney-1": RegionCoordinate(lat: -33.8688, lng: 151.2093),
        "ap-tokyo-1": RegionCoordinate(lat: 35.6762, lng: 139.6503),
        "ap-batam-1": RegionCoordinate(lat: 1.1074, lng: 104.03),
        "ca-montreal-1": RegionCoordinate(lat: 45.5017, lng: -73.5673),
        "ca-toronto-1": RegionCoordinate(lat: 43.6532, lng: -79.3832),
        "eu-amsterdam-1": RegionCoordinate(lat: 52.3676, lng: 4.9041),
        "eu-frankfurt-1": RegionCoordinate(lat: 50.1109, lng: 8.6821),
        "eu-jovanovac-1": RegionCoordinate(lat: 44.2768, lng: 20.5896),
        "eu-madrid-1": RegionCoordinate(lat: 40.4168, lng: -3.7038),
        "eu-madrid-3": RegionCoordinate(lat: 40.4168, lng: -3.7038),
        "eu-marseille-1": RegionCoordinate(lat: 43.2965, lng: 5.3698),
        "eu-milan-1": RegionCoordinate(lat: 45.4642, lng: 9.19),
        "eu-turin-1": RegionCoordinate(lat: 45.0703, lng: 7.6869),
        "eu-paris-1": RegionCoordinate(lat: 48.8566, lng: 2.3522),
        "eu-stockholm-1": RegionCoordinate(lat: 59.3293, lng: 18.0686),
        "eu-zurich-1": RegionCoordinate(lat: 47.3769, lng: 8.5417),
        "il-jerusalem-1": RegionCoordinate(lat: 31.7683, lng: 35.2137),
        "me-abudhabi-1": RegionCoordinate(lat: 24.4539, lng: 54.3773),
        "me-dubai-1": RegionCoordinate(lat: 25.2048, lng: 55.2708),
        "me-jeddah-1": RegionCoordinate(lat: 21.4858, lng: 39.1925),
        "me-riyadh-1": RegionCoordinate(lat: 24.7136, lng: 46.6753),
        "mx-monterrey-1": RegionCoordinate(lat: 25.6866, lng: -100.3161),
        "mx-queretaro-1": RegionCoordinate(lat: 20.5888, lng: -100.3899),
        "sa-bogota-1": RegionCoordinate(lat: 4.711, lng: -74.0721),
        "sa-santiago-1": RegionCoordinate(lat: -33.4489, lng: -70.6693),
        "sa-saopaulo-1": RegionCoordinate(lat: -23.5505, lng: -46.6333),
        "sa-vinhedo-1": RegionCoordinate(lat: -23.0304, lng: -46.9834),
        "uk-cardiff-1": RegionCoordinate(lat: 51.4816, lng: -3.1791),
        "uk-london-1": RegionCoordinate(lat: 51.5074, lng: -0.1278),
        "us-ashburn-1": RegionCoordinate(lat: 39.0438, lng: -77.4874),
        "us-chicago-1": RegionCoordinate(lat: 41.8781, lng: -87.6298),
        "us-phoenix-1": RegionCoordinate(lat: 33.4484, lng: -112.074),
        "us-sanjose-1": RegionCoordinate(lat: 37.3382, lng: -121.8863),
        "sa-valparaiso-1": RegionCoordinate(lat: -33.0472, lng: -71.6127)
    ]
    private static let cityNames: [String: String] = [
        "johannesburg": "约翰内斯堡",
        "casablanca": "卡萨布兰卡",
        "chuncheon": "春川",
        "hyderabad": "海得拉巴",
        "melbourne": "墨尔本",
        "mumbai": "孟买",
        "osaka": "大阪",
        "seoul": "首尔",
        "kulai": "古来",
        "singapore": "新加坡",
        "sydney": "悉尼",
        "tokyo": "东京",
        "batam": "巴淡",
        "montreal": "蒙特利尔",
        "toronto": "多伦多",
        "amsterdam": "阿姆斯特丹",
        "frankfurt": "法兰克福",
        "jovanovac": "乔万诺瓦茨",
        "madrid": "马德里",
        "marseille": "马赛",
        "milan": "米兰",
        "turin": "都灵",
        "paris": "巴黎",
        "stockholm": "斯德哥尔摩",
        "zurich": "苏黎世",
        "jerusalem": "耶路撒冷",
        "abudhabi": "阿布扎比",
        "dubai": "迪拜",
        "jeddah": "吉达",
        "riyadh": "利雅得",
        "monterrey": "蒙特雷",
        "queretaro": "克雷塔罗",
        "bogota": "波哥大",
        "santiago": "圣地亚哥",
        "saopaulo": "圣保罗",
        "vinhedo": "维涅杜",
        "cardiff": "加的夫",
        "london": "伦敦",
        "ashburn": "阿什本",
        "chicago": "芝加哥",
        "phoenix": "凤凰城",
        "sanjose": "圣何塞",
        "valparaiso": "瓦尔帕莱索"
    ]
    static func englishName(_ code: String) -> String {
        guard coordinates[code] != nil else { return code }
        let city = code.split(separator: "-").dropFirst().dropLast().joined(separator: " ")
        let special = ["abudhabi": "Abu Dhabi", "sanjose": "San Jose", "saopaulo": "São Paulo",
                       "valparaiso": "Valparaíso", "queretaro": "Querétaro"]
        return special[city] ?? city.capitalized
    }
    static func cityName(_ code: String) -> String {
        let city = code.split(separator: "-").dropFirst().dropLast().joined(separator: " ")
        return regionText(cityNames[city] ?? code, englishName(code))
    }
    static let land: [[[Double]]] = [
        [[-168, 65], [-165, 60], [-158, 57], [-152, 58], [-146, 60], [-138, 59], [-131, 53], [-125, 49], [-124, 42], [-120, 34], [-117, 32], [-110, 24], [-105, 20], [-97, 16], [-92, 15], [-88, 16], [-87, 21], [-91, 21], [-95, 19], [-97, 23], [-97, 26], [-94, 29], [-89, 29], [-84, 30], [-81, 25], [-80, 32], [-76, 35], [-70, 42], [-67, 45], [-60, 47], [-56, 51], [-56, 54], [-64, 60], [-78, 62], [-78, 55], [-82, 55], [-86, 66], [-95, 68], [-105, 68], [-115, 70], [-125, 70], [-135, 69], [-145, 70], [-156, 71], [-166, 68]],
        [[-45, 60], [-52, 64], [-53, 68], [-62, 70], [-68, 76], [-62, 82], [-40, 83], [-24, 80], [-20, 73], [-30, 68], [-42, 61]],
        [[-81, -4], [-79, 0], [-77, 8], [-72, 12], [-62, 10], [-60, 8], [-52, 5], [-50, 0], [-44, -2], [-38, -5], [-35, -8], [-39, -13], [-39, -18], [-48, -25], [-53, -34], [-58, -38], [-62, -40], [-65, -45], [-68, -50], [-70, -54], [-75, -52], [-74, -45], [-73, -37], [-71, -30], [-70, -20], [-75, -15], [-81, -6]],
        [[-17, 15], [-16, 20], [-12, 28], [-10, 32], [-5, 36], [10, 37], [20, 32], [28, 31], [33, 28], [35, 23], [38, 18], [43, 12], [51, 12], [51, 5], [42, -1], [40, -10], [35, -20], [32, -26], [27, -34], [20, -35], [18, -30], [13, -20], [9, -1], [3, 6], [-8, 4], [-13, 9]],
        [[-10, 36], [-9, 43], [-2, 48], [3, 51], [6, 53], [9, 54], [11, 58], [16, 60], [22, 60], [30, 60], [28, 66], [21, 70], [32, 71], [46, 68], [62, 70], [76, 73], [92, 75], [106, 77], [116, 74], [132, 72], [146, 70], [160, 70], [170, 66], [179, 65], [172, 60], [162, 58], [155, 52], [142, 48], [135, 43], [130, 35], [122, 32], [120, 25], [110, 20], [105, 10], [100, 6], [97, 16], [90, 22], [82, 17], [77, 8], [72, 20], [66, 25], [57, 25], [50, 30], [45, 37], [36, 36], [30, 41], [26, 38], [22, 40], [16, 38], [13, 45], [8, 44], [3, 42], [-2, 37]],
        [[95, 5], [105, -6], [115, -9], [125, -9], [135, -5], [141, -3], [141, -9], [131, -8], [120, -10], [110, -8], [100, 0]],
        [[113, -22], [114, -35], [118, -35], [129, -32], [137, -35], [141, -38], [147, -39], [151, -37], [153, -28], [145, -15], [142, -11], [136, -12], [130, -11], [125, -14], [118, -20]],
        [[172, -41], [174, -37], [178, -38], [176, -41], [174, -46], [168, -46], [167, -44]],
        [[130, 31], [134, 34], [139, 35], [141, 39], [145, 44], [142, 42], [137, 37], [132, 34]],
        [[-5, 50], [-6, 55], [-3, 58], [-1, 56], [1, 53], [1, 51], [-4, 50]],
        [[43, -12], [50, -15], [50, -25], [45, -25], [43, -17]],
        [[-24, 65], [-22, 66], [-14, 66], [-14, 64], [-22, 63]],
        [[120, 18], [124, 18], [126, 10], [122, 6], [119, 11]],
        [[-85, 22], [-77, 23], [-74, 20], [-80, 21]],
        [[8, 55], [11, 57], [13, 55], [10, 54]]
    ]
}
