import SwiftUI

// MARK: - Models from dynamic API maps

struct DnsZoneItem: Identifiable, Hashable {
    let id: String
    let name: String

    init?(dict: [String: Any]) {
        let id = (dict["id"] as? String)
            ?? (dict["zoneId"] as? String)
            ?? (dict["zone_id"] as? String)
            ?? ""
        let name = (dict["name"] as? String)
            ?? (dict["domain"] as? String)
            ?? (dict["zoneName"] as? String)
            ?? ""
        guard !id.isEmpty else { return nil }
        self.id = id
        self.name = name.isEmpty ? id : name
    }
}

struct DnsRecordItem: Identifiable, Hashable {
    let id: String
    let type: String
    let name: String
    let content: String
    let ttl: Int
    let proxied: Bool?

    init?(dict: [String: Any]) {
        let id = (dict["id"] as? String)
            ?? (dict["recordId"] as? String)
            ?? (dict["RecordId"] as? String)
            ?? ""
        guard !id.isEmpty else { return nil }
        self.id = id
        self.type = (dict["type"] as? String)
            ?? (dict["recordType"] as? String)
            ?? (dict["Type"] as? String)
            ?? "—"
        self.name = (dict["name"] as? String)
            ?? (dict["recordName"] as? String)
            ?? (dict["Name"] as? String)
            ?? "—"
        self.content = (dict["content"] as? String)
            ?? (dict["value"] as? String)
            ?? (dict["Content"] as? String)
            ?? "—"
        if let t = dict["ttl"] as? Int {
            self.ttl = t
        } else if let t = dict["ttl"] as? String, let v = Int(t) {
            self.ttl = v
        } else if let t = dict["TTL"] as? Int {
            self.ttl = t
        } else {
            self.ttl = 1
        }
        if let p = dict["proxied"] as? Bool {
            self.proxied = p
        } else if let p = dict["proxied"] as? String {
            self.proxied = (p == "true" || p == "1")
        } else {
            self.proxied = nil
        }
    }
}

// MARK: - Row

struct DnsRecordRowView: View {
    @Environment(\.colorScheme) private var scheme
    let record: DnsRecordItem
    var showProxied: Bool = false
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(record.type)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppTheme.accent(scheme))
                .frame(width: 70, alignment: .leading)
            Text(record.name)
                .lineLimit(1)
                .foregroundColor(AppTheme.text(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(record.content)
                .lineLimit(1)
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(AppTheme.muted(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(record.ttl == 1 ? "Auto" : "\(record.ttl)")
                .font(.caption)
                .foregroundColor(AppTheme.muted(scheme))
                .frame(width: 60, alignment: .leading)
            if showProxied {
                Image(systemName: (record.proxied == true) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor((record.proxied == true) ? AppTheme.success : AppTheme.muted(scheme))
                    .font(.caption)
                    .frame(width: 50, alignment: .center)
            }
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil").foregroundColor(AppTheme.accent(scheme))
                }.buttonStyle(.plain)
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundColor(AppTheme.danger)
                }.buttonStyle(.plain)
            }
            .frame(width: 90, alignment: .center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Edit / Add sheet

struct DnsEditSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let title: String
    let zoneId: String
    let zoneName: String
    let initial: DnsRecordItem?
    var showProxied: Bool = false
    let onSave: (String, String, String, Int, Bool) async throws -> ActionResponse
    let onDone: () -> Void

    @State private var type = "A"
    @State private var name = ""
    @State private var content = ""
    @State private var ttl = "1"
    @State private var proxied = false
    @State private var saving = false
    @State private var errorText: String?

    private let types = ["A", "AAAA", "CNAME", "TXT", "MX", "NS", "SRV"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3.weight(.semibold)).foregroundColor(AppTheme.text(scheme))
            Text("域名：\(zoneName)")
                .font(.caption).foregroundColor(AppTheme.muted(scheme))

            Picker("类型", selection: $type) {
                ForEach(types, id: \.self) { Text($0).tag($0) }
            }
            TextField("名称（如 www 或 @）", text: $name).textFieldStyle(.roundedBorder)
            TextField("内容 / 值", text: $content).textFieldStyle(.roundedBorder)
            TextField("TTL（1=Auto）", text: $ttl).textFieldStyle(.roundedBorder)
            if showProxied {
                Toggle("Cloudflare 代理", isOn: $proxied)
            }
            if let errorText = errorText {
                Text(errorText).font(.caption).foregroundColor(AppTheme.danger)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss.wrappedValue.dismiss(); onDone() }
                Button(action: { Task { await save() } }) {
                    Text(saving ? "保存中…" : "保存")
                }
                .buttonStyle(ProminentButton())
                .disabled(saving || name.isEmpty || content.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(22)
        .frame(width: 400)
        .onAppear {
            if let i = initial {
                type = i.type
                name = i.name
                content = i.content
                ttl = "\(i.ttl)"
                proxied = i.proxied ?? false
            }
        }
    }

    private func save() async {
        saving = true
        errorText = nil
        defer { saving = false }
        let ttlVal = Int(ttl) ?? 1
        do {
            let r = try await onSave(type, name, content, ttlVal, proxied)
            if r.success == false {
                errorText = r.message ?? "保存失败"
                return
            }
            appState.showToast(r.message ?? "已保存")
            dismiss.wrappedValue.dismiss()
            onDone()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
