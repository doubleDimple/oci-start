import SwiftUI
import AppKit

/// Storage modals: create bucket / presigned URL / upload progress.
struct StorageSheetHost: View {
    let sheet: StorageSheet
    @ObservedObject var model: StorageViewModel
    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.presentationMode) private var presentationMode

    private var dark: Bool { appearance.isDarkEffective }
    private var primaryText: Color { AppSheetSurface.primaryText(dark) }
    private var mutedText: Color { AppSheetSurface.mutedText(dark) }

    var body: some View {
        switch sheet {
        case .createBucket:
            createBucketSheet
        case .presigned:
            presignedSheet
        case .uploadProgress:
            uploadSheet
        }
    }

    private func chrome<Content: View, Footer: View>(
        title: String,
        systemImage: String? = nil,
        width: CGFloat = 440,
        height: CGFloat = 320,
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

    // MARK: - Create bucket

    private var createBucketSheet: some View {
        chrome(title: "创建存储桶", systemImage: "externaldrive.badge.plus", width: 440, height: 300, footer: {
            HStack(spacing: 10) {
                AppButton(title: "取消", kind: .secondary) { presentationMode.wrappedValue.dismiss() }
                AppButton(title: "创建", kind: .primary, isLoading: model.formBusy) {
                    model.submitCreateBucket()
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                FormFieldRow(label: "桶名称", required: true) {
                    AppTextField(text: $model.newBucketName, placeholder: "my-bucket-name")
                }
                FormFieldRow(label: "访问类型") {
                    SelectMenu(
                        options: StorageAccessType.allCases.map {
                            SelectOption(id: $0.rawValue, title: $0.title)
                        },
                        selection: Binding(
                            get: { model.newBucketAccess.rawValue },
                            set: { raw in
                                if let raw = raw, let v = StorageAccessType(rawValue: raw) {
                                    model.newBucketAccess = v
                                }
                            }
                        ),
                        placeholder: "选择访问类型",
                        width: 280,
                        allowClear: false
                    )
                }
                if let err = model.formError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(AppSheetSurface.accentRed(dark))
                }
                Text("名称需全局唯一，仅小写字母、数字、连字符。")
                    .font(.system(size: 11))
                    .foregroundColor(mutedText)
            }
        }
    }

    // MARK: - Presigned

    private var presignedSheet: some View {
        chrome(title: "预签名链接", systemImage: "link", width: 520, height: 280, footer: {
            HStack(spacing: 10) {
                AppButton(title: "复制", kind: .secondary, enabled: !model.presignedURLText.isEmpty) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.presignedURLText, forType: .string)
                    AppAlert.info(title: "已复制", message: "预签名链接已复制到剪贴板")
                }
                AppButton(title: "关闭", kind: .primary) { presentationMode.wrappedValue.dismiss() }
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                Text("链接有效期约 1 小时。已自动复制到剪贴板。")
                    .font(.system(size: 12))
                    .foregroundColor(mutedText)
                if model.presignedURLText.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView().scaleEffect(0.8)
                        Text("生成中…")
                            .font(.system(size: 12))
                            .foregroundColor(mutedText)
                        Spacer()
                    }
                    .padding(.vertical, 24)
                } else {
                    ScrollView {
                        Text(model.presignedURLText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                    .padding(10)
                    .background(AppSheetSurface.surface2(dark))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Upload

    private var uploadSheet: some View {
        chrome(title: "上传文件", systemImage: "arrow.up.circle", width: 480, height: 420, footer: {
            HStack(spacing: 10) {
                if model.uploadFinished {
                    AppButton(title: "完成", kind: .primary) { model.closeUploadSheet() }
                } else {
                    AppButton(title: "取消", kind: .secondary) { model.cancelUpload() }
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.uploadTasks) { task in
                            uploadRow(task)
                        }
                    }
                }
                .frame(maxHeight: 260)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("总体进度")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(mutedText)
                        Spacer()
                        Text("\(model.uploadOverallPercent)%")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(primaryText)
                    }
                    progressBar(model.uploadOverallPercent, failed: false)
                }
            }
        }
    }

    private func uploadRow(_ task: StorageUploadTask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(task.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(primaryText)
                    .lineLimit(1)
                Spacer()
                Text(task.statusText)
                    .font(.system(size: 11))
                    .foregroundColor(task.failed ? AppSheetSurface.accentRed(dark) : mutedText)
            }
            progressBar(task.percent, failed: task.failed)
        }
    }

    private func progressBar(_ percent: Int, failed: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.border(dark).opacity(0.5))
                Capsule()
                    .fill(failed ? AppSheetSurface.accentRed(dark) : AppTheme.sidebarActive)
                    .frame(width: max(4, geo.size.width * CGFloat(min(100, max(0, percent))) / 100))
            }
        }
        .frame(height: 5)
    }
}
