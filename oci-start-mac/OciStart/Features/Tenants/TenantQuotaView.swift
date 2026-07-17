import SwiftUI

/// 账号配额整页 — 对齐 Web `quotaModal` + `renderQuotaContent`。
/// 列：限额名称 / 实例类型 / 总量 / 已用 / 可用 / 进度条 / 占比
struct TenantQuotaView: View {
    @ObservedObject var model: TenantsViewModel
    @EnvironmentObject private var appearance: AppearanceController

    private var dark: Bool { appearance.isDarkEffective }
    private var tenant: TenantItem? { model.quotaParent }

    private let wType: CGFloat = 96
    private let wNum: CGFloat = 64
    private let wBar: CGFloat = 130
    private let wPct: CGFloat = 56
    private let minName: CGFloat = 220
    private let hPad: CGFloat = 14

    private let serviceOptions: [SelectOption] = [
        SelectOption(id: "compute", title: "计算 (Compute)"),
        SelectOption(id: "block-storage", title: "块存储 (Block Storage)"),
        SelectOption(id: "object-storage", title: "对象存储 (Object Storage)"),
        SelectOption(id: "mysql", title: "MySQL HeatWave"),
        SelectOption(id: "database", title: "Oracle Database (DBCS)"),
        SelectOption(id: "autonomous-database", title: "自治数据库 (ADB)"),
        SelectOption(id: "nosql", title: "NoSQL Database")
    ]

    private var serviceTitle: String {
        serviceOptions.first(where: { $0.id == model.quotaService })?.title ?? model.quotaService
    }

    private var hasTypeColumn: Bool {
        model.quotaItems.contains { $0.hasInstanceType }
    }

    private var showPagination: Bool {
        model.quotaPage > 0 || model.quotaHasNext
    }

    private var cardBorder: Color { AppTheme.border(dark) }
    private var surface: Color { dark ? Color(hex: "1a1d27") : Color.white }
    private var headerBg: Color { AppTheme.sidebarHover(dark).opacity(0.65) }
    private var primaryText: Color { dark ? Color.white.opacity(0.9) : Color(hex: "1e293b") }
    private var secondaryText: Color { AppTheme.sidebarText(dark) }

    var body: some View {
        PageScaffold(
            title: "账号配额",
            subtitle: tenant.map { $0.displayName },
            systemImage: "chart.bar.fill",
            toolbar: { toolbar },
            content: {
                VStack(spacing: 0) {
                    filterBar
                    if !model.quotaError.isEmpty {
                        errorBanner(model.quotaError)
                    }
                    statusLine
                    listBody
                    if showPagination && !model.quotaItems.isEmpty {
                        paginationBar
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appLoading(model.quotaLoading)
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            AppButton(title: "返回列表", systemImage: "chevron.left", kind: .secondary) {
                model.closeQuota()
            }
            AppButton(
                title: "刷新",
                systemImage: "arrow.clockwise",
                kind: .secondary,
                enabled: !model.quotaLoading
            ) {
                Task { await model.queryQuota(page: model.quotaPage) }
            }
        }
    }

    // MARK: - Filter（对齐 Web：仅租户 + 服务 + 查询）

    private var filterBar: some View {
        FilterBar(
            leading: {
                HStack(spacing: 12) {
                    if !model.quotaRegions.isEmpty {
                        SelectMenu(
                            options: model.quotaRegions.map { SelectOption(id: $0.id, title: $0.label) },
                            selection: Binding(
                                get: { model.quotaTenantId },
                                set: { model.quotaTenantId = $0 ?? "" }
                            ),
                            placeholder: "选择租户…",
                            width: 240,
                            allowClear: false
                        )
                    }
                    SelectMenu(
                        options: serviceOptions,
                        selection: Binding(
                            get: { model.quotaService },
                            set: { model.quotaService = $0 ?? "compute" }
                        ),
                        placeholder: "服务类型",
                        width: 220,
                        allowClear: false
                    )
                }
            },
            trailing: {
                AppButton(
                    title: "查询",
                    systemImage: "magnifyingglass",
                    kind: .primary,
                    isLoading: model.quotaLoading,
                    enabled: !model.quotaLoading
                ) {
                    Task { await model.queryQuota(page: 0) }
                }
            }
        )
    }

    private var statusLine: some View {
        HStack {
            Text(statusText)
                .font(.system(size: 12))
                .foregroundColor(secondaryText)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.sidebarHover(dark).opacity(0.35))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(cardBorder.opacity(0.5)),
            alignment: .bottom
        )
    }

    private var statusText: String {
        if model.quotaRegionLabel.isEmpty {
            return "选择租户和服务后点击查询"
        }
        return "\(model.quotaRegionLabel) · \(serviceTitle) · 第 \(model.quotaPage + 1) 页，共 \(model.quotaItems.count) 条"
    }

    private func errorBanner(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.system(size: 12))
            Spacer()
            Button("重试") {
                Task { await model.queryQuota(page: model.quotaPage) }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .foregroundColor(Color(hex: "f85149"))
        .padding(12)
        .background(Color(hex: "f85149").opacity(0.1))
    }

    // MARK: - Table

    @ViewBuilder
    private var listBody: some View {
        if model.quotaItems.isEmpty {
            EmptyStateView(
                icon: model.quotaError.isEmpty ? "tray" : "exclamationmark.circle",
                title: model.quotaError.isEmpty
                    ? (model.quotaRegionLabel.isEmpty ? "请先查询" : "该服务暂无配额数据")
                    : "查询失败",
                subtitle: model.quotaError.isEmpty
                    ? "选择租户和服务类型后点击查询"
                    : model.quotaError,
                actionTitle: model.quotaLoading ? nil : (model.quotaError.isEmpty ? "查询" : "重试"),
                action: model.quotaLoading ? nil : { Task { await model.queryQuota(page: 0) } }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geo in
                let typeW = hasTypeColumn ? wType : 0
                let fixed = typeW + wNum * 3 + wBar + wPct + minName + hPad * 2
                let totalW = max(geo.size.width - 32, fixed)
                let wName = minName + max(0, totalW - fixed)

                VStack(spacing: 0) {
                    headerRow(wName: wName, typeW: typeW, width: totalW)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.quotaItems.enumerated()), id: \.element.id) { idx, row in
                                dataRow(index: idx, row: row, wName: wName, typeW: typeW, width: totalW)
                            }
                        }
                    }
                }
                .frame(width: totalW, alignment: .topLeading)
                .background(surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(cardBorder, lineWidth: 1)
                )
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, showPagination ? 4 : 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func headerRow(wName: CGFloat, typeW: CGFloat, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            colHeader("限额名称", wName, align: .leading)
            if typeW > 0 {
                colHeader("实例类型", typeW, align: .center)
            }
            colHeader("总量", wNum, align: .center)
            colHeader("已用", wNum, align: .center)
            colHeader("可用", wNum, align: .center)
            colHeader("进度条", wBar, align: .leading)
            colHeader("占比", wPct, align: .center)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .background(headerBg)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(cardBorder.opacity(0.6)),
            alignment: .bottom
        )
    }

