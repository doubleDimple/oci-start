import SwiftUI

/// 原生对象存储（对齐 Web `/oci/storage/page` · `oci_object_storage.ftl`）。
struct StorageView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = StorageViewModel()

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        PageScaffold(
            title: "对象存储",
            subtitle: "OCI Object Storage · 存储桶与对象管理",
            systemImage: "externaldrive",
            toolbar: { toolbar },
            content: {
                VStack(spacing: 0) {
                    filterBar
                    if let err = model.errorText, !err.isEmpty {
                        errorBanner(err)
                    }
                    HStack(alignment: .top, spacing: 14) {
                        bucketPanel
                            .frame(minWidth: 260, idealWidth: 320, maxWidth: 380)
                        objectPanel
                            .frame(minWidth: 0, maxWidth: .infinity)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appLoading(model.isLoading)
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onAppear { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            Task { await model.reloadAll() }
        }
        .sheet(item: $model.activeSheet) { sheet in
            StorageSheetHost(sheet: sheet, model: model)
                .environmentObject(appearance)
        }
        .environmentObject(appearance)
    }

    // MARK: - Toolbar / filter

    private var toolbar: some View {
        HStack(spacing: 8) {
            AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) {
                Task { await model.reloadAll() }
            }
        }
    }

    private var filterBar: some View {
        FilterBar(
            leading: {
                HStack(spacing: 10) {
                    Text("租户")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.sidebarText(dark))
                    SelectMenu(
                        options: model.parentTenants.map {
                            SelectOption(id: $0.id, title: model.tenantLabel($0))
                        },
                        selection: Binding(
                            get: { model.selectedTenantId.isEmpty ? nil : model.selectedTenantId },
                            set: { model.onTenantChanged($0) }
                        ),
                        placeholder: "选择租户…",
                        width: 260,
                        allowClear: true
                    )
                }
            },
            trailing: {
                AppButton(title: "刷新桶", systemImage: "arrow.clockwise", kind: .secondary) {
                    model.refreshBuckets()
                }
            }
        )
    }

    private func errorBanner(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.system(size: 12))
            Spacer()
            Button("重试") { Task { await model.reloadAll() } }
                .buttonStyle(PlainButtonStyle())
        }
        .foregroundColor(Color(hex: "f85149"))
        .padding(12)
        .background(Color(hex: "f85149").opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Bucket panel

    private var bucketPanel: some View {
        panelCard {
            panelHeader(
                title: "存储桶",
                systemImage: "externaldrive.fill",
                trailing: {
                    AppButton(title: "创建", systemImage: "plus", kind: .primary) {
                        model.openCreateBucket()
                    }
                }
            )

            SearchField(
                text: $model.bucketSearch,
                placeholder: "搜索存储桶…",
                fillsWidth: true
            )

            Group {
                if model.bucketsLoading && model.buckets.isEmpty {
                    loadingBox
                } else if model.filteredBuckets.isEmpty {
                    EmptyStateView(
                        icon: "externaldrive",
                        title: model.selectedTenantId.isEmpty ? "请选择租户" : "暂无存储桶",
                        subtitle: model.selectedTenantId.isEmpty
                            ? "先在上方选择 OCI 租户"
                            : "点击「创建」新建存储桶"
                    )
                    .frame(minHeight: 180)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(model.filteredBuckets) { b in
                                bucketRow(b)
                                Divider().opacity(0.3)
                            }
                            if model.hasMoreBuckets && model.bucketSearch.trimmingCharacters(in: .whitespaces).isEmpty {
                                Button(action: { model.loadMoreBuckets() }) {
                                    HStack {
                                        Spacer()
                                        if model.bucketsLoading {
                                            ProgressView().scaleEffect(0.7)
                                        }
                                        Text("加载更多")
                                            .font(.system(size: 12, weight: .medium))
                                        Spacer()
                                    }
                                    .padding(.vertical, 10)
                                    .foregroundColor(AppTheme.sidebarActive)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func bucketRow(_ b: StorageBucketItem) -> some View {
        let active = model.selectedBucket?.name == b.name
        return HStack(alignment: .center, spacing: 8) {
            Button(action: { model.selectBucket(b) }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(b.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
                        .lineLimit(1)
                    if !b.createdText.isEmpty {
                        Text(b.createdText)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.sidebarText(dark))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            StatusBadge(text: b.accessLabel, tone: b.accessTone)

            Button(action: { model.deleteBucket(b) }) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "f85149"))
                    .padding(6)
                    .background(Color(hex: "f85149").opacity(0.12))
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(active ? AppTheme.sidebarActive.opacity(0.12) : Color.clear)
        .cornerRadius(6)
    }

    // MARK: - Object panel

    private var objectPanel: some View {
        panelCard {
            panelHeader(
                title: objectTitle,
                systemImage: "folder",
                trailing: {
                    if model.selectedBucket != nil {
                        HStack(spacing: 6) {
                            AppButton(title: "上传", systemImage: "arrow.up", kind: .primary) {
                                model.pickAndUpload()
                            }
                            AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) {
                                model.refreshObjects()
                            }
                        }
                    }
                }
            )

            Group {
                if model.selectedBucket == nil {
                    EmptyStateView(
                        icon: "hand.point.left",
                        title: "选择左侧存储桶",
                        subtitle: "查看并管理桶中的对象"
                    )
                    .frame(minHeight: 220)
                } else if model.objectsLoading && model.objects.isEmpty {
                    loadingBox
                } else if model.objects.isEmpty {
                    EmptyStateView(
                        icon: "doc",
                        title: "桶内暂无对象",
                        subtitle: "点击「上传」添加文件",
                        actionTitle: "上传文件",
                        action: { model.pickAndUpload() }
                    )
                    .frame(minHeight: 220)
                } else {
                    VStack(spacing: 0) {
                        objectHeader
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(model.objects) { o in
                                    objectRow(o)
                                    Divider().opacity(0.3)
                                }
                            }
                        }
                        objectPager
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var objectTitle: String {
        if let b = model.selectedBucket {
            return "对象 · \(b.name)"
        }
        return "对象"
    }

    private var objectHeader: some View {
        HStack(spacing: 0) {
            Text("名称").frame(maxWidth: .infinity, alignment: .leading)
            Text("大小").frame(width: 88, alignment: .trailing)
            Text("修改时间").frame(width: 130, alignment: .leading)
            Text("操作").frame(width: 160, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(AppTheme.sidebarText(dark))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.pageBg(dark).opacity(0.5))
    }

    private func objectRow(_ o: StorageObjectItem) -> some View {
        HStack(spacing: 0) {
            Text(o.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(o.name)

            Text(o.sizeText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(AppTheme.sidebarText(dark))
                .frame(width: 88, alignment: .trailing)

            Text(o.modifiedText)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.sidebarText(dark))
                .frame(width: 130, alignment: .leading)

            HStack(spacing: 4) {
                if o.isPreviewable {
                    iconBtn("eye", help: "预览") { model.previewObject(o) }
                }
                iconBtn("arrow.down", help: "下载") { model.downloadObject(o) }
                iconBtn("link", help: "预签名链接") { model.openPresigned(o) }
                iconBtn("trash", help: "删除", danger: true) { model.deleteObject(o) }
            }
            .frame(width: 160, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private func iconBtn(_ system: String, help: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(danger ? Color(hex: "f85149") : AppTheme.sidebarActive)
                .padding(6)
                .background(
                    (danger ? Color(hex: "f85149") : AppTheme.sidebarActive).opacity(0.12)
                )
                .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .help(help)
    }

    private var objectPager: some View {
        HStack(spacing: 10) {
            Text(model.objectPageLabel)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.sidebarText(dark))
            Spacer()
            Button(action: { model.objectPrevPage() }) {
                Label("上一页", systemImage: "chevron.left")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(model.objectPageIndex <= 0)
            .opacity(model.objectPageIndex <= 0 ? 0.35 : 1)

            Button(action: { model.objectNextPage() }) {
                HStack(spacing: 4) {
                    Text("下一页").font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!model.objectHasNext)
            .opacity(model.objectHasNext ? 1 : 0.35)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(AppTheme.border(dark).opacity(0.5)),
            alignment: .top
        )
    }

    // MARK: - Shared

    private func panelCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.sidebarBg(dark))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border(dark).opacity(0.7), lineWidth: 1)
        )
    }

    private func panelHeader<Trailing: View>(
        title: String,
        systemImage: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.sidebarActive)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
                .lineLimit(1)
            Spacer()
            trailing()
        }
    }

    private var loadingBox: some View {
        HStack {
            Spacer()
            ProgressView().scaleEffect(0.8)
            Text("加载中…")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarText(dark))
            Spacer()
        }
        .padding(.vertical, 48)
    }
}
