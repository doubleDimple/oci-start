import SwiftUI

/// 原生代理配置（对齐 Web `/vpnProxy/page` · `vpn_proxy.ftl`）。
struct ProxyConfigView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = ProxyConfigViewModel()
    /// Row ids currently showing plaintext password (click-to-reveal, align Web).
    @State private var revealedPasswordIds: Set<Int64> = []

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        PageScaffold(
            title: "代理配置",
            subtitle: "HTTP/HTTPS 代理池 · 强制代理 · 按租户绑定或全局共享",
            systemImage: "arrow.left.arrow.right",
            toolbar: { toolbar },
            content: {
                VStack(spacing: 0) {
                    if let err = model.errorText, !err.isEmpty {
                        errorBanner(err)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }
                    listBody
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .appLoading(model.isLoading && model.items.isEmpty)
            },
            footer: {
                PaginationBar(state: $model.pageState) {
                    model.onPageChange()
                }
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onAppear { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            Task { await model.reload() }
        }
        .sheet(item: $model.activeForm) { _ in
            ProxyConfigSheet(model: model)
                .environmentObject(appearance)
        }
        .environmentObject(appearance)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            AppButton(
                title: "一键全部测试",
                systemImage: "network",
                kind: .secondary,
                isLoading: model.isTestingAll
            ) {
                model.testAll()
            }
            .disabled(model.isTestingAll || model.items.isEmpty)
            AppButton(title: "新增代理", systemImage: "plus", kind: .primary) {
                model.openAdd()
            }
            AppButton(
                title: "刷新",
                systemImage: "arrow.clockwise",
                kind: .secondary,
                isLoading: model.isLoading
            ) {
                Task { await model.reload() }
            }
        }
    }

    private var listBody: some View {
        Group {
            if model.items.isEmpty && !model.isLoading {
                EmptyStateView(
                    icon: "arrow.left.arrow.right.circle",
                    title: "暂无代理",
                    subtitle: "点击「新增代理」配置 HTTP/HTTPS 出口",
                    actionTitle: "新增代理",
                    action: { model.openAdd() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DataList {
                    DataListColumnHeader(title: "名称", width: 100)
                    DataListColumnHeader(title: "类型", width: 64)
                    DataListColumnHeader(title: "地址", width: nil)
                    DataListColumnHeader(title: "端口", width: 56)
                    DataListColumnHeader(title: "用户名", width: 88)
                    DataListColumnHeader(title: "密码", width: 80)
                    DataListColumnHeader(title: "租户", width: 110)
                    DataListColumnHeader(title: "强制", width: 72)
                    DataListColumnHeader(title: "连通状态", width: 80)
                    DataListColumnHeader(title: "操作", width: 170, alignment: .trailing)
                } content: {
                    ForEach(model.items) { item in
                        DataListRow {
                            row(item)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
        }
    }

    private func row(_ item: VpnProxyItem) -> some View {
        HStack(spacing: 0) {
            cell(item.customName.isEmpty ? "—" : item.customName, width: 100, weight: .semibold)
            cell(item.proxyType, width: 64, weight: .semibold)
            cell(item.proxyHost, width: nil)
            cell("\(item.proxyPort)", width: 56)
            cell(item.proxyUsername.isEmpty ? "—" : item.proxyUsername, width: 88)
            passwordCell(item)
            cell(item.tenantLabel, width: 110)
            // 强制列可点切换（橙=强制 / 绿=非强制）
            forceShieldCell(item)
            StatusBadge(text: item.statusLabel, tone: item.statusTone)
                .frame(width: 80, alignment: .leading)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Button(action: { model.testConnection(item) }) {
                    Image(systemName: item.isTesting ? "ellipsis" : "bolt.horizontal.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.sidebarActive)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AppTheme.sidebarActive.opacity(0.12))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(item.isTesting || model.isTestingAll)
                .help("测试连通")
                Button(action: { model.toggleForce(item) }) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(item.isForce
                                         ? Color(hex: "e67e22")
                                         : Color(hex: "1abc9c"))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill((item.isForce
                                       ? Color(hex: "e67e22")
                                       : Color(hex: "1abc9c")).opacity(0.12))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .help(item.isForce ? "关闭强制代理" : "开启强制代理")
                Button(action: { model.openEdit(item) }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.sidebarActive)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AppTheme.sidebarActive.opacity(0.12))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .help("编辑")
                Button(action: { model.delete(item) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "f85149"))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: "f85149").opacity(0.12))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .help("删除")
            }
            .frame(width: 170)
        }
    }

    /// 强制列：橙=强制，绿=非强制；点击切换
    private func forceShieldCell(_ item: VpnProxyItem) -> some View {
        Button(action: { model.toggleForce(item) }) {
            HStack(spacing: 4) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 12))
                    .foregroundColor(item.isForce
                                     ? Color(hex: dark ? "e67e22" : "d35400")
                                     : Color(hex: dark ? "1abc9c" : "16a085"))
                Text(item.forceLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(item.isForce
                                     ? Color(hex: dark ? "e67e22" : "d35400")
                                     : Color(hex: dark ? "1abc9c" : "16a085"))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill((item.isForce
                           ? Color(hex: "e67e22")
                           : Color(hex: "1abc9c")).opacity(0.12))
            )
            .frame(width: 72, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help(item.isForce
              ? "强制代理：不通则拒绝请求（点击关闭）"
              : "非强制：不通可直连（点击开启强制）")
    }

    private func passwordCell(_ item: VpnProxyItem) -> some View {
        if item.proxyPassword.isEmpty {
            return AnyView(cell("—", width: 80))
        }
        let revealed = revealedPasswordIds.contains(item.id)
        return AnyView(
            Button(action: {
                if revealedPasswordIds.contains(item.id) {
                    revealedPasswordIds.remove(item.id)
                } else {
                    revealedPasswordIds.insert(item.id)
                }
            }) {
                HStack(spacing: 4) {
                    Text(revealed ? item.proxyPassword : "••••••••")
                        .font(.system(size: 12, design: revealed ? .monospaced : .default))
                        .foregroundColor(dark ? Color.white.opacity(0.88) : Color(hex: "1e2f42"))
                        .lineLimit(1)
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.sidebarText(dark))
                }
                .frame(width: 80, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            .help(revealed ? "隐藏密码" : "显示密码")
        )
    }

    private func cell(_ text: String, width: CGFloat?, weight: Font.Weight = .regular) -> some View {
        Text(text)
            .font(.system(size: 12, weight: weight))
            .foregroundColor(dark ? Color.white.opacity(0.88) : Color(hex: "1e2f42"))
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(hex: "f85149"))
            Text(text).font(.system(size: 12))
            Spacer()
            Button("重试") { Task { await model.reload() } }
                .buttonStyle(PlainButtonStyle())
        }
        .foregroundColor(Color(hex: "f85149"))
        .padding(12)
        .background(Color(hex: "f85149").opacity(0.1))
        .cornerRadius(8)
    }
}
