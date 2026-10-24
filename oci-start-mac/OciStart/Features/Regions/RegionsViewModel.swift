import Foundation
import Combine

@MainActor
final class RegionsViewModel: ObservableObject {
    @Published private(set) var openRecords: [OpenRegionNotify] = []
    @Published private(set) var myRecords: [OpenRegionNotify] = []
    @Published private(set) var regionMap: [String: String] = [:]
    @Published private(set) var allRows: [RegionRow] = []
    @Published private(set) var filteredRows: [RegionRow] = []
    @Published private(set) var pageRows: [RegionRow] = []
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var armError: String?
    @Published private(set) var mineError: String?
    @Published private(set) var armLoaded = false
    @Published private(set) var mineLoaded = false
    @Published var searchText = "" { didSet { refilter(reset: true) } }
    @Published var continent: RegionContinent = .all { didSet { refilter(reset: true) } }
    @Published var statusFilter: RegionStatusFilter = .all { didSet { refilter(reset: true) } }
    @Published var showMapBoard = true
    @Published var showArm = true
    @Published var showMine = true
    @Published var onlyShared = false
    @Published var showLabels = true
    @Published var showPulse = true
    @Published var showLinks = true
    @Published var zoom: Double = 1
    @Published var selectedRegion: String?
    @Published var pageState = PageState(page: 0, size: 10)
    private let session: AppSession
    private var timer: Timer?
    private var generation = 0

