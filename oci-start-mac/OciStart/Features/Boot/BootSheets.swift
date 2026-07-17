import SwiftUI
import AppKit

/// Boot modals: detail list / edit config / web embed (add config).
struct BootSheetHost: View {
    let sheet: BootSheet
    @ObservedObject var model: BootViewModel
    @EnvironmentObject private var appearance: AppearanceController
    @EnvironmentObject private var session: AppSession
    @Environment(\.presentationMode) private var presentationMode

    private var dark: Bool { appearance.isDarkEffective }
    private var primaryText: Color { AppSheetSurface.primaryText(dark) }
    private var mutedText: Color { AppSheetSurface.mutedText(dark) }

    var body: some View {
        switch sheet {
        case .detail:
            detailSheet
        case .editDetail:
            editSheet
        case .embed(let title, let path, let query):
            embedSheet(title: title, path: path, query: query)
        }
    }

    private func chrome<Content: View, Footer: View>(
        title: String,
        systemImage: String? = nil,
        width: CGFloat = 720,
        height: CGFloat = 520,
        @ViewBuilder footer: () -> Footer,
        @ViewBuilder content: () -> Content
    ) -> some View {
        AppSheetChrome(
            title: title,
            systemImage: systemImage,
            width: width,
            height: height,
            fixedSize: true,
            onClose: { presentationMode.wrappedValue.dismiss() },
            footer: footer,
            content: content
        )
    }

    // MARK: - Detail

    private var detailSheet: some View {
        chrome(
            title: detailTitle,
            systemImage: "list.bullet.rectangle",
            width: 780,
            height: 520,
            footer: {
                HStack {
                    if let p = model.detailParent {
                        AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) {
                            Task { await model.loadDetail(p) }
                        }
                    }
                    Spacer()
                    AppButton(title: "关闭", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                }
            }
        ) {
            if model.detailLoading && model.detailItems.isEmpty {
                HStack {
                    Spacer()
                    ProgressView().scaleEffect(0.8)
                    Text("加载中…").font(.system(size: 12)).foregroundColor(mutedText)
                    Spacer()
                }
                .padding(.vertical, 40)
            } else if model.detailItems.isEmpty {
                EmptyStateView(icon: "tray", title: "暂无子任务", subtitle: "该组下没有开机配置")
                    .frame(minHeight: 200)
            } else {
                VStack(spacing: 0) {
                    detailHeader
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(model.detailItems) { d in
                                detailRow(d)
                                Divider().opacity(0.3)
                            }
                        }
                    }
                }
            }
        }
    }

    private var detailTitle: String {
        if let p = model.detailParent {
            return "开机详情 · \(p.displayTenant) · \(p.archText)"
        }
        return "开机详情"
    }

    private var detailHeader: some View {
        HStack(spacing: 8) {
            Group {
                col("昨日", 48)
                col("今日", 48)
                col("失败", 48)
                col("系统", 90)
                col("配置", 110)
            }
            Group {
                col("时段", 72)
                col("间隔", 48)
                col("密码", 72)
                col("状态", 64)
                col("创建", 110)
            }
            Text("操作")
                .frame(width: 120, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(mutedText)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppSheetSurface.surface2(dark))
    }

    private func col(_ t: String, _ w: CGFloat) -> some View {
        Text(t).frame(width: w, alignment: .leading)
    }

    private func detailRow(_ d: BootDetailItem) -> some View {
        HStack(spacing: 8) {
            Group {
                cell("\(d.yesterdayAttemptCount)", 48)
                cell("\(d.currentAttemptCount)", 48)
                cell("\(d.failCount)", 48)
                cell(d.osText, 90)
                cell(d.configText, 110)
            }
            Group {
                cell(d.dayGap.isEmpty ? "—" : d.dayGap, 72)
                cell("\(d.loopTime)s", 48)
                cell(d.rootPassword.isEmpty ? "—" : "••••••••", 72)
                StatusBadge(text: d.statusText, tone: d.statusTone)
                    .frame(width: 64, alignment: .leading)
                cell(d.createdAt.isEmpty ? "—" : String(d.createdAt.prefix(16)), 110)
            }
            HStack(spacing: 4) {
                miniBtn(d.status == 1 ? "停止" : "启动", danger: d.status == 1) {
                    model.toggleDetailStatus(d, start: d.status != 1)
                }
                miniBtn("改", danger: false) { model.openEditDetail(d) }
                miniBtn("删", danger: true) { model.deleteDetail(d) }
            }
            .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private func cell(_ t: String, _ w: CGFloat) -> some View {
        Text(t)
            .font(.system(size: 11))
            .foregroundColor(primaryText)
            .lineLimit(1)
            .frame(width: w, alignment: .leading)
    }

    private func miniBtn(_ title: String, danger: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(danger ? AppSheetSurface.accentRed(dark) : AppTheme.sidebarActive)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background((danger ? AppSheetSurface.accentRed(dark) : AppTheme.sidebarActive).opacity(0.12))
                .cornerRadius(5)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Edit

    private var editSheet: some View {
        chrome(title: "修改开机配置", systemImage: "slider.horizontal.3", width: 440, height: 420, footer: {
            HStack(spacing: 10) {
                AppButton(title: "取消", kind: .secondary) {
                    if let p = model.detailParent {
                        model.activeSheet = .detail(p)
                    } else {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                AppButton(title: "保存", kind: .primary, isLoading: model.formBusy) {
                    model.submitEditDetail()
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                FormFieldRow(label: "OCPU", required: true) {
                    AppTextField(text: $model.editOcpu, placeholder: "1")
                }
                FormFieldRow(label: "内存 (GB)", required: true) {
                    AppTextField(text: $model.editMemory, placeholder: "6")
                }
                FormFieldRow(label: "磁盘 (GB)", required: true) {
                    AppTextField(text: $model.editDisk, placeholder: "50")
                }
                FormFieldRow(label: "循环间隔 (秒)", required: true) {
                    AppTextField(text: $model.editLoopTime, placeholder: "60")
                }
                FormFieldRow(label: "时段范围") {
                    AppTextField(text: $model.editDayGap, placeholder: "如 08:00-22:00")
                }
                FormFieldRow(label: "Root 密码", required: true) {
                    AppTextField(text: $model.editPassword, placeholder: "root 密码")
                }
                if let err = model.formError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(AppSheetSurface.accentRed(dark))
                }
            }
        }
    }

    // MARK: - Embed

    private func embedSheet(title: String, path: String, query: [String: String]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("关闭") { presentationMode.wrappedValue.dismiss() }
                    .buttonStyle(PlainButtonStyle())
            }
            .padding(12)
            BootEmbedRepresentable(session: session, path: path, query: query, title: title)
                .frame(minWidth: 860, minHeight: 560)
        }
        .frame(width: 900, height: 620)
    }
}

/// Thin AppKit host for WebEmbedViewController inside SwiftUI sheet.
private struct BootEmbedRepresentable: NSViewControllerRepresentable {
    let session: AppSession
    let path: String
    let query: [String: String]
    let title: String

    func makeNSViewController(context: Context) -> WebEmbedViewController {
        WebEmbedViewController(session: session, path: path, query: query, title: title)
    }

    func updateNSViewController(_ nsViewController: WebEmbedViewController, context: Context) {}
}
