import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {

    // MARK: - Auth
    @Published var isAuthenticated = false

    // MARK: - Instances
    @Published var instances: [OciInstance] = []
    @Published var instancesLoading = false

    // MARK: - Dashboard
    @Published var dashboardStats: DashboardStats?

    // MARK: - Tenants
    @Published var tenants: [Tenant] = []
    @Published var allTenants: [Tenant] = []   // for dropdowns
    @Published var tenantsLoading = false

    // MARK: - Object Storage
    @Published var buckets: [StorageBucket] = []
    @Published var storageObjects: [StorageObject] = []
    @Published var storageLoading = false

    // MARK: - Memos
    @Published var memos: [Memo] = []

    // MARK: - API Token
    @Published var apiTokenStatus: ApiTokenStatus?

    // MARK: - VPS Monitor (reuses instances list)
    @Published var vpsLoading = false

    // MARK: - Global UI
    @Published var errorMessage: String?
    @Published var toastMessage: String?
    @Published var isLoading = false

    var serverURL: String {
        get { UserDefaults.standard.string(forKey: "serverURL") ?? "http://localhost:9856" }
        set { UserDefaults.standard.set(newValue, forKey: "serverURL"); objectWillChange.send() }
    }

    private(set) var network: NetworkService
    private let auth: AuthService
    private var toastTask: Task<Void, Never>?

    init() {
        let net = NetworkService()
        self.network = net
        self.auth = AuthService(network: net)
        // Session check is now triggered by ContentView after backend is ready
    }

    // MARK: - Auth

    func checkSessionPublic() async {
        await checkSession()
    }

    private func checkSession() async {
        guard let _ = try? await network.getInstances(baseURL: serverURL, page: 0, size: 1) else { return }
        isAuthenticated = true
        await loadInitialData()
    }

    func login(username: String, password: String,
               verificationCode: String? = nil, mfaCode: String? = nil) async throws {
        try await auth.login(baseURL: serverURL, username: username, password: password,
                             verificationCode: verificationCode, mfaCode: mfaCode)
        isAuthenticated = true
        await loadInitialData()
    }

    func logout() async {
        try? await network.performLogout(baseURL: serverURL)
        isAuthenticated = false
        instances = []; tenants = []; memos = []; dashboardStats = nil
    }

    private func loadInitialData() async {
        async let a: () = loadInstances()
        async let b: () = loadTenants()
        async let c: () = loadDashboard()
        _ = await (a, b, c)
    }

    // MARK: - Dashboard

    func loadDashboard() async {
        dashboardStats = try? await network.getDashboardStats(baseURL: serverURL)
    }

    // MARK: - Instances

    func loadInstances() async {
        instancesLoading = true
        defer { instancesLoading = false }
        do {
            let resp = try await network.getInstances(baseURL: serverURL)
            instances = resp.content ?? []
        } catch NetworkError.unauthorized { isAuthenticated = false }
        catch { errorMessage = error.localizedDescription }
    }

    func startInstance(_ instanceId: String) async {
        do {
            let r = try await network.startInstance(baseURL: serverURL, instanceId: instanceId)
            showToast(r.message ?? "启动请求已发送")
            await loadInstances()
        } catch { errorMessage = error.localizedDescription }
    }

    func stopInstance(_ instanceId: String) async {
        do {
            let r = try await network.stopInstance(baseURL: serverURL, instanceId: instanceId)
            showToast(r.message ?? "停止请求已发送")
            await loadInstances()
        } catch { errorMessage = error.localizedDescription }
    }

    func terminateInstance(_ instanceId: String) async {
        do {
            let r = try await network.terminateInstance(baseURL: serverURL, instanceId: instanceId)
            showToast(r.message ?? "终止请求已发送")
            await loadInstances()
        } catch { errorMessage = error.localizedDescription }
    }

    func changeIP(_ instanceDetailId: String) async {
        do {
            let r = try await network.changeIP(baseURL: serverURL, instanceDetailId: instanceDetailId)
            showToast(r.message ?? "换IP请求已发送")
            await loadInstances()
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Tenants

    func loadTenants(page: Int = 0, keyword: String? = nil) async {
        tenantsLoading = true
        defer { tenantsLoading = false }
        do {
            let resp = try await network.getTenants(baseURL: serverURL, page: page, keyword: keyword)
            tenants = resp.content ?? []
        } catch { errorMessage = error.localizedDescription }
    }

    func loadAllTenants() async {
        allTenants = (try? await network.getAllTenants(baseURL: serverURL)) ?? []
    }

    func deleteTenant(_ id: Int64) async {
        do {
            let r = try await network.deleteTenant(baseURL: serverURL, tenantId: id)
            showToast(r.message ?? "已删除")
            await loadTenants()
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Object Storage

    func loadBuckets(tenantId: Int64) async {
        storageLoading = true
        defer { storageLoading = false }
        buckets = []
        storageObjects = []
        do {
            let resp = try await network.getBuckets(baseURL: serverURL, tenantId: tenantId)
            buckets = resp.items ?? []
        } catch { errorMessage = error.localizedDescription }
    }

    func loadObjects(tenantId: Int64, namespace: String, bucketName: String) async {
        storageLoading = true
        defer { storageLoading = false }
        do {
            let resp = try await network.getObjects(baseURL: serverURL, tenantId: tenantId, namespace: namespace, bucketName: bucketName)
            storageObjects = resp.items ?? []
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteObject(tenantId: Int64, namespace: String, bucketName: String, objectName: String) async {
        do {
            let r = try await network.deleteObject(baseURL: serverURL, tenantId: tenantId, namespace: namespace, bucketName: bucketName, objectName: objectName)
            showToast(r.message ?? "已删除")
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Memos

    func loadMemos() async {
        memos = (try? await network.getMemos(baseURL: serverURL)) ?? []
    }

    func createMemo(title: String, content: String) async -> Memo? {
        do {
            let m = try await network.createMemo(baseURL: serverURL, title: title, content: content)
            memos.insert(m, at: 0)
            return m
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateMemo(id: Int64, title: String, content: String) async {
        do {
            let m = try await network.updateMemo(baseURL: serverURL, id: id, title: title, content: content)
            if let idx = memos.firstIndex(where: { $0.id == id }) { memos[idx] = m }
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteMemo(id: Int64) async {
        do {
            try await network.deleteMemo(baseURL: serverURL, id: id)
            memos.removeAll { $0.id == id }
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - API Token

    func loadApiTokenStatus() async {
        apiTokenStatus = try? await network.getApiTokenStatus(baseURL: serverURL)
    }

    func generateApiToken() async {
        do {
            apiTokenStatus = try await network.generateApiToken(baseURL: serverURL)
            showToast("Token 已生成")
        } catch { errorMessage = error.localizedDescription }
    }

    func revokeApiToken() async {
        do {
            _ = try await network.revokeApiToken(baseURL: serverURL)
            apiTokenStatus = nil
            showToast("Token 已撤销")
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Helpers

    func showToast(_ msg: String) {
        toastTask?.cancel()
        toastMessage = msg
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { toastMessage = nil }
        }
    }
}
