import Foundation

enum BackendState: Equatable {
    case starting
    case ready
    case failed(String)
}

final class BackendManager: ObservableObject {

    static let shared = BackendManager()

    @Published var state: BackendState = .starting
    @Published var logBuffer: [String] = []

    private var process: Process?
    private let processLock = NSLock()
    private let port = 9856

    private init() {}

    // MARK: - Public

    @MainActor
    func start() async {
        // If already running on the port (e.g. dev mode), treat as ready
        if await ping(URL(string: "http://localhost:\(port)/login")!) {
            state = .ready
            return
        }

        guard let javaURL = resolveJava() else {
            state = .failed("找不到捆绑的 JRE（PlugIns/jre-arm64 或 jre-x86_64）")
            return
        }
        guard let jarURL = Bundle.main.url(forResource: "server", withExtension: "jar") else {
            state = .failed("找不到 server.jar（Resources/server.jar）")
            return
        }

        let dataDir = appSupportDir()
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let uploadDir = dataDir.appendingPathComponent("upload").path
        try? FileManager.default.createDirectory(
            atPath: uploadDir, withIntermediateDirectories: true, attributes: nil)

        let dbPath = dataDir.appendingPathComponent("vps_db").path

        let proc = Process()
        proc.executableURL = javaURL
        proc.arguments = [
            "-Xmx512m",
            "-Dserver.port=\(port)",
            "-Dspring.datasource.url=jdbc:h2:file:\(dbPath);DB_CLOSE_ON_EXIT=FALSE",
            "-DbaseFile.filePath=\(uploadDir)/",
            "-jar", jarURL.path
        ]
        proc.currentDirectoryURL = dataDir

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = pipe
        let appendLog: (String) -> Void = { [weak self] line in
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.logBuffer.append(line)
                if strongSelf.logBuffer.count > 500 { strongSelf.logBuffer.removeFirst() }
            }
        }
        pipe.fileHandleForReading.readabilityHandler = { fh in
            guard let line = String(data: fh.availableData, encoding: .utf8),
                  !line.isEmpty else { return }
            appendLog(line)
        }

        do {
            try proc.launch()
        } catch {
            state = .failed("启动 Java 进程失败：\(error.localizedDescription)")
            return
        }
        processLock.lock()
        self.process = proc
        processLock.unlock()

        // Poll until Spring Boot is ready (up to 90 s)
        let healthURL = URL(string: "http://localhost:\(port)/login")!
        for _ in 0..<90 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if await ping(healthURL) {
                state = .ready
                return
            }
            // Check if process died early
            if !proc.isRunning {
                state = .failed("后端进程意外退出，请查看日志")
                return
            }
        }
        state = .failed("后端启动超时（90 秒）")
    }

    /// Thread-safe: safe to call from AppDelegate.terminate
    func stop() {
        processLock.lock()
        let proc = process
        process = nil
        processLock.unlock()

        guard let proc = proc, proc.isRunning else { return }
        let pid = proc.processIdentifier
        proc.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
        }
    }

    @MainActor
    func restart() async {
        stop()
        try? await Task.sleep(nanoseconds: 800_000_000)
        state = .starting
        await start()
    }

    // MARK: - Private helpers

    private func ping(_ url: URL) async -> Bool {
        do {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 2
            let session = URLSession(configuration: config)
            let (_, resp) = try await session.compatData(from: url)
            return (resp as? HTTPURLResponse) != nil
        } catch {
            return false
        }
    }

    private func resolveJava() -> URL? {
        guard let pluginsURL = Bundle.main.builtInPlugInsURL else { return nil }
        let arch = isAppleSilicon() ? "arm64" : "x86_64"
        // Try arch-specific JRE first, then fall back to the other one
        for a in [arch, arch == "arm64" ? "x86_64" : "arm64"] {
            let javaURL = pluginsURL
                .appendingPathComponent("jre-\(a)")
                .appendingPathComponent("bin/java")
            if FileManager.default.isExecutableFile(atPath: javaURL.path) {
                return javaURL
            }
        }
        return nil
    }

    private func appSupportDir() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("OciStart")
    }

    private func isAppleSilicon() -> Bool {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { ptr -> String in
            String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        return machine.hasPrefix("arm")
    }
}