    var totalRegions: Int { Set(allRows.map(\.regionCode)).count }
    var openArmCount: Int { Set(allRows.filter(\.isOpen).map(\.regionCode)).count }
    var mineCount: Int { Set(myRecords.map(\.region)).count }
    var sharedCount: Int { Set(allRows.filter { $0.isOpen && $0.isMine }.map(\.regionCode)).count }
    var lastUpdateText: String {
        guard let lastUpdate = lastUpdate else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: UserDefaults.standard.string(forKey: "appLocale") ?? "zh_CN")
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: lastUpdate)
    }
    var mapRows: [RegionRow] {
        var rows: [String: RegionRow] = [:]
        for row in allRows where row.coordinate != nil && ((showArm && row.isOpen) || (showMine && row.isMine)) {
            guard !onlyShared || (row.isOpen && row.isMine) else { continue }
            if let current = rows[row.regionCode], current.isOpen || !row.isOpen { continue }
            rows[row.regionCode] = row
        }
        return rows.values.sorted { $0.regionCode < $1.regionCode }
    }
    var unknownCoordinates: Int {
        Set(allRows.filter { $0.coordinate == nil && ((showArm && $0.isOpen) || (showMine && $0.isMine)) }.map(\.regionCode)).count
    }
    var selectedRow: RegionRow? {
        allRows.first { $0.regionCode == selectedRegion && $0.isOpen } ?? allRows.first { $0.regionCode == selectedRegion }
    }
    var todayNewCount: Int {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        return Set(allRows.filter { row in
            guard row.isOpen, let value = row.openTime, let date = Self.parseDate(value) else { return false }
            return date >= start && date < end
        }.map(\.regionCode)).count
    }
    init(session: AppSession = .shared) { self.session = session }

    func start() {
        guard timer == nil else { return }
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in await self.refresh() }
        }
    }
    func stop() {
        generation += 1
        timer?.invalidate()
        timer = nil
        isLoading = false
    }
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        generation += 1
        let current = generation
        defer { if generation == current { isLoading = false } }
        async let arm: Result<ArmDataPayload, Error> = fetch(path: "/resource/arm-data")
        async let mine: Result<MyRegionsPayload, Error> = fetch(path: "/resource/my-regions")
        let responses = await (arm, mine)
        guard current == generation else { return }
        var complete = true
        switch responses.0 {
        case .success(let data):
            openRecords = data.armRecords.filter { !$0.region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            regionMap = data.regionMap
            armLoaded = true
            armError = nil
        case .failure(let error):
            armError = error.localizedDescription
            complete = false
        }
        switch responses.1 {
        case .success(let data):
            myRecords = data.hasRecords.filter { !$0.region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            mineLoaded = true
            mineError = nil
        case .failure(let error):
            mineError = error.localizedDescription
            complete = false
        }
        rebuildRows()
        // A partial refresh preserves the last successful timestamp and each endpoint's history.
        if complete { lastUpdate = Date() }
    }
    func goPage(_ action: (inout PageState) -> Void) { action(&pageState); applyPage() }
    func select(_ row: RegionRow, locateTable: Bool = false) {
        selectedRegion = row.regionCode
        showMapBoard = true
        if row.isOpen { showArm = true }
        if row.isMine { showMine = true }
        if !row.isOpen || !row.isMine { onlyShared = false }
        if locateTable {
            searchText = ""
            continent = .all
            statusFilter = .all
            if let index = filteredRows.firstIndex(where: { $0.regionCode == row.regionCode }) {
                pageState.page = index / pageState.size
                applyPage()
            }
        }
    }
    func localeChanged() { refilter(reset: false) }

    private func fetch<T: Decodable>(path: String) async -> Result<T, Error> {
        do {
            let url = try APIClient.shared.makeURL(session.serverURL, path: path)
            let raw = try await APIClient.shared.getJSON(url, headers: ["Cache-Control": "no-cache, no-store"])
            let envelope = try JSONDecoder().decode(APIEnvelope<T>.self, from: raw)
            guard envelope.success, let data = envelope.data else {
                throw APIError.serverMessage(envelope.message ?? regionText("请求失败", "Request failed"))
            }
            return .success(data)
        } catch { return .failure(error) }
    }
    private func rebuildRows() {
        let owned = Set(myRecords.map(\.region))
        let names = regionMap
        func row(code: String, id: String, record: OpenRegionNotify?) -> RegionRow {
            RegionRow(id: id, regionCode: code, name: names[code] ?? KnownRegions.cityName(code),
                      isOpen: (record?.openCount ?? 0) > 0, isMine: owned.contains(code),
                      architectureType: record?.architectureType.isEmpty == false ? record!.architectureType : "—",
                      openTime: record?.openTime, openCount: record?.openCount ?? 0,
                      monthlyOpenCount: record?.monthlyOpenCount ?? 0, lastNotifyTime: record?.lastNotifyTime,
                      continent: RegionContinent.of(regionCode: code))
        }
        // Preserve every backend record. Repeated code/architecture records need separate SwiftUI identities.
        var occurrences: [String: Int] = [:]
        var recorded: [RegionRow] = []
        for record in openRecords {
            let key = "\(record.region):\(record.architectureType)"
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            recorded.append(row(code: record.region, id: "record-\(key):\(occurrence)", record: record))
        }
        let added = Set(recorded.map(\.regionCode))
        let remaining = Set(KnownRegions.codes).union(owned).subtracting(added).sorted()
        allRows = recorded + remaining.map { row(code: $0, id: "region-\($0)", record: nil) }
        refilter(reset: false)
    }
    private func refilter(reset: Bool) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredRows = allRows.filter { row in
            let matchesSearch = query.isEmpty || row.regionCode.localizedCaseInsensitiveContains(query) || row.displayName.localizedCaseInsensitiveContains(query)
            let matchesContinent = continent == .all || row.continent == continent.rawValue
            let matchesStatus = statusFilter == .all || (statusFilter == .open ? row.isOpen : !row.isOpen)
            return matchesSearch && matchesContinent && matchesStatus
        }
        if reset { pageState.page = 0 }
        applyPage()
    }
    private func applyPage() {
        pageState.apply(totalElements: Int64(filteredRows.count))
        pageRows = Array(filteredRows.dropFirst(pageState.page * pageState.size).prefix(pageState.size))
    }
    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
