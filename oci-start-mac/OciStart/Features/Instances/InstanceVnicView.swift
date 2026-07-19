import SwiftUI
import AppKit

// MARK: - Models

struct VnicItem: Identifiable, Equatable {
    var id: String { vnicId.isEmpty ? attachmentId : vnicId }
    var vnicId: String = ""
    var vnicDisplayName: String = ""
    var privateIp: String = ""
    var publicIp: String = ""
    var subnetId: String = ""
    var attachmentId: String = ""
    var lifecycleState: String = ""
    var ipv6Addresses: [String] = []
    var isPrimary: Bool = false
}

struct VnicStatistics: Equatable {
    var totalVnicCount: Int = 0
    var activeVnicCount: Int = 0
    var secondaryVnicCount: Int = 0
    var totalIpv6Count: Int = 0
}

// MARK: - Service

struct InstanceVnicService {
    let baseURL: String
    private let client = APIClient.shared

    func loadData(ociInstanceId: String) async throws -> (vnics: [VnicItem], stats: VnicStatistics, tenantId: String, primarySubnet: String) {
        let url = try client.makeURL(baseURL, path: "/oci/vnic/loadData", query: ["instanceId": ociInstanceId])
        let raw = try await client.getJSON(url)
        guard let root = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            throw APIError.serverMessage("VNIC 响应无效")
        }
        let ok = (root["success"] as? Bool) ?? false
        if !ok {
            throw APIError.serverMessage(InstanceJSON.string(root["message"]).isEmpty ? "加载失败" : InstanceJSON.string(root["message"]))
        }
        let data = (root["data"] as? [String: Any]) ?? [:]
        let list = (data["vnicList"] as? [[String: Any]]) ?? []
        let vnics = list.map { parseVnic($0) }
        var stats = VnicStatistics()
        if let s = data["statistics"] as? [String: Any] {
            stats.totalVnicCount = InstanceJSON.int(s["totalVnicCount"])
            stats.activeVnicCount = InstanceJSON.int(s["activeVnicCount"])
            stats.secondaryVnicCount = InstanceJSON.int(s["secondaryVnicCount"])
            stats.totalIpv6Count = InstanceJSON.int(s["totalIpv6Count"])
        }
        let tenantId = InstanceJSON.string(data["tenantId"])
        let primarySubnet = (data["primaryVnic"] as? [String: Any]).map { InstanceJSON.string($0["subnetId"]) } ?? ""
        return (vnics, stats, tenantId, primarySubnet)
    }

    func createVnic(ociInstanceId: String, subnetId: String, vnicCount: Int, ipv6Count: Int) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/vnic/create")
        let raw = try await client.postJSON(url, body: [
            "instanceId": ociInstanceId,
            "subnetId": subnetId,
            "vnicCount": vnicCount,
            "ipv6CountPerVnic": ipv6Count
        ])
        return try parseMsg(raw, fallback: "创建完成")
    }

    func deleteVnic(ociInstanceId: String, vnicId: String) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/vnic/delete")
        let raw = try await client.postJSON(url, body: [
            "instanceId": ociInstanceId,
            "vnicId": vnicId
        ])
        return try parseMsg(raw, fallback: "删除完成")
    }

    func createIpv6(ociInstanceId: String, vnicId: String, count: Int) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/vnic/createIpv6")
        let raw = try await client.postJSON(url, body: [
            "instanceId": ociInstanceId,
            "vnicId": vnicId,
            "ipv6Count": count
        ])
        return try parseMsg(raw, fallback: "IPv6 创建完成")
    }

    func deleteIpv6(ociInstanceId: String, vnicId: String, address: String) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/vnic/deleteIpv6")
        let raw = try await client.postJSON(url, body: [
            "instanceId": ociInstanceId,
            "vnicId": vnicId,
            "ipv6Address": address
        ])
        return try parseMsg(raw, fallback: "IPv6 已删除")
    }

    func deleteAllSecondary(ociInstanceId: String) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/vnic/deleteAllSecondary")
        let raw = try await client.postJSON(url, body: ["instanceId": ociInstanceId])
        return try parseMsg(raw, fallback: "已删除辅助 VNIC")
    }

    func refresh(ociInstanceId: String) async throws -> (vnics: [VnicItem], stats: VnicStatistics, tenantId: String, primarySubnet: String) {
        // Web refresh 走 /oci/vnic/refresh 再 load；直接 load 即可
        return try await loadData(ociInstanceId: ociInstanceId)
    }

    func configureLoadBalancer(ociInstanceId: String) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/vnic/network/configureLoadBalancer")
        let raw = try await client.postJSON(url, body: ["instanceId": ociInstanceId])
        return try parseMsg(raw, fallback: "负载均衡配置完成")
    }

    func restoreNetwork(ociInstanceId: String) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/vnic/network/restoreNetwork")
        let raw = try await client.postJSON(url, body: ["instanceId": ociInstanceId])
        return try parseMsg(raw, fallback: "网络已还原")
    }

    private func parseVnic(_ m: [String: Any]) -> VnicItem {
        var v = VnicItem()
        v.vnicId = InstanceJSON.string(m["vnicId"])
        v.vnicDisplayName = InstanceJSON.string(m["vnicDisplayName"])
        v.privateIp = InstanceJSON.string(m["privateIp"])
        v.publicIp = InstanceJSON.string(m["publicIp"])
        v.subnetId = InstanceJSON.string(m["subnetId"])
        v.attachmentId = InstanceJSON.string(m["attachmentId"])
        if let st = m["lifecycleState"] as? String {
            v.lifecycleState = st
        } else {
            v.lifecycleState = InstanceJSON.string(m["lifecycleState"])
        }
        if let arr = m["ipv6Addresses"] as? [String] {
            v.ipv6Addresses = arr
        } else if let arr = m["ipv6Addresses"] as? [Any] {
            v.ipv6Addresses = arr.map { InstanceJSON.string($0) }.filter { !$0.isEmpty }
        }
        if let b = m["isPrimary"] as? Bool {
            v.isPrimary = b
        } else if let n = m["isPrimary"] as? NSNumber {
            v.isPrimary = n.boolValue
        }
        return v
    }

    private func parseMsg(_ data: Data, fallback: String) throws -> String {
        let r = InstanceJSON.successMessage(data, fallback: fallback)
        // 部分接口用 success:bool
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let s = obj["success"] as? Bool, !s {
                let msg = InstanceJSON.string(obj["message"])
                throw APIError.serverMessage(msg.isEmpty ? fallback + "失败" : msg)
            }
        }
        if !r.ok { throw APIError.serverMessage(r.message) }
        return r.message
    }
}

