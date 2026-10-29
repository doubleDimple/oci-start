import Foundation
import Combine

@MainActor
final class RegionsViewModel: ObservableObject {
    @Published private(set) var myRecords: [OwnedRegion] = []
    @Published private(set) var regionMap: [String: String] = [:]
    @Published private(set) var allRows: [RegionRow] = []
    @Published private(set) var filteredRows: [RegionRow] = []
    @Published private(set) var pageRows: [RegionRow] = []
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var mineError: String?
    @Published private(set) var mineLoaded = false
    @Published var searchText = "" { didSet { refilter(reset: true) } }
    @Published var continent: RegionContinent = .all { didSet { refilter(reset: true) } }
    @Published var statusFilter: RegionStatusFilter = .all { didSet { refilter(reset: true) } }
    @Published var showMapBoard = true
    @Published var showMine = true
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
    var mineCount: Int { Set(myRecords.map(\.region)).count }
    var lastUpdateText: String {
        guard let lastUpdate = lastUpdate else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: UserDefaults.standard.string(forKey: "appLocale") ?? "zh_CN")
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: lastUpdate)
    }
    var mapRows: [RegionRow] { allRows.filter { $0.coordinate != nil && $0.isMine && showMine } }
    var unknownCoordinates: Int { allRows.filter { $0.coordinate == nil && $0.isMine }.count }
    var selectedRow: RegionRow? { allRows.first { $0.regionCode == selectedRegion } }
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
        let result: Result<MyRegionsPayload, Error> = await fetch(path: "/resource/my-regions")
        guard current == generation else { return }
        switch result {
        case .success(let data):
            myRecords = data.hasRecords.filter { !$0.region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            regionMap = data.regionMap ?? [:]
            mineLoaded = true
            mineError = nil
            rebuildRows()
            lastUpdate = Date()
        case .failure(let error):
            mineError = error.localizedDescription
        }
    }
    func goPage(_ action: (inout PageState) -> Void) { action(&pageState); applyPage() }
    func select(_ row: RegionRow, locateTable: Bool = false) {
        selectedRegion = row.regionCode
        showMapBoard = true
        if row.isMine { showMine = true }
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
        allRows = Set(KnownRegions.codes).union(owned).union(names.keys).sorted().map { code in
            RegionRow(id: code, regionCode: code, name: names[code] ?? KnownRegions.cityName(code),
                      isMine: owned.contains(code), continent: RegionContinent.of(regionCode: code))
        }
        if let selected = selectedRegion, !owned.contains(selected) { selectedRegion = nil }
        refilter(reset: false)
    }
    private func refilter(reset: Bool) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredRows = allRows.filter { row in
            let matchesSearch = query.isEmpty || row.regionCode.localizedCaseInsensitiveContains(query) || row.displayName.localizedCaseInsensitiveContains(query)
            let matchesContinent = continent == .all || row.continent == continent.rawValue
            let matchesStatus = statusFilter == .all || (statusFilter == .linked ? row.isMine : !row.isMine)
            return matchesSearch && matchesContinent && matchesStatus
        }
        if reset { pageState.page = 0 }
        applyPage()
    }
    private func applyPage() {
        pageState.apply(totalElements: Int64(filteredRows.count))
        pageRows = Array(filteredRows.dropFirst(pageState.page * pageState.size).prefix(pageState.size))
    }
}
