import Foundation
import Combine

/// ViewModel for Web `/system/ipSettings`.
@MainActor
final class IpQualityViewModel: ObservableObject {

    @Published var ipCheckEnabled = false
    @Published var checkInterval = 1
    @Published var telecom = VPSConfigDTO(type: "telecom")
    @Published var unicom = VPSConfigDTO(type: "unicom")
    @Published var mobile = VPSConfigDTO(type: "mobile")

    @Published private(set) var isLoading = false
    @Published private(set) var savingKey: String?
    @Published private(set) var errorText: String?

    private let session: AppSession
    private var service: IpQualityService { IpQualityService(baseURL: session.serverURL) }

    var intervalOptions: [SelectOption] {
        (1...24).map { SelectOption(id: "\($0)", title: "\($0) 小时") }
    }

    init(session: AppSession = .shared) {
        self.session = session
    }

    func start() {
        Task { await reload() }
    }

    func reload() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let cfg = try await service.fetchConfigs()
            ipCheckEnabled = cfg.ipCheck.enabled
            checkInterval = max(1, min(24, cfg.ipCheck.checkInterval))
            telecom = cfg.telecom
            unicom = cfg.unicom
            mobile = cfg.mobile
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func saveIpCheck() {
        Task { await performSaveIpCheck() }
    }

    private func performSaveIpCheck() async {
        savingKey = "ipCheck"
        defer { savingKey = nil }
        do {
            try await LoadingHUD.shared.during {
                try await service.updateIpCheck(enabled: ipCheckEnabled, checkInterval: checkInterval)
            }
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func binding(for carrier: IpCarrier) -> VPSConfigDTO {
        switch carrier {
        case .telecom: return telecom
        case .unicom: return unicom
        case .mobile: return mobile
        }
    }

    func update(_ carrier: IpCarrier, _ value: VPSConfigDTO) {
        var v = value
        v.type = carrier.rawValue
        switch carrier {
        case .telecom: telecom = v
        case .unicom: unicom = v
        case .mobile: mobile = v
        }
    }

    func saveVPS(_ carrier: IpCarrier) {
        Task { await performSaveVPS(carrier) }
    }

    private func performSaveVPS(_ carrier: IpCarrier) async {
        var cfg = binding(for: carrier)
        if cfg.enabled {
            let ip = cfg.serverIp.trimmingCharacters(in: .whitespacesAndNewlines)
            let user = cfg.username.trimmingCharacters(in: .whitespacesAndNewlines)
            if ip.isEmpty || user.isEmpty || cfg.password.isEmpty {
                ToastCenter.shared.error("启用时请填写服务器地址、用户名与密码")
                return
            }
        }
        guard (1...65535).contains(cfg.sshPort) else {
            ToastCenter.shared.error("SSH 端口范围应为 1–65535")
            return
        }
        cfg.serverIp = cfg.serverIp.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.username = cfg.username.trimmingCharacters(in: .whitespacesAndNewlines)
        update(carrier, cfg)
        savingKey = carrier.rawValue
        defer { savingKey = nil }
        do {
            try await LoadingHUD.shared.during {
                try await service.saveVPS(cfg)
            }
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func testVPS(_ carrier: IpCarrier) {
        Task { await performTestVPS(carrier) }
    }

    private func performTestVPS(_ carrier: IpCarrier) async {
        let cfg = binding(for: carrier)
        let ip = cfg.serverIp.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = cfg.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if ip.isEmpty || user.isEmpty || cfg.password.isEmpty {
            ToastCenter.shared.error("请填写服务器地址、用户名与密码后再测试")
            return
        }
        guard (1...65535).contains(cfg.sshPort) else {
            ToastCenter.shared.error("SSH 端口范围应为 1–65535")
            return
        }
        savingKey = "test-\(carrier.rawValue)"
        defer { savingKey = nil }
        do {
            let msg = try await LoadingHUD.shared.during {
                try await service.testConnection(cfg)
            }
            AppAlert.info(title: "连接测试", message: msg)
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