// MARK: - ViewModel

@MainActor
final class InstanceVnicViewModel: ObservableObject {
    let item: InstanceItem
    private let session: AppSession
    private var service: InstanceVnicService { InstanceVnicService(baseURL: session.serverURL) }

    @Published var vnics: [VnicItem] = []
    @Published var stats = VnicStatistics()
    @Published var isLoading = false
    @Published var isBusy = false
    @Published var errorText: String?
    @Published var primarySubnet = ""

    // Create form
    @Published var showCreate = false
    @Published var formSubnet = ""
    @Published var formVnicCount = "1"
    @Published var formIpv6Count = "0"
    @Published var formError: String?

    // IPv6 form
    @Published var showIpv6 = false
    @Published var ipv6Target: VnicItem?
    @Published var formIpv6AddCount = "1"

    init(item: InstanceItem, session: AppSession = .shared) {
        self.item = item
        self.session = session
    }

    private var ociId: String { item.instanceId }

    func start() {
        Task { await reload() }
    }

    func reload() async {
        guard !ociId.isEmpty else {
            errorText = "缺少 OCI 实例 OCID"
            return
        }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let r = try await service.loadData(ociInstanceId: ociId)
            vnics = r.vnics
            stats = r.stats
            primarySubnet = r.primarySubnet
            if formSubnet.isEmpty { formSubnet = r.primarySubnet }
        } catch {
            errorText = error.localizedDescription
            vnics = []
        }
    }

    func openCreate() {
        formSubnet = primarySubnet
        formVnicCount = "1"
        formIpv6Count = "0"
        formError = nil
        showCreate = true
    }

    func submitCreate() {
        let subnet = formSubnet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subnet.isEmpty else {
            formError = "请填写子网 ID"
            return
        }
        guard let vc = Int(formVnicCount), vc >= 1, vc <= 24 else {
            formError = "VNIC 数量须为 1–24"
            return
        }
        guard let ic = Int(formIpv6Count), ic >= 0, ic <= 32 else {
            formError = "每 VNIC IPv6 数量无效"
            return
        }
        Task {
            isBusy = true
            formError = nil
            do {
                let msg = try await service.createVnic(
                    ociInstanceId: ociId, subnetId: subnet, vnicCount: vc, ipv6Count: ic
                )
                showCreate = false
                ToastCenter.shared.success(msg)
                await reload()
            } catch {
                formError = error.localizedDescription
            }
            isBusy = false
        }
    }

    func deleteVnic(_ v: VnicItem) {
        guard !v.isPrimary else {
            ToastCenter.shared.error("不能删除主 VNIC")
            return
        }
        guard AppAlert.confirm(
            title: "删除 VNIC",
            message: "确定删除 \(v.vnicDisplayName.isEmpty ? v.vnicId : v.vnicDisplayName)？",
            confirmTitle: "删除",
            style: .critical
        ) else { return }
        Task {
            isBusy = true
            do {
                let msg = try await service.deleteVnic(ociInstanceId: ociId, vnicId: v.vnicId)
                ToastCenter.shared.success(msg)
                await reload()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            isBusy = false
        }
    }

    func openAddIpv6(_ v: VnicItem) {
        ipv6Target = v
        formIpv6AddCount = "1"
        formError = nil
        showIpv6 = true
    }

    func submitIpv6() {
        guard let v = ipv6Target else { return }
        guard let c = Int(formIpv6AddCount), c >= 1, c <= 32 else {
            formError = "数量须为 1–32"
            return
        }
        Task {
            isBusy = true
            formError = nil
            do {
                let msg = try await service.createIpv6(ociInstanceId: ociId, vnicId: v.vnicId, count: c)
                showIpv6 = false
                ToastCenter.shared.success(msg)
                await reload()
            } catch {
                formError = error.localizedDescription
            }
            isBusy = false
        }
    }

    func deleteIpv6(vnic: VnicItem, address: String) {
        guard AppAlert.confirm(
            title: "删除 IPv6",
            message: "删除地址 \(address)？",
            confirmTitle: "删除",
            style: .critical
        ) else { return }
        Task {
            isBusy = true
            do {
                let msg = try await service.deleteIpv6(ociInstanceId: ociId, vnicId: vnic.vnicId, address: address)
                ToastCenter.shared.success(msg)
                await reload()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            isBusy = false
        }
    }

    func deleteAllSecondary() {
        guard stats.secondaryVnicCount > 0 else {
            ToastCenter.shared.error("没有辅助 VNIC")
            return
        }
        guard AppAlert.confirm(
            title: "删除全部辅助 VNIC",
            message: "将删除 \(stats.secondaryVnicCount) 个辅助网卡，此操作不可恢复。",
            confirmTitle: "删除",
            style: .critical
        ) else { return }
        Task {
            isBusy = true
            do {
                let msg = try await service.deleteAllSecondary(ociInstanceId: ociId)
                ToastCenter.shared.success(msg)
                await reload()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            isBusy = false
        }
    }

    func configureLB() {
        guard AppAlert.confirm(title: "配置负载均衡", message: "为一键配置负载均衡网络？可能耗时较长。") else { return }
        Task {
            isBusy = true
            do {
                let msg = try await service.configureLoadBalancer(ociInstanceId: ociId)
                ToastCenter.shared.success(msg)
                await reload()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            isBusy = false
        }
    }

    func restoreNetwork() {
        guard AppAlert.confirm(
            title: "还原网络",
            message: "将还原网络配置（可能删除 LB / 网关等），是否继续？",
            confirmTitle: "还原",
            style: .critical
        ) else { return }
        Task {
            isBusy = true
            do {
                let msg = try await service.restoreNetwork(ociInstanceId: ociId)
                ToastCenter.shared.success(msg)
                await reload()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            isBusy = false
        }
    }

    func copy(_ text: String, label: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(t, forType: .string)
        ToastCenter.shared.success("\(label) 已复制")
    }
}

// MARK: - View

struct InstanceVnicView: View {
    let item: InstanceItem
    var onBack: (() -> Void)?
    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var model: InstanceVnicViewModel

    init(item: InstanceItem, onBack: (() -> Void)? = nil) {
        self.item = item
        self.onBack = onBack
        _model = StateObject(wrappedValue: InstanceVnicViewModel(item: item))
    }

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let err = model.errorText, !err.isEmpty {
                errorBanner(err)
            }
            summaryBar
            actionBar
            listBody
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background(AppTheme.pageBg(dark))
        .appLoading(model.isBusy || (model.isLoading && !model.vnics.isEmpty))
        .onAppear {
            FloatingMenuDismiss.all()
            model.start()
        }
        .sheet(isPresented: $model.showCreate) { createSheet }
        .sheet(isPresented: $model.showIpv6) { ipv6Sheet }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if onBack != nil {
                AppButton(title: "返回", systemImage: "chevron.left", kind: .secondary) {
                    onBack?()
                }
            }
            Image(systemName: "network")
                .foregroundColor(AppTheme.sidebarActive)
            VStack(alignment: .leading, spacing: 2) {
                Text("网络管理 — \(item.displayName.isEmpty ? "实例" : item.displayName)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
                Text(item.instanceId.isEmpty ? "缺少 OCID" : item.instanceId)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(AppTheme.sidebarText(dark))
                    .lineLimit(1)
            }
            Spacer()
            AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary, isLoading: model.isLoading) {
                Task { await model.reload() }
            }
            if onBack == nil {
                AppButton(title: "关闭", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.sidebarBg(dark))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.55)),
            alignment: .bottom
        )
    }

    private var summaryBar: some View {
        HStack(spacing: 10) {
            chip("VNIC", "\(model.stats.totalVnicCount)", AppTheme.sidebarActive)
            chip("活跃", "\(model.stats.activeVnicCount)", Color(hex: "3fb950"))
            chip("辅助", "\(model.stats.secondaryVnicCount)", Color(hex: "d29922"))
            chip("IPv6", "\(model.stats.totalIpv6Count)", Color(hex: "a371f7"))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func chip(_ title: String, _ value: String, _ accent: Color) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppSheetSurface.mutedText(dark))
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(AppSheetSurface.panelBg(dark)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppSheetSurface.border(dark), lineWidth: 1))
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            AppButton(title: "创建 VNIC", systemImage: "plus", kind: .primary) { model.openCreate() }
            AppButton(title: "删除辅助", systemImage: "trash", kind: .danger) { model.deleteAllSecondary() }
            AppButton(title: "负载均衡", kind: .secondary) { model.configureLB() }
            AppButton(title: "还原网络", kind: .secondary) { model.restoreNetwork() }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var listBody: some View {
        if model.isLoading && model.vnics.isEmpty {
            VStack {
                Spacer()
                ProgressView()
                Text("加载网络…").font(.system(size: 12)).foregroundColor(AppSheetSurface.mutedText(dark))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.vnics.isEmpty {
            EmptyStateView(
                icon: "network",
                title: "暂无 VNIC",
                subtitle: "刷新或检查实例 OCID",
                actionTitle: "刷新",
                action: { Task { await model.reload() } }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.vnics) { v in
                        vnicCard(v)
                    }
                }
                .padding(16)
            }
        }
    }

    private func vnicCard(_ v: VnicItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(v.vnicDisplayName.isEmpty ? v.vnicId : v.vnicDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppSheetSurface.primaryText(dark))
                    .lineLimit(1)
                if v.isPrimary {
                    Text("主")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppTheme.sidebarActive))
                }
                Spacer()
                Text(v.lifecycleState.isEmpty ? "—" : v.lifecycleState)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(v.lifecycleState.uppercased() == "ATTACHED" ? Color(hex: "3fb950") : AppSheetSurface.mutedText(dark))
            }
            infoRow("公网", v.publicIp.isEmpty ? "—" : v.publicIp) { model.copy(v.publicIp, label: "公网 IP") }
            infoRow("内网", v.privateIp.isEmpty ? "—" : v.privateIp) { model.copy(v.privateIp, label: "内网 IP") }
            infoRow("子网", v.subnetId.isEmpty ? "—" : v.subnetId) { model.copy(v.subnetId, label: "子网 ID") }
            if !v.ipv6Addresses.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("IPv6")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppSheetSurface.mutedText(dark))
                    ForEach(v.ipv6Addresses, id: \.self) { ip in
                        HStack {
                            Text(ip)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(AppTheme.sidebarActive)
                                .lineLimit(1)
                            Spacer()
                            Button("复制") { model.copy(ip, label: "IPv6") }
                                .buttonStyle(PlainButtonStyle())
                                .font(.system(size: 11))
                            Button("删除") { model.deleteIpv6(vnic: v, address: ip) }
                                .buttonStyle(PlainButtonStyle())
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "f85149"))
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Spacer()
                AppButton(title: "添加 IPv6", kind: .secondary) { model.openAddIpv6(v) }
                if !v.isPrimary {
                    AppButton(title: "删除", kind: .danger) { model.deleteVnic(v) }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppSheetSurface.panelBg(dark)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppSheetSurface.border(dark), lineWidth: 1))
    }

    private func infoRow(_ label: String, _ value: String, copy: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppSheetSurface.mutedText(dark))
                .frame(width: 36, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(AppSheetSurface.primaryText(dark))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if value != "—" {
                Button(action: copy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(AppSheetSurface.mutedText(dark))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.system(size: 12))
            Spacer()
            Button("重试") { Task { await model.reload() } }
                .buttonStyle(PlainButtonStyle())
        }
        .foregroundColor(Color(hex: "f85149"))
        .padding(12)
        .background(Color(hex: "f85149").opacity(0.1))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var createSheet: some View {
        AppSheetChrome(
            title: "创建 VNIC",
            systemImage: "plus.circle",
            width: 440,
            height: 320,
            fixedSize: true,
            onClose: { model.showCreate = false },
            footer: {
                HStack {
                    AppButton(title: "取消", kind: .secondary) { model.showCreate = false }
                    AppButton(title: "创建", kind: .primary, isLoading: model.isBusy) { model.submitCreate() }
                }
            },
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    FormFieldRow(label: "子网 ID", required: true) {
                        AppTextField(text: $model.formSubnet, placeholder: "ocid1.subnet…", leadingSystemImage: "network")
                    }
                    FormFieldRow(label: "VNIC 数量", required: true) {
                        AppTextField(text: $model.formVnicCount, placeholder: "1")
                    }
                    FormFieldRow(label: "每 VNIC IPv6 数") {
                        AppTextField(text: $model.formIpv6Count, placeholder: "0")
                    }
                    if let e = model.formError, !e.isEmpty {
                        Text(e).font(.system(size: 12)).foregroundColor(Color(hex: "f85149"))
                    }
                }
            }
        )
        .environmentObject(appearance)
    }

    private var ipv6Sheet: some View {
        AppSheetChrome(
            title: "添加 IPv6",
            systemImage: "globe",
            width: 400,
            height: 240,
            fixedSize: true,
            onClose: { model.showIpv6 = false },
            footer: {
                HStack {
                    AppButton(title: "取消", kind: .secondary) { model.showIpv6 = false }
                    AppButton(title: "创建", kind: .primary, isLoading: model.isBusy) { model.submitIpv6() }
                }
            },
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.ipv6Target?.vnicDisplayName ?? model.ipv6Target?.vnicId ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(AppSheetSurface.mutedText(dark))
                    FormFieldRow(label: "数量", required: true) {
                        AppTextField(text: $model.formIpv6AddCount, placeholder: "1")
                    }
                    if let e = model.formError, !e.isEmpty {
                        Text(e).font(.system(size: 12)).foregroundColor(Color(hex: "f85149"))
                    }
                }
            }
        )
        .environmentObject(appearance)
    }
}
