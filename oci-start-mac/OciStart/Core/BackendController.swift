import Foundation
import Combine

enum BackendState: Equatable {
    case idle
    case starting
    case ready
    case failed(String)
}

/// Optional embedded Spring Boot. Dev: external :9856 counts as ready.
final class BackendController: ObservableObject {
    static let shared = BackendController()

    @Published private(set) var state: BackendState = .idle

    private var process: Process?
    private let processLock = NSLock()
    private let defaultPort = 9856

    private init() {}

    @MainActor
    func start() async {
        if case .ready = state { return }
        if case .starting = state { return }
        state = .starting

        let probeURL = URL(string: "http://127.0.0.1:\(defaultPort)/login")!

        // Already running (previous launch / manual)
        if await ping(probeURL) {
            state = .ready
            appendBackendLog("port \(defaultPort) already up → ready")
            return
        }

        guard let javaURL = resolveJava(),
              let jarURL = Bundle.main.url(forResource: "server", withExtension: "jar") else {
            // Xcode debug without embedded runtime
            state = .ready
            appendBackendLog("no embedded jre/jar → external mode ready")
            return
        }

        // Use ~/.ocistart (no spaces). "Application Support" breaks H2/JDBC and
        // caused: IllegalStateException: Unable to detect database type.
        let dataDir = appDataDir()
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let uploadDir = dataDir.appendingPathComponent("upload", isDirectory: true)
        try? FileManager.default.createDirectory(at: uploadDir, withIntermediateDirectories: true)

        let dbFile = dataDir.appendingPathComponent("vps_db").path
        let dbURL = "jdbc:h2:file:\(dbFile);DB_CLOSE_ON_EXIT=FALSE;MODE=MySQL"

        let logFile = dataDir.appendingPathComponent("backend.log")
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }

        let proc = Process()
        proc.executableURL = javaURL
        proc.arguments = [
            "-Xmx512m",
            "-Dfile.encoding=UTF-8",
            "-Dserver.port=\(defaultPort)",
            "-Dspring.datasource.url=\(dbURL)",
            "-Dspring.datasource.driver-class-name=org.h2.Driver",
            "-DbaseFile.filePath=\(uploadDir.path)/",
            "-jar", jarURL.path
        ]
        proc.currentDirectoryURL = dataDir

        // Capture stdout/stderr to file so failures are diagnosable
        if let outHandle = try? FileHandle(forWritingTo: logFile) {
            outHandle.seekToEndOfFile()
            let header = "\n---- start \(Date()) ----\n".data(using: .utf8) ?? Data()
            outHandle.write(header)
            proc.standardOutput = outHandle
            proc.standardError = outHandle
        }

        do {
            try proc.run()
            appendBackendLog("spawned java pid=\(proc.processIdentifier) jar=\(jarURL.lastPathComponent)")
        } catch {
            state = .failed("启动 Java 失败：\(error.localizedDescription)")
            appendBackendLog("spawn failed: \(error)")
            return
        }
        processLock.lock()
        process = proc
        processLock.unlock()

