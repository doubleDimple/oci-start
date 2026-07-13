import SwiftUI

/// Web-parity page for `/resource/list` (`arm_records.ftl` + `arm_records.js`).
/// Title on web: 开机区域监控（侧栏「OCI区域管理」/ Mac「区域订阅」）.
struct RegionsView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = RegionsViewModel()

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let err = model.errorText, !err.isEmpty {
                    errorBanner(err)
                }
                statsGrid
                mapCard
                listCard
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(RegionsTheme.bg(dark).ignoresSafeArea())
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            Task { await model.refresh() }
        }
        .environmentObject(appearance)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: "4d9eff").opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(RegionsTheme.blue(dark))
                }
                Text("开机区域监控")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(RegionsTheme.text(dark))
            }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(RegionsTheme.green(dark)).frame(width: 7, height: 7)
                Text(model.lastUpdateText)
                    .font(.system(size: 12))
                    .foregroundColor(RegionsTheme.muted(dark))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(RegionsTheme.surface2(dark)))
            .overlay(Capsule().stroke(RegionsTheme.border(dark), lineWidth: 1))
        }
        .padding(.bottom, 8)
        .overlay(Rectangle().fill(RegionsTheme.border(dark)).frame(height: 1), alignment: .bottom)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.system(size: 12))
            Spacer()
            Button("重试") { Task { await model.refresh() } }
                .buttonStyle(PlainButtonStyle())
        }
        .foregroundColor(RegionsTheme.red(dark))
        .padding(12)
        .background(RegionsTheme.red(dark).opacity(0.1))
        .cornerRadius(10)
    }

    // MARK: - Stats

    private var statsGrid: some View {
        HStack(spacing: 14) {
            statCard(icon: "mappin.and.ellipse", color: RegionsTheme.blue(dark),
                     title: "总区域数", value: "\(model.totalRegions)")
            statCard(icon: "cpu", color: RegionsTheme.green(dark),
                     title: "已开ARM架构区域数", value: "\(model.openArmCount)")
            statCard(icon: "bell.fill", color: RegionsTheme.orange(dark),
                     title: "今日新开机区域数", value: "\(model.todayNewCount)")
        }
    }

    private func statCard(icon: String, color: Color, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(color)
                }
                Spacer()
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(RegionsTheme.muted(dark))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(RegionsTheme.text(dark))
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .background(RegionsTheme.surface2(dark))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(RegionsTheme.border(dark), lineWidth: 1))
        .cornerRadius(12)
    }

    // MARK: - Map board (native stand-in for Leaflet)

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(RegionsTheme.green(dark).opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: "globe")
                        .foregroundColor(RegionsTheme.green(dark))
                }
                Text("数量: \(model.mapCount)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(RegionsTheme.text(dark))

                Spacer(minLength: 8)

                HStack(spacing: 0) {
                    mapToggle("ARM放货区域", mode: .arm)
                    mapToggle("我的区域", mode: .mine)
                }
                .background(RegionsTheme.surface(dark))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(RegionsTheme.border(dark), lineWidth: 1))

                Button(action: { model.showMapBoard.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: model.showMapBoard ? "map.fill" : "map")
                        Text(model.showMapBoard ? "隐藏地图" : "显示地图")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(model.showMapBoard ? .white : RegionsTheme.text(dark))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(model.showMapBoard ? RegionsTheme.blue(dark) : RegionsTheme.surface(dark))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(RegionsTheme.border(dark), lineWidth: model.showMapBoard ? 0 : 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }

            if model.showMapBoard {
                regionBoard
            }
        }
        .padding(18)
        .background(RegionsTheme.surface2(dark))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(RegionsTheme.border(dark), lineWidth: 1))
        .cornerRadius(12)
    }

    private func mapToggle(_ title: String, mode: RegionsMapViewMode) -> some View {
        Button(action: { model.mapMode = mode }) {
            Text(title)
                .font(.system(size: 12, weight: model.mapMode == mode ? .semibold : .regular))
                .foregroundColor(model.mapMode == mode ? .white : RegionsTheme.muted(dark))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(model.mapMode == mode ? RegionsTheme.blue(dark) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var regionBoard: some View {
        let openSet = Set(model.openRecords.filter { $0.openCount > 0 }.map(\.region))
        let mineSet = Set(model.myRecords.map(\.region))
        let groups: [(String, [String])] = [
            ("亚太", KnownRegions.codes.filter { $0.hasPrefix("ap-") }),
            ("欧洲/英国", KnownRegions.codes.filter { $0.hasPrefix("eu-") || $0.hasPrefix("uk-") || $0.hasPrefix("il-") }),
            ("北美", KnownRegions.codes.filter { $0.hasPrefix("us-") || $0.hasPrefix("ca-") || $0.hasPrefix("mx-") }),
            ("南美", KnownRegions.codes.filter { $0.hasPrefix("sa-") }),
            ("中东/非洲", KnownRegions.codes.filter { $0.hasPrefix("me-") || $0.hasPrefix("af-") })
        ]

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                legendDot(RegionsTheme.orange(dark), "已放货")
                legendDot(RegionsTheme.green(dark), "我的区域")
                legendDot(RegionsTheme.muted(dark).opacity(0.45), "未放货")
                Spacer()
                Text("原生区域状态板（Web 端为 Leaflet 地图）")
                    .font(.system(size: 11))
                    .foregroundColor(RegionsTheme.muted(dark))
            }
            ForEach(groups, id: \.0) { title, codes in
                if !codes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(RegionsTheme.muted(dark))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                            ForEach(codes, id: \.self) { code in
                                let name = model.regionMap[code] ?? code
                                let isOpen = openSet.contains(code)
                                let isMine = mineSet.contains(code)
                                let active: Bool = {
                                    switch model.mapMode {
                                    case .arm: return isOpen
                                    case .mine: return isMine
                                    }
                                }()
                                let color: Color = {
                                    if model.mapMode == .mine && isMine { return RegionsTheme.green(dark) }
                                    if model.mapMode == .arm && isOpen { return RegionsTheme.orange(dark) }
                                    return RegionsTheme.muted(dark).opacity(0.35)
                                }()
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(color)
                                        .frame(width: active ? 10 : 8, height: active ? 10 : 8)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(name)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(RegionsTheme.text(dark))
                                            .lineLimit(1)
                                        Text(code)
                                            .font(.system(size: 10))
                                            .foregroundColor(RegionsTheme.muted(dark))
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(8)
                                .background(RegionsTheme.surface(dark))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(active ? color.opacity(0.5) : RegionsTheme.border(dark), lineWidth: 1)
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func legendDot(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.system(size: 11)).foregroundColor(RegionsTheme.muted(dark))
        }
    }

    // MARK: - List

    private var listCard: some View {
        // ZStack so filter dropdown can float above the table without pushing rows.
        ZStack(alignment: .topLeading) {
            // Table block (full card content, with top inset for the filter row)
            VStack(alignment: .leading, spacing: 0) {
                // Spacer matching filter row height
                Color.clear
                    .frame(height: AppInputStyle.height + 14)

                HStack(spacing: 0) {
                    col("状态", 80)
                    col("区域代码", 140)
                    col("区域名称", 140)
                    col("架构类型", 90)
                    col("开机时间", 140)
                    col("总开机数量", 90)
                    col("当月开机数量", 100)
                    col("最后开机时间", 140)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .background(RegionsTheme.surface(dark))
                .overlay(Rectangle().fill(RegionsTheme.border(dark)).frame(height: 1), alignment: .bottom)

                if model.pageRows.isEmpty {
                    Text(model.isLoading ? "加载中..." : "没有找到匹配的区域")
                        .font(.system(size: 13))
                        .foregroundColor(RegionsTheme.muted(dark))
                        .frame(maxWidth: .infinity)
                        .padding(40)
                } else {
                    ForEach(model.pageRows) { row in
                        HStack(spacing: 0) {
                            StatusBadge(text: row.isOpen ? "已放货" : "未放货",
                                        tone: row.isOpen ? .success : .neutral)
                                .frame(width: 80, alignment: .leading)
                            cell(row.regionCode, 140)
                            cell(row.name, 140)
                            cell(row.architectureType, 90)
                            cell(Self.fmt(row.openTime), 140)
                            cell("\(row.openCount)", 90)
                            cell("\(row.monthlyOpenCount)", 100)
                            cell(Self.fmt(row.lastNotifyTime), 140)
                        }
                        .padding(.vertical, 11)
                        .padding(.horizontal, 8)
                        .overlay(Rectangle().fill(RegionsTheme.border(dark).opacity(0.6)).frame(height: 1), alignment: .bottom)
                    }
                }

                // Common drop-in pagination (SelectMenu size + AppInputStyle jump)
                PaginationBar(state: $model.pageState) {
                    model.goPage { _ in }
                }
                .padding(.top, 8)
            }

            // Filter row on top layer — SelectMenu panel floats over the table
            HStack(alignment: .top, spacing: 10) {
                SearchField(
                    text: $model.searchText,
                    placeholder: "搜索区域...",
                    maxWidth: 260
                )

                SelectMenu(
                    options: continentOptions,
                    selection: continentSelection,
                    placeholder: "全部大洲",
                    width: 132,
                    allowClear: false
                )
                SelectMenu(
                    options: statusOptions,
                    selection: statusSelection,
                    placeholder: "全部状态",
                    width: 120,
                    allowClear: false
                )

                Spacer(minLength: 0)
                if model.isLoading {
                    ProgressView().scaleEffect(0.7)
                        .frame(width: 20, height: AppInputStyle.height)
                }
            }
            .zIndex(50)
        }
        .padding(18)
        // Background without .cornerRadius (that clips floating menus)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(RegionsTheme.surface2(dark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(RegionsTheme.border(dark), lineWidth: 1)
        )
    }

    private var continentOptions: [SelectOption] {
        RegionContinent.allCases.map { SelectOption(id: $0.rawValue, title: $0.title) }
    }

    private var statusOptions: [SelectOption] {
        RegionStatusFilter.allCases.map { SelectOption(id: $0.rawValue, title: $0.title) }
    }

    private var continentSelection: Binding<String?> {
        Binding(
            get: { model.continent.rawValue },
            set: { raw in
                if let raw = raw, let c = RegionContinent(rawValue: raw) {
                    model.continent = c
                } else {
                    model.continent = .all
                }
            }
        )
    }

    private var statusSelection: Binding<String?> {
        Binding(
            get: { model.statusFilter.rawValue },
            set: { raw in
                if let raw = raw, let s = RegionStatusFilter(rawValue: raw) {
                    model.statusFilter = s
                } else {
                    model.statusFilter = .all
                }
            }
        )
    }

    private func col(_ title: String, _ w: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(RegionsTheme.muted(dark))
            .frame(width: w, alignment: .leading)
    }

    private func cell(_ text: String, _ w: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(RegionsTheme.text(dark))
            .lineLimit(1)
            .frame(width: w, alignment: .leading)
    }

    private static func fmt(_ s: String?) -> String {
        guard let s = s, !s.isEmpty else { return "--" }
        return s
    }
}

// MARK: - Theme (arm_records.css)

enum RegionsTheme {
    static func bg(_ dark: Bool) -> Color { dark ? Color(hex: "1a1d21") : Color(hex: "f0f2f5") }
    static func surface(_ dark: Bool) -> Color { dark ? Color(hex: "22262b") : Color.white }
    static func surface2(_ dark: Bool) -> Color { dark ? Color(hex: "292d32") : Color(hex: "f8fafc") }
    static func border(_ dark: Bool) -> Color { dark ? Color(hex: "31363d") : Color(hex: "e8ecf0") }
    static func text(_ dark: Bool) -> Color { dark ? Color(hex: "cdd9e5") : Color(hex: "111827") }
    static func muted(_ dark: Bool) -> Color { dark ? Color(hex: "768390") : Color(hex: "4b5563") }
    static func blue(_ dark: Bool) -> Color { dark ? Color(hex: "4d9eff") : Color(hex: "3b82f6") }
    static func green(_ dark: Bool) -> Color { dark ? Color(hex: "3fb950") : Color(hex: "22c55e") }
    static func orange(_ dark: Bool) -> Color { dark ? Color(hex: "f78166") : Color(hex: "f97316") }
    static func red(_ dark: Bool) -> Color { dark ? Color(hex: "ff6b6b") : Color(hex: "ef4444") }
}
