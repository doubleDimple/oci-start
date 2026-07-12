import SwiftUI

/// Sheet form to create a boot task (Web: /tenants/bootPage + POST /tenants/boot/save)
/// Not a sidebar item — opened from 一键开机 toolbar only.
struct AddBootTaskView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var tenants: [Tenant] = []
    @State private var selectedTenant: Tenant?
    @State private var architecture = "ARM"
    @State private var ocpu = "1"
    @State private var memory = "6"
    @State private var disk = "50"
    @State private var instanceCount = "1"
    @State private var loopTime = "60"
    @State private var dayGap = ""
    @State private var remark = ""
    @State private var rootPassword = ""
    @State private var images: [SystemImage] = []
    @State private var selectedImageId = ""
    @State private var loadingTenants = false
    @State private var loadingImages = false
    @State private var saving = false
    @State private var localError: String?

    private let archOptions = ["ARM", "AMD"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("添加开机任务")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(AppTheme.text(scheme))
                Spacer()
                Button(action: { dismiss.wrappedValue.dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppTheme.muted(scheme))
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    formRow("租户") {
                        if loadingTenants {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Picker("", selection: $selectedTenant) {
                                Text("选择租户…").tag(Optional<Tenant>.none)
                                ForEach(tenants) { t in
                                    Text(t.displayName).tag(Optional(t))
                                }
                            }
                            .labelsHidden()
                            .onChange(of: selectedTenant) { t in
                                if t != nil { Task { await loadImages() } }
                            }
                        }
                    }

                    formRow("架构") {
                        Picker("", selection: $architecture) {
                            ForEach(archOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: architecture) { _ in Task { await loadImages() } }
                    }

                    HStack(spacing: 12) {
                        halfField("OCPU", text: $ocpu)
                        halfField("内存 (GB)", text: $memory)
                        halfField("磁盘 (GB)", text: $disk)
                    }

                    HStack(spacing: 12) {
                        halfField("实例数", text: $instanceCount)
                        halfField("间隔(秒)", text: $loopTime)
                    }

                    formRow("系统镜像") {
                        if loadingImages {
                            ProgressView().scaleEffect(0.8)
                        } else if images.isEmpty {
                            Text(selectedTenant == nil ? "请先选择租户" : "暂无镜像 / 可留空")
                                .font(.caption).foregroundColor(AppTheme.muted(scheme))
                        } else {
                            Picker("", selection: $selectedImageId) {
                                Text("默认 / 不指定").tag("")
                                ForEach(Array(images.enumerated()), id: \.offset) { _, img in
                                    Text(img.label).tag(img.imageId ?? "")
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    formRow("root 密码（可选）") {
                        SecureField("留空则自动生成", text: $rootPassword)
                            .textFieldStyle(.roundedBorder)
                    }

                    formRow("dayGap（可选）") {
                        TextField("例如 1-3 或留空", text: $dayGap)
                            .textFieldStyle(.roundedBorder)
                    }

                    formRow("备注") {
                        TextField("备注", text: $remark)
                            .textFieldStyle(.roundedBorder)
                    }

                    if let localError = localError {
                        Text(localError).font(.caption).foregroundColor(AppTheme.danger)
                    }

                    HStack {
                        Spacer()
                        Button("取消") { dismiss.wrappedValue.dismiss() }
                        Button(action: { Task { await save() } }) {
                            Text(saving ? "保存中…" : "创建任务")
                        }
                        .buttonStyle(ProminentButton())
                        .disabled(saving || selectedTenant == nil)
                        .keyboardShortcut(.return)
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
        }
        .frame(width: 480, height: 560)
        .background(AppTheme.surface(scheme))
        .onAppear { Task { await loadTenants() } }
    }

    private func halfField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.medium)).foregroundColor(AppTheme.muted(scheme))
            TextField(title, text: text).textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity)
    }

    private func formRow<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium)).foregroundColor(AppTheme.muted(scheme))
            content()
        }
    }

    private func loadTenants() async {
        loadingTenants = true
        defer { loadingTenants = false }
        await appState.loadAllTenants()
        tenants = appState.allTenants.filter { ($0.cloudType ?? 1) == 1 }
    }

    private func loadImages() async {
        guard let t = selectedTenant else { images = []; return }
        loadingImages = true
        defer { loadingImages = false }
        do {
            images = try await appState.network.querySystemImages(
                baseURL: appState.serverURL, tenantId: t.id, shapeType: architecture)
            selectedImageId = ""
        } catch {
            images = []
        }
    }

    private func save() async {
        guard let t = selectedTenant else { return }
        saving = true
        localError = nil
        defer { saving = false }

        var params: [String: String] = [
            "tenantId": "\(t.id)",
            "architecture": architecture,
            "ocpu": ocpu,
            "memory": memory,
            "disk": disk,
            "instanceCount": instanceCount,
            "loopTime": loopTime,
            "rootPassword": rootPassword,
            "dayGap": dayGap,
            "remark": remark,
            "cloudType": "1"
        ]
        if !selectedImageId.isEmpty {
            params["imageId"] = selectedImageId
            if let img = images.first(where: { $0.imageId == selectedImageId }) {
                params["operatingSystem"] = img.operatingSystem ?? ""
                params["operatingSystemVersion"] = img.operatingSystemVersion ?? ""
            }
        }

        do {
            let r = try await appState.network.saveBootConfig(baseURL: appState.serverURL, params: params)
            if r.success == false {
                localError = r.message ?? "创建失败"
                return
            }
            appState.showToast(r.message ?? "开机任务已创建")
            await appState.loadBootTasks()
            dismiss.wrappedValue.dismiss()
        } catch {
            localError = error.localizedDescription
        }
    }
}

private extension SystemImage {
    var label: String {
        let os = operatingSystem ?? ""
        let ver = operatingSystemVersion ?? ""
        let id = imageId ?? ""
        if !os.isEmpty || !ver.isEmpty { return "\(os) \(ver)".trimmingCharacters(in: .whitespaces) }
        return id
    }
}
