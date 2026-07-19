import SwiftUI

/// 原生 Cloudflare DNS 管理（对齐 Web `/dns/cloudflare` · `cf_manage.ftl`）。
struct CloudflareView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = CloudflareViewModel()

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        PageScaffold(
            title: "Cloudflare",
            subtitle: "DNS 解析管理 · 代理状态 · 同步记录",
            systemImage: "cloud.fill",
            toolbar: { toolbar },
            content: {
                VStack(spacing: 0) {
                    if let err = model.errorText, !err.isEmpty {
                        errorBanner(err)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }
                    filterBar
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    listBody
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .appLoading((model.isLoading || model.isZonesLoading) && model.records.isEmpty && model.zones.isEmpty)
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
            Task { await model.loadZones(selectFirst: false); await model.reloadRecords() }
        }
        .sheet(item: $model.dnsForm) { _ in
            CloudflareDnsSheet(model: model)
                .environmentObject(appearance)
        }
        .sheet(item: $model.configForm) { _ in
            CloudflareConfigSheet(model: model)
                .environmentObject(appearance)
        }
        .environmentObject(appearance)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            AppButton(title: "密钥配置", systemImage: "key", kind: .secondary) {
                model.openConfig()
            }
            AppButton(title: "添加记录", systemImage: "plus", kind: .primary) {
                model.openAdd()
            }
            AppButton(
                title: "同步记录",
                systemImage: "arrow.triangle.2.circlepath",
                kind: .secondary,
                isLoading: model.isSyncing
            ) {
                model.syncRecords()
            }
            AppButton(
                title: "刷新",
                systemImage: "arrow.clockwise",
                kind: .secondary,
                isLoading: model.isLoading
            ) {
                Task { await model.reloadRecords() }
            }
        }
    }

    // MARK: - Filter

    private var filterBar: some View {
        FilterBar {
            HStack(spacing: 10) {
                Text("域名")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.sidebarText(dark))
                SelectMenu(
                    options: model.zoneOptions,
                    selection: Binding(
                        get: { model.selectedZoneId },
                        set: { model.onZoneChange($0) }
                    ),
                    placeholder: model.zones.isEmpty ? "暂无域名" : "选择域名",
                    width: 220,
                    allowClear: false,
                    searchable: true
                )
                AppButton(
                    title: "刷新域名",
                    systemImage: "arrow.clockwise",
                    kind: .secondary,
                    isLoading: model.isZonesLoading
                ) {
                    Task { await model.loadZones(selectFirst: false) }
                }

                SearchField(text: $model.searchName, placeholder: "记录名")
                    .frame(width: 140)
                SearchField(text: $model.searchContent, placeholder: "记录值")
                    .frame(width: 140)
                if !model.searchName.isEmpty || !model.searchContent.isEmpty {
                    AppButton(title: "清除", systemImage: "xmark", kind: .secondary) {
                        model.clearSearch()
                    }
                }
            }
        }
    }

    // MARK: - List

    private var listBody: some View {
        Group {
            if model.selectedZoneId == nil || model.selectedZoneId?.isEmpty == true {
                EmptyStateView(
                    icon: "cloud",
                    title: model.zones.isEmpty ? "暂无可用域名" : "请选择域名",
                    subtitle: model.zones.isEmpty
                        ? "请先在「密钥配置」中填写 Cloudflare API Key，或点击「密钥配置」"
                        : "从上方下拉选择要管理的 Zone",
                    actionTitle: "密钥配置",
                    action: { model.openConfig() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.filteredRecords.isEmpty && !model.isLoading {
                EmptyStateView(
                    icon: "list.bullet.rectangle",
                    title: model.records.isEmpty ? "暂无 DNS 记录" : "无匹配结果",
                    subtitle: model.records.isEmpty ? "点击「添加记录」创建解析" : "试试其他关键词（仅过滤当前页）",
                    actionTitle: model.records.isEmpty ? "添加记录" : nil,
                    action: model.records.isEmpty ? { model.openAdd() } : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DataList {
                    DataListColumnHeader(title: "类型", width: 72)
                    DataListColumnHeader(title: "记录名", width: nil)
                    DataListColumnHeader(title: "记录值", width: nil)
                    DataListColumnHeader(title: "TTL", width: 72)
                    DataListColumnHeader(title: "代理", width: 80)
                    DataListColumnHeader(title: "操作", width: 88, alignment: .trailing)
                } content: {
                    ForEach(model.filteredRecords) { item in
                        DataListRow {
                            row(item)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .appLoading(model.isLoading)
            }
        }
    }

    private func row(_ item: CfDnsRecord) -> some View {
        HStack(spacing: 0) {
            typeChip(item.type)
                .frame(width: 72, alignment: .leading)
            cell(item.name, width: nil)
            cell(item.content, width: nil)
            cell(CloudflareJSON.formatTTL(item.ttl), width: 72)
            StatusBadge(
                text: item.proxied ? "已代理" : "仅 DNS",
                tone: item.proxied ? .warning : .info
            )
            .frame(width: 80, alignment: .leading)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                actionBtn("pencil", color: AppTheme.sidebarActive, tip: "编辑") {
                    model.openEdit(item)
                }
                actionBtn("trash", color: Color(hex: "f85149"), tip: "删除") {
                    model.delete(item)
                }
            }
            .frame(width: 88)
        }
    }

    private func typeChip(_ type: String) -> some View {
        let c = CloudflareJSON.typeColor(type)
        return Text(type)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(c)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(c.opacity(0.15))
            .cornerRadius(6)
    }

    private func cell(_ text: String, width: CGFloat?) -> some View {
        Text(text.isEmpty ? "—" : text)
            .font(.system(size: 12))
            .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : width, alignment: .leading)
            .help(text)
    }

    private func actionBtn(_ icon: String, color: Color, tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.12)))
        }
        .buttonStyle(PlainButtonStyle())
        .help(tip)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(hex: "f85149"))
            Text(text).font(.system(size: 12))
            Spacer()
            Button("密钥配置") { model.openConfig() }
                .buttonStyle(PlainButtonStyle())
            Button("重试") {
                Task { await model.loadZones(selectFirst: true) }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .foregroundColor(Color(hex: "f85149"))
        .padding(12)
        .background(Color(hex: "f85149").opacity(0.1))
        .cornerRadius(8)
    }
}
