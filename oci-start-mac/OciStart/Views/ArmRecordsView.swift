import SwiftUI

struct ArmRecordsView: View {
    @EnvironmentObject var appState: AppState
    @State private var records: [ArmRegionRecord] = []
    @State private var isLoading = false
    @State private var searchText = ""

    var filtered: [ArmRegionRecord] {
        guard !searchText.isEmpty else { return records }
        let q = searchText.lowercased()
        return records.filter {
            ($0.region?.lowercased().contains(q) ?? false) ||
            ($0.regionName?.lowercased().contains(q) ?? false) ||
            ($0.status?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.callout)
                TextField("搜索区域…", text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            // Column headers
            HStack(spacing: 0) {
                Text("区域代码").frame(width: 160, alignment: .leading)
                Text("区域名称").frame(maxWidth: .infinity, alignment: .leading)
                Text("状态").frame(width: 120, alignment: .leading)
                Text("时间").frame(width: 160, alignment: .leading)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .font(.caption.weight(.semibold)).foregroundColor(.secondary)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if isLoading && records.isEmpty {
                VStack { Spacer(); ProgressView("加载中…"); Spacer() }
            } else if filtered.isEmpty {
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "map").font(.largeTitle).foregroundColor(.secondary)
                        Text(records.isEmpty ? "暂无 ARM 区域记录" : "无匹配结果").foregroundColor(.secondary)
                    }
                    Spacer()
                }
            } else {
                List(filtered) { record in
                    ArmRecordRow(record: record)
                        .listRowInsets(EdgeInsets())
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("ARM 区域")
        .toolbar {
            ToolbarItem {
                Text("\(filtered.count) 条").font(.caption).foregroundColor(.secondary)
            }
            ToolbarItem {
                if isLoading { ProgressView().scaleEffect(0.75) }
            }
            ToolbarItem {
                Button(action: load) { Label("刷新", systemImage: "arrow.clockwise") }
                    .disabled(isLoading)
            }
        }
        .onAppear { if records.isEmpty { load() } }
    }

    private func load() {
        isLoading = true
        Task {
            records = (try? await appState.network.getArmData(baseURL: appState.serverURL)) ?? []
            isLoading = false
        }
    }
}

struct ArmRecordRow: View {
    let record: ArmRegionRecord

    var body: some View {
        HStack(spacing: 0) {
            Text(record.region ?? "—")
                .font(.system(.callout, design: .monospaced))
                .frame(width: 160, alignment: .leading)

            Text(record.regionName ?? "—")
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(record.status ?? "—").font(.caption)
            }
            .frame(width: 120, alignment: .leading)

            Text(record.createTime.map { String($0.prefix(10)) } ?? "—")
                .font(.caption).foregroundColor(.secondary)
                .frame(width: 160, alignment: .leading)
        }
        .padding(.vertical, 8).padding(.horizontal, 16)
    }

    private var statusColor: Color {
        switch record.status?.uppercased() {
        case "SUCCESS", "AVAILABLE": return .green
        case "FAIL", "ERROR":       return .red
        default:                    return .orange
        }
    }
}
