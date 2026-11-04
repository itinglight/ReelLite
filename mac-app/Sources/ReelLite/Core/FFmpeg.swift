import Foundation

// MARK: - ffprobe JSON 模型

struct ProbeResult: Decodable {
    let streams: [ProbeStream]
    let format: ProbeFormat?

    var video: ProbeStream? { streams.first { $0.codecType == "video" } }
    var audio: ProbeStream? { streams.first { $0.codecType == "audio" } }

    var duration: Double? {
        if let d = format?.duration, let v = Double(d), v > 0 { return v }
        if let d = video?.duration, let v = Double(d), v > 0 { return v }
        return nil
    }
}

struct ProbeStream: Decodable {
    let codecType: String?
    let codecName: String?
    let codecLongName: String?
    let profile: String?
    let width: Int?
    let height: Int?
    let pixFmt: String?
    let avgFrameRate: String?
    let rFrameRate: String?
    let bitRate: String?
    let duration: String?

    /// 与脚本一致：优先 r_frame_rate
    var frameRateString: String? {
        for s in [rFrameRate, avgFrameRate] {
            if let s, Self.evaluate(s) != nil { return s }
        }
        return nil
    }

    var fps: Double? { avgFrameRate.flatMap(Self.evaluate) ?? rFrameRate.flatMap(Self.evaluate) }

    static func evaluate(_ rational: String) -> Double? {
        let parts = rational.split(separator: "/")
        if parts.count == 2, let n = Double(parts[0]), let d = Double(parts[1]), d != 0, n > 0 { return n / d }
        if parts.count == 1, let v = Double(parts[0]), v > 0 { return v }
        return nil
    }
}

struct ProbeFormat: Decodable {
    let duration: String?
    let size: String?
    let bitRate: String?
    let formatName: String?
}

// MARK: - 兼容性评分（来自 video_inspect.sh）

struct Compatibility {
    let chrome: Int
    let safari: Int
    let remark: String

    static func evaluate(_ v: ProbeStream?) -> Compatibility {
        let codec = v?.codecName ?? ""
        switch codec {
        case "av1":
            return .init(chrome: 5, safari: 4, remark: "AV1 高效编码")
        case "vp9":
            if VP9Check.isSafariCompatible(v) {
                return .init(chrome: 5, safari: 5, remark: "Safari 完美支持")
            }
            return .init(chrome: 5, safari: 1, remark: "Safari 不兼容 (Profile 问题)")
        case "h264":
            return .init(chrome: 5, safari: 5, remark: "通用保命编码")
        default:
            return .init(chrome: 0, safari: 0, remark: "未知编码")
        }
    }
}

enum VP9Check {
    static func isSafariCompatible(_ v: ProbeStream?) -> Bool {
        v?.profile == "Profile 0" && (v?.pixFmt == nil || v?.pixFmt == "yuv420p")
    }
}

// MARK: - 调用封装

enum FFprobe {
    static func probe(_ url: URL) async throws -> ProbeResult {
        guard let bin = ToolLocator.ffprobe else { throw ToolError.notFound("ffprobe") }
        let r = try await Shell.run(bin, ["-v", "error", "-show_streams", "-show_format", "-of", "json", url.path])
        guard r.status == 0 else { throw ToolError.failed(r.status, r.stderr) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ProbeResult.self, from: r.stdout)
    }
}

enum FFmpeg {
    /// 运行 ffmpeg，并通过 -progress 解析进度（0...1）。
    static func run(
        _ args: [String],
        duration: Double? = nil,
        log: (@Sendable (String) -> Void)? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard let bin = ToolLocator.ffmpeg else { throw ToolError.notFound("ffmpeg") }
        let full = ["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-nostats", "-progress", "pipe:1"] + args
        log?("$ ffmpeg " + full.map(shellQuote).joined(separator: " "))

        let r = try await Shell.run(bin, full, onStdoutLine: { line in
            guard let progress else { return }
            if line.hasPrefix("out_time_us="), let duration, duration > 0,
               let us = Double(line.dropFirst("out_time_us=".count)) {
                progress(min(max(us / 1_000_000 / duration, 0), 1))
            } else if line == "progress=end" {
                progress(1)
            }
        }, onStderrLine: { line in
            log?(line)
        })
        guard r.status == 0 else { throw ToolError.failed(r.status, r.stderr) }
    }

    static func shellQuote(_ s: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:=,+"))
        if !s.isEmpty, s.unicodeScalars.allSatisfy({ safe.contains($0) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - 工具函数

enum Fmt {
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    static func duration(_ s: Double) -> String {
        let total = Int(s.rounded())
        let h = total / 3600, m = total % 3600 / 60, sec = total % 60
        let base = h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
        return base + String(format: " (%.2fs)", s)
    }

    static func kbps(_ bitRate: String?) -> String {
        guard let b = bitRate, let v = Double(b) else { return "N/A" }
        return "\(Int(v / 1000)) kbps"
    }
}