    private func dataRow(index: Int, row: TenantQuotaItem, wName: CGFloat, typeW: CGFloat, width: CGFloat) -> some View {
        let pct = row.usagePercent
        let stripe = index % 2 == 1 ? AppTheme.sidebarHover(dark).opacity(0.14) : Color.clear
        return HStack(spacing: 0) {
            // 限额名称 + 状态点
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(usageColor(pct))
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name.isEmpty ? "—" : row.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(primaryText)
                        .lineLimit(2)
                        .help(row.name)
                    if !row.scope.isEmpty {
                        Text(row.scope)
                            .font(.system(size: 10))
                            .foregroundColor(secondaryText)
                            .lineLimit(1)
                            .help(row.scope)
                    }
                }
            }
            .frame(width: wName, alignment: .leading)

            if typeW > 0 {
                Group {
                    if row.hasInstanceType {
                        typeBadge(row.instanceType)
                    } else {
                        Text("—")
                            .font(.system(size: 11))
                            .foregroundColor(secondaryText)
                    }
                }
                .frame(width: typeW, alignment: .center)
            }

            numCell(row.limit, wNum, color: secondaryText)
            numCell(row.used, wNum, color: secondaryText)
            numCell(row.available, wNum, color: availableColor(row), bold: true)

            // 进度条
            progressBar(pct: pct)
                .frame(width: wBar, alignment: .leading)
                .padding(.trailing, 4)

