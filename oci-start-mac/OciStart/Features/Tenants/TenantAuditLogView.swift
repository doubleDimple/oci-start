import SwiftUI

/// 租户审计日志整页 — 对应 Web `auditLogModal`，从租户列表进入，非弹框。
/// 列对齐 Web：# / 用户 / 来源 IP / 事件 / 客户端环境 / 时间 / 状态
/// 分页：统一 `PaginationBar`（OCI token 游标，无每页条数选择）
struct TenantAuditLogView: View {
    @ObservedObject var model: TenantsViewModel
    @EnvironmentObject private var appearance: AppearanceController

    private var dark: Bool { appearance.isDarkEffective }
    private var tenant: TenantItem? { model.auditParent }

    private let wIndex: CGFloat = 44
    private let wUser: CGFloat = 120
    private let wIP: CGFloat = 120
    private let wTime: CGFloat = 150
    private let wStatus: CGFloat = 72
    private let minEvent: CGFloat = 140
    private let minEnv: CGFloat = 120
    private let hPad: CGFloat = 12

    var body: some View {
        PageScaffold(
            title: "审计日志",
            subtitle: tenant.map { "\($0.displayName) · \($0.region.isEmpty ? "—" : $0.region)" },
            systemImage: "doc.text",
            toolbar: { EmptyView() },
            content: {
                VStack(spacing: 0) {
                    filterBar
                    if let err = model.auditError, !err.isEmpty {
                        errorBanner(err)
                    }
                    listBody
                    if shouldShowPagination {
                        PaginationBar(
                            state: $model.auditPageState,
                            showsSizeSelector: false,
                            showsJump: true,
                            rangeTextOverride: model.auditRangeText
                        ) {
                            model.onAuditPageChange()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    private var shouldShowPagination: Bool {
        // 有数据，或已发现多页 / 仍有下一页时展示
        !model.auditPageItems.isEmpty
            || model.auditPageState.totalPages > 1
            || model.auditHasMore
            || model.auditPageState.page > 0
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            if let selectedTenant = tenant {
                Text("审计日志 · \(selectedTenant.displayName) · \(selectedTenant.region.isEmpty ? "—" : selectedTenant.region)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary(dark))
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)
            }
            AppButton(title: "返回列表", systemImage: "chevron.left", kind: .secondary) {
                model.closeAudit()
            }
            AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) {
                model.reloadAudit()
            }
            if model.auditLoading {
                ProgressView().scaleEffect(0.7)
            }
        }
    }

    // MARK: - Filter

    private var filterBar: some View {
        FilterBar(
            leading: {
                HStack(spacing: 8) {
                    Text("开始")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary(dark))
                    AppTextField(text: $model.auditStart, placeholder: "yyyy-MM-dd")
                        .frame(width: 140)
                    Text("结束")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary(dark))
                    AppTextField(text: $model.auditEnd, placeholder: "yyyy-MM-dd")
                        .frame(width: 140)
                    Text("最多查询近 90 天")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary(dark))
                }
            },
            trailing: {
                toolbar
                AppButton(title: "查询", systemImage: "magnifyingglass", kind: .primary) {
                    guard let t = tenant else { return }
                    model.searchAudit(t)
                }
            }
        )
    }

    private func errorBanner(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.system(size: 14))
            Spacer()
            Button("重试") {
                model.reloadAudit()
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
        if model.auditLoading && model.auditPageItems.isEmpty {
            VStack {
                Spacer()
                ProgressView()
                Text("加载审计日志…")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary(dark))
                    .padding(.top, 8)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.auditPageItems.isEmpty {
            EmptyStateView(
                icon: "doc.text.magnifyingglass",
                title: "暂无日志",
                subtitle: "当前日期范围内没有审计事件，可调整起止日期后重试",
                actionTitle: "返回列表",
                action: { model.closeAudit() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geo in
                let fixed = wIndex + wUser + wIP + wTime + wStatus + minEvent + minEnv + hPad * 2
                let totalW = max(geo.size.width, fixed)
                let flex = max(0, totalW - fixed)
                let wEvent = minEvent + flex * 0.55
                let wEnv = minEnv + flex * 0.45

                NativeHorizontalTable(contentWidth: totalW, viewportWidth: geo.size.width, height: geo.size.height) {
                    VStack(spacing: 0) {
                        headerRow(wEvent: wEvent, wEnv: wEnv, width: totalW)
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(model.auditPageItems.enumerated()), id: \.offset) { idx, log in
                                    dataRow(
                                        index: model.auditRowStart + idx - 1,
                                        displayIndex: model.auditRowStart + idx,
                                        log: log,
                                        wEvent: wEvent,
                                        wEnv: wEnv,
                                        width: totalW
                                    )
                                }
                            }
                        }
                    }
                    .frame(width: totalW, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func headerRow(wEvent: CGFloat, wEnv: CGFloat, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            colHeader("#", wIndex)
            colHeader("用户", wUser)
            colHeader("来源 IP", wIP)
            colHeader("事件", wEvent)
            colHeader("客户端环境", wEnv)
            colHeader("时间", wTime)
            colHeader("状态", wStatus, align: .center)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .background(AppTheme.hover(dark).opacity(0.65))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.5)),
            alignment: .bottom
        )
    }

    private func dataRow(
        index: Int,
        displayIndex: Int,
        log: TenantAuditLogEntry,
        wEvent: CGFloat,
        wEnv: CGFloat,
        width: CGFloat
    ) -> some View {
        let errorTint = Color(hex: "f85149").opacity(dark ? 0.12 : 0.08)
        let stripe = index % 2 == 1 ? AppTheme.hover(dark).opacity(0.18) : Color.clear
        return HStack(spacing: 0) {
            cell("\(displayIndex)", wIndex, muted: true)
            cell(display(log.userName), wUser)
            cell(display(log.ipAddress), wIP, muted: true)
            cell(display(log.eventType), wEvent, bold: true)
            cell(display(log.clientEnv), wEnv, muted: true)
            cell(display(log.eventTime), wTime, muted: true)
            statusCell(log)
                .frame(width: wStatus, alignment: .center)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
        .background(log.isError ? errorTint : stripe)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.3)),
            alignment: .bottom
        )
    }

    private func statusCell(_ log: TenantAuditLogEntry) -> some View {
        let text = log.responseStatus.isEmpty ? "—" : log.responseStatus
        let tone: StatusTone = log.isError ? .danger : (log.responseStatus == "200" ? .success : .neutral)
        return StatusBadge(text: text, tone: tone)
    }

    private func display(_ s: String) -> String {
        s.isEmpty ? "—" : s
    }

    private func colHeader(_ title: String, _ w: CGFloat, align: Alignment = .leading) -> some View {
        Text(title)
            .lineLimit(1)
            .font(.system(size: AppTheme.bodySize, weight: .semibold))
            .foregroundColor(AppTheme.textSecondary(dark))
            .frame(width: w, alignment: align)
    }

    private func cell(_ text: String, _ w: CGFloat, muted: Bool = false, bold: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 14, weight: bold ? .semibold : .regular))
            .foregroundColor(
                muted
                    ? AppTheme.textSecondary(dark)
                    : (AppTheme.textPrimary(dark))
            )
            .lineLimit(1)
            .help(text)
            .frame(width: w, alignment: .leading)
    }
}
