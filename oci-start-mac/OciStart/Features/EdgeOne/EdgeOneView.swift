import SwiftUI

/// 原生腾讯云 EdgeOne 管理（对齐 Web `/dns/edgeone` · `eo_manage.ftl`）。
struct EdgeOneView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = EdgeOneViewModel()

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        PageScaffold(
            title: "EdgeOne",
            subtitle: "腾讯云 DNS 记录 · 加速域名 · 同步管理",
            systemImage: "globe",
            toolbar: { toolbar },
            content: {
                VStack(spacing: 0) {
                    if let err = model.errorText, !err.isEmpty {
                        errorBanner(err)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }
                    modePicker
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    filterBar
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    listBody
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .appLoading((model.isLoading || model.isZonesLoading) && model.zones.isEmpty)
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
        .onChange(of: model.searchName) { _ in model.onSearchChanged() }
        .onChange(of: model.searchContent) { _ in model.onSearchChanged() }
        .sheet(item: $model.dnsForm) { _ in
            EdgeOneDnsSheet(model: model)
                .environmentObject(appearance)
        }
        .sheet(item: $model.configForm) { _ in
            EdgeOneConfigSheet(model: model)
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
            if model.mode == .dns {
                AppButton(title: "添加记录", systemImage: "plus", kind: .primary) {
                    model.openAdd()
                }
            }
            AppButton(
                title: model.mode == .dns ? "同步记录" : "同步域名",
                systemImage: "arrow.triangle.2.circlepath",
                kind: .secondary,
                isLoading: model.isSyncing
            ) {
                model.sync()
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

    // MARK: - Mode picker (pill)

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(EdgeOneMode.allCases) { m in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.switchMode(m)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: m.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                        Text(m.title)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(model.mode == m
                                     ? .white
                                     : (dark ? Color.white.opacity(0.75) : Color(hex: "1e2f42")))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(model.mode == m
                                  ? Color(hex: "00b9ff")
                                  : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            Spacer()
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.sidebarBg(dark).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border(dark).opacity(0.6), lineWidth: 1)
        )
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

                SearchField(
                    text: $model.searchName,
                    placeholder: model.mode == .dns ? "记录名" : "域名 / 状态"
                )
                .frame(width: 140)
                SearchField(
                    text: $model.searchContent,
                    placeholder: model.mode == .dns ? "记录值" : "CNAME"
                )
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
                    icon: "globe",
                    title: model.zones.isEmpty ? "暂无可用域名" : "请选择域名",
                    subtitle: model.zones.isEmpty
                        ? "请先配置腾讯云 SecretId / SecretKey"
                        : "从上方下拉选择 EdgeOne 站点",
                    actionTitle: "密钥配置",
                    action: { model.openConfig() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.mode == .dns {
                dnsList
            } else {
                domainList
            }
        }
    }

    private var dnsList: some View {
        Group {
            if model.pagedDns.isEmpty && !model.isLoading {
                EmptyStateView(
                    icon: "list.bullet.rectangle",
                    title: model.filteredDns.isEmpty && !model.dnsRecords.isEmpty
                        ? "无匹配结果"
                        : "暂无 DNS 记录",
                    subtitle: model.dnsRecords.isEmpty
                        ? "点击「添加记录」或「同步记录」"
                        : "试试其他关键词",
                    actionTitle: model.dnsRecords.isEmpty ? "添加记录" : nil,
                    action: model.dnsRecords.isEmpty ? { model.openAdd() } : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DataList {
                    DataListColumnHeader(title: "类型", width: 72)
                    DataListColumnHeader(title: "记录名", width: nil)
                    DataListColumnHeader(title: "记录值", width: nil)
                    DataListColumnHeader(title: "TTL", width: 72)
                    DataListColumnHeader(title: "优先级", width: 64)
                    DataListColumnHeader(title: "操作", width: 88, alignment: .trailing)
                } content: {
                    ForEach(model.pagedDns) { item in
                        DataListRow {
                            dnsRow(item)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .appLoading(model.isLoading)
            }
        }
    }

    private var domainList: some View {
        Group {
            if model.pagedDomains.isEmpty && !model.isLoading {
                EmptyStateView(
                    icon: "speedometer",
                    title: model.filteredDomains.isEmpty && !model.accelDomains.isEmpty
                        ? "无匹配结果"
                        : "暂无加速域名",
                    subtitle: model.accelDomains.isEmpty
                        ? "点击「同步域名」从腾讯云拉取"
                        : "试试其他关键词",
                    actionTitle: model.accelDomains.isEmpty ? "同步域名" : nil,
                    action: model.accelDomains.isEmpty ? { model.sync() } : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DataList {
                    DataListColumnHeader(title: "域名", width: nil)
                    DataListColumnHeader(title: "状态", width: 90)
                    DataListColumnHeader(title: "CNAME", width: nil)
                    DataListColumnHeader(title: "协议", width: 100)
                    DataListColumnHeader(title: "操作", width: 56, alignment: .trailing)
                } content: {
                    ForEach(model.pagedDomains) { item in
                        DataListRow {
                            domainRow(item)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .appLoading(model.isLoading)
            }
        }
    }

    private func dnsRow(_ item: EoDnsRecord) -> some View {
        HStack(spacing: 0) {
            typeChip(item.type)
                .frame(width: 72, alignment: .leading)
            cell(item.name, width: nil)
            cell(item.content, width: nil)
            cell(EdgeOneJSON.formatTTL(item.ttl), width: 72)
            cell(item.priority.map { "\($0)" } ?? "—", width: 64)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                actionBtn("pencil", color: AppTheme.sidebarActive, tip: "编辑") {
                    model.openEdit(item)
                }
                actionBtn("trash", color: Color(hex: "f85149"), tip: "删除") {
                    model.deleteDns(item)
                }
            }
            .frame(width: 88)
        }
    }

    private func domainRow(_ item: EoAccelDomain) -> some View {
        HStack(spacing: 0) {
            cell(item.domainName, width: nil)
            StatusBadge(
                text: item.status.isEmpty ? "—" : item.status,
                tone: item.statusTone
            )
            .frame(width: 90, alignment: .leading)
            cell(item.cname.isEmpty ? "—" : item.cname, width: nil)
            cell(item.protocolLabel, width: 100)
            HStack {
                Spacer(minLength: 0)
                actionBtn("trash", color: Color(hex: "f85149"), tip: "删除") {
                    model.deleteDomain(item)
                }
            }
            .frame(width: 56)
        }
    }

    private func typeChip(_ type: String) -> some View {
        let c = EdgeOneJSON.typeColor(type)
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