        for i in 0..<90 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if await ping(probeURL) {
                state = .ready
                appendBackendLog("ready after \(i + 1)s")
                return
            }
            if !proc.isRunning {
                let code = proc.terminationStatus
                state = .failed("后端进程退出 (code=\(code))，见 Application Support/OciStart/backend.log")
                appendBackendLog("java exited code=\(code)")
                return
            }
        }
        state = .failed("后端启动超时（90 秒），见 backend.log")
        appendBackendLog("timeout 90s")
    }

    /// Stop embedded backend. Call on app quit (menu / Dock / Cmd+Q).
    /// Also cleans up orphan Java on :9856 left from a previous crash.
    func stop() {
        appendBackendLog("stop requested")
        processLock.lock()
        let proc = process
        process = nil
        processLock.unlock()

        if let proc = proc {
            let pid = proc.processIdentifier
            if proc.isRunning {
                appendBackendLog("terminating tracked java pid=\(pid)")
                // SIGTERM first (Spring Boot hooks DB close)
                proc.terminate()
                kill(pid, SIGTERM)
                let deadline = Date().addingTimeInterval(2.5)
                while proc.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if proc.isRunning {
                    appendBackendLog("SIGKILL tracked java pid=\(pid)")
                    kill(pid, SIGKILL)
                    // Process.terminate is soft; force via kill already done
                }
            } else {
                appendBackendLog("tracked process already exited pid=\(pid)")
            }
        } else {
            appendBackendLog("no tracked process — will still scan port \(defaultPort)")
        }

        // Always sweep listeners on our port (covers “port already up” start path)
        killOrphanBackendsOnPort(defaultPort)

        // Reset so next launch always re-enters start() (not stuck on .ready)
        DispatchQueue.main.async {
            self.state = .idle
        }
        appendBackendLog("stop finished → state=idle")
    }

    /// Login UI: only allow credential entry when backend answers.
    var isReadyForLogin: Bool {
        if case .ready = state { return true }
        return false
    }

    /// Kill java processes listening on `port` if cmdline looks like our server.jar.
    private func killOrphanBackendsOnPort(_ port: Int) {
        let pids = listeningPIDs(on: port)
        guard !pids.isEmpty else {
            appendBackendLog("no listeners on :\(port)")
            return
        }
        // Only kill processes that look like our packaged server.jar
        // (don't kill a developer's unrelated service on 9856).
        for pid in pids {
            let cmd = processCommandLine(pid: pid)
            let isOurs = cmd.contains("server.jar")
                || (cmd.contains("java") && cmd.contains("oci-start"))
                || (cmd.contains("java") && cmd.contains("-Dserver.port=\(port)") && cmd.contains(".jar"))
            appendBackendLog("listener pid=\(pid) ours=\(isOurs) cmd=\(String(cmd.prefix(180)))")
            guard isOurs else { continue }
            kill(pid, SIGTERM)
            Thread.sleep(forTimeInterval: 0.4)
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
                appendBackendLog("SIGKILL orphan pid=\(pid)")
            } else {
                appendBackendLog("orphan pid=\(pid) exited after SIGTERM")
            }
        }
    }

    private func listeningPIDs(on port: Int) -> [pid_t] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            appendBackendLog("lsof failed: \(error.localizedDescription)")
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text
            .split(whereSeparator: { $0.isNewline || $0.isWhitespace })
            .compactMap { Int32($0) }
    }

    private func processCommandLine(pid: pid_t) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", "\(pid)", "-o", "command="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ping(_ url: URL) async -> Bool {
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        do {
            let (_, response) = try await URLSession.shared.compatData(for: req)
            return (response as? HTTPURLResponse) != nil
        } catch {
            return false
        }
    }

    private func resolveJava() -> URL? {
        let arch = Self.unameMachine()
        let jreName = arch.contains("arm64") ? "jre-arm64" : "jre-x86_64"
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent(jreName).appendingPathComponent("bin/java"),
            Bundle.main.builtInPlugInsURL?.appendingPathComponent(jreName).appendingPathComponent("bin/java")
        ]
        for case let url? in candidates {
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// Runtime data + DB (no spaces in path).
    private func appDataDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ocistart", isDirectory: true)
    }

    /// UI logs still under Application Support for easy discovery.
    private func appSupportLogDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("OciStart", isDirectory: true)
    }

    private func appendBackendLog(_ msg: String) {
        let dir = appSupportLogDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("backend-controller.log")
        let line = "\(Date())  \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: file.path),
           let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: file)
        }
        // Also mirror into data dir
        let dataDir = appDataDir()
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let mirror = dataDir.appendingPathComponent("backend-controller.log")
        if FileManager.default.fileExists(atPath: mirror.path),
           let h = try? FileHandle(forWritingTo: mirror) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: mirror)
        }
    }

    private static func unameMachine() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
