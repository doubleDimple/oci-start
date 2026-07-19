import Foundation

/// 对齐 Web `vps_list.ftl` / `VpsController`。
struct VpsService {
    let baseURL: String
    private let client = APIClient.shared

    /// 与 Web 同源：一次拉全量（Web 默认 size=1000）
    func listAll() async throws -> InstancesListResponse {
        let url = try client.makeURL(baseURL, path: "/oci/list/json", query: [
            "page": "0",
            "size": "1000"
        ])
        let raw = try await client.getJSON(url)
        return try InstanceJSON.parseList(raw)
    }

    func enablePing() async throws -> String {
        let url = try client.makeURL(baseURL, path: "/vps/instances/enablePing")
        let raw = try await client.postJSON(url, body: [:])
        return InstanceJSON.successMessage(raw, fallback: "已开启自动 Ping").message
    }

    func disablePing() async throws -> String {
        let url = try client.makeURL(baseURL, path: "/vps/instances/disablePing")
        let raw = try await client.postJSON(url, body: [:])
        return InstanceJSON.successMessage(raw, fallback: "已停止自动 Ping").message
    }

    func manualPing() async throws -> String {
        let url = try client.makeURL(baseURL, path: "/vps/instances/ping")
        let raw = try await client.postJSON(url, body: [:])
        return InstanceJSON.successMessage(raw, fallback: "Ping 检测已下发").message
    }

    func installMonitor(vpsId: String) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/api/monitor/install")
        let (data, http) = try await client.postForm(url, fields: ["vpsId": vpsId])
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.serverMessage("HTTP \(http.statusCode)")
        }
        return InstanceJSON.successMessage(data, fallback: "安装指令已发送").message
    }

    func uninstallMonitor(vpsId: String) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/api/monitor/uninstall")
        let (data, http) = try await client.postForm(url, fields: ["vpsId": vpsId])
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.serverMessage("HTTP \(http.statusCode)")
        }
        return InstanceJSON.successMessage(data, fallback: "卸载指令已发送").message
    }

    /// 本机 `ping -c 1` 测延迟（毫秒）；失败返回 -1
    static func pingLatency(ip: String) async -> Int {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/sbin/ping")
                // macOS: -c count, -t timeout seconds
                proc.arguments = ["-c", "1", "-t", "2", ip]
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = pipe
                do {
                    let start = Date()
                    try proc.run()
                    proc.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let out = String(data: data, encoding: .utf8) ?? ""
                    if proc.terminationStatus == 0 {
                        // time=12.345 ms
                        if let range = out.range(of: #"time=([0-9.]+)"#, options: .regularExpression) {
                            let token = String(out[range]).replacingOccurrences(of: "time=", with: "")
                            if let ms = Double(token) {
                                cont.resume(returning: Int(ms.rounded()))
                                return
                            }
                        }
                        let ms = Int(Date().timeIntervalSince(start) * 1000)
                        cont.resume(returning: max(1, ms))
                    } else {
                        cont.resume(returning: -1)
                    }
                } catch {
                    cont.resume(returning: -1)
                }
            }
        }
    }
}
