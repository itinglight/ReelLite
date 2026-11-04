import Foundation

/// 定位 ffmpeg / ffprobe。从 Finder 启动的 App 拿不到终端的 PATH，所以显式搜索常见目录。
enum ToolLocator {
    static let customDirKey = "customFFmpegDir"

    static var searchDirs: [String] {
        var dirs: [String] = []
        if let custom = UserDefaults.standard.string(forKey: customDirKey), !custom.isEmpty {
            dirs.append(custom)
        }
        dirs += ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            dirs += path.split(separator: ":").map(String.init)
        }
        return dirs
    }

    static func find(_ name: String) -> String? {
        for dir in searchDirs {
            let p = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    static var ffmpeg: String? { find("ffmpeg") }
    static var ffprobe: String? { find("ffprobe") }
}

struct ProcessResult {
    let status: Int32
    let stdout: Data
    let stderr: String
}

enum ToolError: LocalizedError {
    case notFound(String)
    case failed(Int32, String)
    case cancelled
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let n): return "找不到 \(n)，请先安装：brew install ffmpeg"
        case .failed(let code, let err):
            let tail = err.split(separator: "\n").suffix(6).joined(separator: "\n")
            return "退出码 \(code)\n\(tail)"
        case .cancelled: return "已取消"
        case .message(let m): return m
        }
    }
}

/// 把字节流拆成行（线程安全）
private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private(set) var all = Data()
    let onLine: ((String) -> Void)?

    init(onLine: ((String) -> Void)?) { self.onLine = onLine }

    func feed(_ data: Data) {
        lock.lock()
        all.append(data)
        buffer.append(data)
        var lines: [String] = []
        while let idx = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = buffer[buffer.startIndex..<idx]
            buffer.removeSubrange(buffer.startIndex...idx)
            if let s = String(data: lineData, encoding: .utf8), !s.isEmpty { lines.append(s) }
        }
        lock.unlock()
        lines.forEach { onLine?($0) }
    }

    func flush() {
        lock.lock()
        let rest = buffer
        buffer.removeAll()
        lock.unlock()
        if let s = String(data: rest, encoding: .utf8), !s.isEmpty { onLine?(s) }
    }

    var data: Data { lock.lock(); defer { lock.unlock() }; return all }
}

private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

enum Shell {
    /// 运行外部进程。Task 被取消时会终止子进程。
    static func run(
        _ executable: String,
        _ args: [String],
        onStdoutLine: ((String) -> Void)? = nil,
        onStderrLine: ((String) -> Void)? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let out = LineCollector(onLine: onStdoutLine)
        let err = LineCollector(onLine: onStderrLine)
        let cancelled = CancelFlag()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ProcessResult, Error>) in
                let group = DispatchGroup()
                group.enter()
                process.terminationHandler = { _ in group.leave() }
                do {
                    try process.run()
                } catch {
                    cont.resume(throwing: error)
                    return
                }
                for (handle, collector) in [(outPipe.fileHandleForReading, out), (errPipe.fileHandleForReading, err)] {
                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        while true {
                            let d = handle.availableData
                            if d.isEmpty { break }
                            collector.feed(d)
                        }
                        collector.flush()
                        group.leave()
                    }
                }
                group.notify(queue: .global()) {
                    if cancelled.value {
                        cont.resume(throwing: ToolError.cancelled)
                        return
                    }
                    cont.resume(returning: ProcessResult(
                        status: process.terminationStatus,
                        stdout: out.data,
                        stderr: String(data: err.data, encoding: .utf8) ?? ""
                    ))
                }
            }
        } onCancel: {
            cancelled.set()
            if process.isRunning { process.terminate() }
        }
    }
}