            Text("\(pct)%")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(pctColor(pct))
                .frame(width: wPct, alignment: .center)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .background(stripe)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(cardBorder.opacity(0.35)),
            alignment: .bottom
        )
    }

    // MARK: - Pagination（对齐 Web 底部条）

    private var paginationBar: some View {
        HStack(spacing: 12) {
            AppButton(
                title: "上一页",
                systemImage: "chevron.left",
                kind: .secondary,
                enabled: model.quotaPage > 0 && !model.quotaLoading
            ) {
                Task { await model.queryQuota(page: model.quotaPage - 1) }
            }

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Text("第 \(model.quotaPage + 1) 页")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(primaryText)
                Text("|")
                    .foregroundColor(cardBorder)
                Text("每页")
                    .font(.system(size: 12))
                    .foregroundColor(secondaryText)
                SelectMenu(
                    options: [10, 20, 50].map { SelectOption(id: "\($0)", title: "\($0)") },
                    selection: Binding(
                        get: { "\(model.quotaPageSize)" },
                        set: {
                            if let v = Int($0 ?? "20"), v != model.quotaPageSize {
                                model.quotaPageSize = v
                                Task { await model.queryQuota(page: 0) }
                            }
                        }
                    ),
                    placeholder: "20",
                    width: 72,
                    allowClear: false
                )
                Text("条")
                    .font(.system(size: 12))
                    .foregroundColor(secondaryText)
            }

            Spacer(minLength: 8)

            AppButton(
                title: "下一页",
                systemImage: "chevron.right",
                kind: .secondary,
                enabled: model.quotaHasNext && !model.quotaLoading
            ) {
                Task { await model.queryQuota(page: model.quotaPage + 1) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Cells / chrome

    private func colHeader(_ title: String, _ w: CGFloat, align: Alignment) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(secondaryText)
            .frame(width: w, alignment: align)
    }

    private func numCell(_ text: String, _ w: CGFloat, color: Color, bold: Bool = false) -> some View {
        Text(text.isEmpty ? "—" : text)
            .font(.system(size: 12, weight: bold ? .bold : .regular))
            .foregroundColor(color)
            .lineLimit(1)
            .frame(width: w, alignment: .center)
    }

    private func progressBar(pct: Int) -> some View {
        GeometryReader { geo in
            let fill = max(0, min(1, CGFloat(pct) / 100))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(AppTheme.sidebarHover(dark).opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(cardBorder.opacity(0.6), lineWidth: 1)
                    )
                RoundedRectangle(cornerRadius: 3)
                    .fill(usageColor(pct))
                    .frame(width: max(fill > 0 ? 4 : 0, geo.size.width * fill))
            }
        }
        .frame(height: 6)
        .padding(.trailing, 8)
    }

    private func typeBadge(_ typeName: String) -> some View {
        let style = QuotaTypeBadgeStyle.colors(for: typeName, dark: dark)
        let label = typeName.hasPrefix("裸金属·")
            ? "BM·" + String(typeName.dropFirst(4))
            : typeName
        return Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(style.fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(style.bg)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(style.bd, lineWidth: 1)
            )
            .cornerRadius(4)
            .lineLimit(1)
    }

    // MARK: - Colors（对齐 Web 阈值）

    private func usageColor(_ pct: Int) -> Color {
        if pct >= 90 { return Color(hex: "dc2626") }
        if pct >= 60 { return Color(hex: "d97706") }
        return Color(hex: "16a34a")
    }

    private func pctColor(_ pct: Int) -> Color {
        if pct >= 90 { return Color(hex: "dc2626") }
        if pct >= 60 { return Color(hex: "d97706") }
        return secondaryText
    }

    private func availableColor(_ row: TenantQuotaItem) -> Color {
        if row.availableValue <= 0 { return Color(hex: "dc2626") }
        if row.totalValue > 0, row.availableValue < row.totalValue * 0.2 {
            return Color(hex: "d97706")
        }
        return Color(hex: "16a34a")
    }
}

// MARK: - Type badge palette（Web `quotaTypeBadge`）

private enum QuotaTypeBadgeStyle {
    struct Colors {
        let bg: Color
        let fg: Color
        let bd: Color
    }

    static func colors(for typeName: String, dark: Bool) -> Colors {
        var key = typeName
        if typeName.hasPrefix("裸金属·") {
            key = String(typeName.dropFirst(3))
        }
        // 亮色板（Web 原色）；暗色略加深底、提亮字
        let light: (String, String, String)
        switch key {
        case "Ampere":
            light = ("f0fdf4", "15803d", "bbf7d0")
        case "AMD E5", "AMD E4", "AMD E3":
            light = ("eff6ff", "1d4ed8", "bfdbfe")
        case "AMD E2", "Intel 旧款", "裸金属":
            light = ("f8fafc", "64748b", "e2e8f0")
        case "Intel X9", "Intel X8", "Intel X7", "Intel", "Intel 高频":
            light = ("fdf4ff", "7e22ce", "e9d5ff")
        case "GPU", "HPC", "DenseIO A4 AX", "DenseIO":
            light = ("fff7ed", "c2410c", "fed7aa")
        case "MySQL":
            light = ("f0f9ff", "0369a1", "bae6fd")
        case "ADB", "DBCS", "Exadata":
            light = ("fef3c7", "92400e", "fde68a")
        case "NoSQL":
            light = ("f5f3ff", "6d28d9", "ddd6fe")
        default:
            light = ("f8fafc", "64748b", "e2e8f0")
        }
        if dark {
            return Colors(
                bg: Color(hex: light.0).opacity(0.18),
                fg: Color(hex: light.1).opacity(0.95),
                bd: Color(hex: light.2).opacity(0.35)
            )
        }
        return Colors(
            bg: Color(hex: light.0),
            fg: Color(hex: light.1),
            bd: Color(hex: light.2)
        )
    }
}
