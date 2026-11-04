import SwiftUI

/// compress_video.sh 中的 6 个压缩方案
struct CompressPreset: Identifiable, Hashable {
    let id: String          // 用作输出文件名后缀
    let codec: String
    let note: String        // 技术参数（小字）
    let title: String       // 通俗名称
    let usage: String       // 适合什么场景
    let ext: String
    let encoderArgs: [String]
    let scale: String

    func args(fps: String?) -> [String] {
        let vf = fps.map { "\(scale),fps=\($0)" } ?? scale
        return ["-an"] + encoderArgs + ["-vf", vf]
    }

    static let all: [CompressPreset] = [
        .init(id: "1080p_vp8", codec: "VP8", note: "WebM · 最高 1080p · CRF 10", title: "兼容优先", usage: "几乎所有浏览器都能播，画质好但文件偏大", ext: "webm",
              encoderArgs: ["-c:v", "libvpx", "-crf", "10", "-b:v", "0", "-deadline", "good", "-cpu-used", "1"],
              scale: "scale='min(1920,iw)':'-2'"),
        .init(id: "720p_vp9", codec: "VP9", note: "WebM · 最高 720p · CRF 33", title: "小尺寸", usage: "体积小，适合手机页面或小窗口播放", ext: "webm",
              encoderArgs: ["-c:v", "libvpx-vp9", "-crf", "33", "-b:v", "0", "-row-mt", "1", "-tile-columns", "2", "-frame-parallel", "1"],
              scale: "scale='min(1280,iw)':'-2'"),
        .init(id: "1080p_vp9_hq", codec: "VP9", note: "WebM · 1080p · CRF 25", title: "高清", usage: "画质优先，适合首页大图、全屏背景", ext: "webm",
              encoderArgs: ["-c:v", "libvpx-vp9", "-crf", "25", "-b:v", "0", "-row-mt", "1", "-tile-columns", "2", "-frame-parallel", "1"],
              scale: "scale='1920:-2'"),
        .init(id: "1080p_av1_hq", codec: "AV1", note: "MP4 · 1080p · CRF 36", title: "高清省流量", usage: "新一代编码，同等画质下体积更小；压缩较慢", ext: "mp4",
              encoderArgs: ["-c:v", "libaom-av1", "-crf", "36", "-b:v", "0", "-cpu-used", "6"],
              scale: "scale='1920:-2'"),
        .init(id: "1080p_av1", codec: "AV1", note: "MP4 · 1080p · CRF 38", title: "均衡", usage: "比「高清省流量」再小一些，画质略降", ext: "mp4",
              encoderArgs: ["-c:v", "libaom-av1", "-crf", "38", "-b:v", "0", "-cpu-used", "6"],
              scale: "scale='1920:-2'"),
        .init(id: "720p_av1", codec: "AV1", note: "MP4 · 720p · CRF 38", title: "最省流量", usage: "体积最小，适合移动端和弱网环境", ext: "mp4",
              encoderArgs: ["-c:v", "libaom-av1", "-crf", "38", "-b:v", "0", "-cpu-used", "6"],
              scale: "scale='1280:-2'"),
    ]
}

enum JobStatus: Equatable {
    case pending, running(Double), done, failed(String), cancelled
}

struct CompressJob: Identifiable {
    var id: String { preset.id }
    let preset: CompressPreset
    let output: URL
    var status: JobStatus = .pending
    var size: Int64?
    var elapsed: TimeInterval?
}

@MainActor @Observable
final class CompressModel {
    var input: URL?
    var probe: ProbeResult?
    var inputSize: Int64?
    var outputDir: URL?
    var enabled: Set<String> = Set(CompressPreset.all.map(\.id))
    var jobs: [CompressJob] = []
    var log = LogBuffer()
    var isRunning = false
    private var task: Task<Void, Never>?

    var effectiveOutputDir: URL? {
        outputDir ?? input?.deletingLastPathComponent().appendingPathComponent("compressed_videos", isDirectory: true)
    }

    func setInput(_ url: URL) {
        input = url
        inputSize = Fmt.fileSize(url)
        probe = nil
        jobs = []
        Task {
            probe = try? await FFprobe.probe(url)
        }
    }

    func start() {
        guard let input, let dir = effectiveOutputDir, !isRunning else { return }
        let name = input.deletingPathExtension().lastPathComponent
        jobs = CompressPreset.all.filter { enabled.contains($0.id) }.map {
            CompressJob(preset: $0, output: dir.appendingPathComponent("\(name)_\($0.id).\($0.ext)"))
        }
        guard !jobs.isEmpty else { return }
        isRunning = true
        log.clear()

        task = Task {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                log.append("❌ 无法创建输出目录: \(error.localizedDescription)")
                isRunning = false
                return
            }
            let info: ProbeResult? = if let probe { probe } else { try? await FFprobe.probe(input) }
            self.probe = info
            let fps = info?.video?.frameRateString
            let duration = info?.duration
            log.append("开始压缩: \(input.path)")
            log.append("检测到源帧率: \(fps ?? "未知")   原始大小: \(inputSize.map(Fmt.bytes) ?? "?")")

            for i in jobs.indices {
                if Task.isCancelled { jobs[i].status = .cancelled; continue }
                let job = jobs[i]
                jobs[i].status = .running(0)
                let started = Date()
                do {
                    try await FFmpeg.run(
                        ["-i", input.path] + job.preset.args(fps: fps) + [job.output.path],
                        duration: duration,
                        log: { line in Task { @MainActor in self.log.append(line) } },
                        progress: { p in Task { @MainActor in
                            if case .running = self.jobs[i].status { self.jobs[i].status = .running(p) }
                        } }
                    )
                    jobs[i].status = .done
                    jobs[i].size = Fmt.fileSize(job.output)
                    jobs[i].elapsed = Date().timeIntervalSince(started)
                } catch ToolError.cancelled {
                    jobs[i].status = .cancelled
                    try? FileManager.default.removeItem(at: job.output)
                } catch {
                    jobs[i].status = .failed(error.localizedDescription)
                    log.append("❌ \(job.preset.id): \(error.localizedDescription)")
                }
            }
            log.append("✅ 全部完成")
            isRunning = false
        }
    }

    func cancel() {
        task?.cancel()
    }
}

struct CompressView: View {
    @Bindable var model: CompressModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "压缩视频",
                           subtitle: "选好方案后一键生成多个版本，对比体积，挑最合适的放到网页上",
                           icon: "arrow.down.right.and.arrow.up.left")

                // 第 1 步：选文件
                if let input = model.input {
                    FileChip(url: input, detail: inputDetail, onClear: model.isRunning ? nil : {
                        model.input = nil; model.jobs = []
                    })
                } else {
                    DropZone(title: "把视频拖到这里，或点击选择", subtitle: "支持 mp4 / mov / webm / mkv 等常见格式") {
                        if let u = $0.first { model.setInput(u) }
                    }
                }

                // 第 2 步：选方案
                Card {
                    HStack {
                        Text("选择要生成的版本").font(.headline)
                        Spacer()
                        Button(model.enabled.count == CompressPreset.all.count ? "全不选" : "全选") {
                            if model.enabled.count == CompressPreset.all.count { model.enabled = [] }
                            else { model.enabled = Set(CompressPreset.all.map(\.id)) }
                        }
                        .buttonStyle(.borderless).font(.callout).disabled(model.isRunning)
                    }
                    Text("每勾选一个就多生成一个文件。生成的视频都不带声音，适合做网页背景视频。")
                        .font(.caption).foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(CompressPreset.all) { p in
                            presetRow(p)
                            if p.id != CompressPreset.all.last?.id { Divider() }
                        }
                    }
                    Divider()
                    ParamRow(title: "保存位置",
                             help: model.outputDir == nil
                                ? "默认保存在原视频旁边的 compressed_videos 文件夹"
                                : (model.effectiveOutputDir?.path ?? "")) {
                        HStack {
                            if model.outputDir != nil {
                                Button("恢复默认") { model.outputDir = nil }
                            }
                            Button("更改…") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.canCreateDirectories = true
                                if panel.runModal() == .OK { model.outputDir = panel.url }
                            }
                        }
                        .disabled(model.isRunning)
                    }
                }

                // 第 3 步：开始
                HStack(spacing: 12) {
                    if model.isRunning {
                        Button(role: .destructive) { model.cancel() } label: {
                            Label("停止", systemImage: "stop.fill")
                        }
                        .controlSize(.large)
                        ProgressView().controlSize(.small)
                        Text("正在生成第 \(min(doneCount + 1, model.jobs.count)) / \(model.jobs.count) 个，AV1 会比较慢，请耐心等待")
                            .foregroundStyle(.secondary).font(.callout)
                    } else {
                        Button { model.start() } label: {
                            Label(model.enabled.isEmpty ? "请先勾选版本" : "开始压缩（\(model.enabled.count) 个版本）",
                                  systemImage: "play.fill")
                                .frame(minWidth: 160)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(model.input == nil || model.enabled.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                        if model.input == nil {
                            Text("先选择一个视频").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if doneCount > 0, let dir = model.effectiveOutputDir {
                        Button("打开保存文件夹") { NSWorkspace.shared.open(dir) }
                    }
                }

                if !model.jobs.isEmpty { resultTable }

                PageFooter(glossary: [Terms.codec, Terms.container, Terms.crf, Terms.ratio],
                           log: model.log.lines)
            }
            .padding(24)
        }
    }

    private func presetRow(_ p: CompressPreset) -> some View {
        Toggle(isOn: Binding(
            get: { model.enabled.contains(p.id) },
            set: { on in if on { model.enabled.insert(p.id) } else { model.enabled.remove(p.id) } }
        )) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(p.title).font(.callout.weight(.medium))
                        CodecTag(codec: p.codec)
                    }
                    Text(p.usage).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(p.note).font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 7)
            .padding(.leading, 4)
        }
        .toggleStyle(.checkbox)
        .disabled(model.isRunning)
    }

    private var doneCount: Int { model.jobs.filter { $0.status == .done }.count }

    private var inputDetail: String {
        var parts: [String] = []
        if let s = model.inputSize { parts.append(Fmt.bytes(s)) }
        if let v = model.probe?.video {
            if let w = v.width, let h = v.height { parts.append("\(w)×\(h)") }
            if let c = v.codecName { parts.append(c) }
            if let f = v.fps { parts.append(String(format: "%.0f 帧/秒", f)) }
        }
        if let d = model.probe?.duration { parts.append(Fmt.duration(d)) }
        return parts.joined(separator: " · ")
    }

    /// 已完成的按体积升序排列（同脚本），其余保持原顺序
    private var sortedJobs: [CompressJob] {
        let done = model.jobs.filter { $0.size != nil }.sorted { ($0.size ?? 0) < ($1.size ?? 0) }
        return done + model.jobs.filter { $0.size == nil }
    }

    private var resultTable: some View {
        Card {
            Text("结果对比（从小到大）").font(.headline)
            Text("「压缩比」表示原视频是新文件的几倍大，数字越大越省空间；「剩余体积」是新文件占原视频的百分比。")
                .font(.caption).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("版本"); Text("大小"); Text("压缩比"); Text("剩余体积"); Text("状态"); Text("")
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Divider().gridCellColumns(6)
                ForEach(sortedJobs) { job in
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(job.preset.title).font(.callout.weight(.medium))
                                CodecTag(codec: job.preset.codec)
                            }
                            Text(job.output.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Text(job.size.map(Fmt.bytes) ?? "—").monospacedDigit()
                        Text(ratio(job)).monospacedDigit().bold()
                        Text(percent(job)).monospacedDigit()
                        StatusView(status: job.status, elapsed: job.elapsed).frame(width: 150, alignment: .leading)
                        Button { revealInFinder([job.output]) } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.borderless)
                            .help("在 Finder 中显示")
                            .opacity(job.status == .done ? 1 : 0)
                            .disabled(job.status != .done)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func ratio(_ job: CompressJob) -> String {
        guard let s = job.size, s > 0, let o = model.inputSize else { return "—" }
        return String(format: "%.2fx", Double(o) / Double(s))
    }

    private func percent(_ job: CompressJob) -> String {
        guard let s = job.size, let o = model.inputSize, o > 0 else { return "—" }
        return String(format: "%.1f%%", Double(s) * 100 / Double(o))
    }
}

struct CodecTag: View {
    var codec: String
    var body: some View {
        Text(codec)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
    var color: Color {
        switch codec {
        case "AV1": return .purple
        case "VP9": return .blue
        case "VP8": return .teal
        default: return .gray
        }
    }
}

struct StatusView: View {
    var status: JobStatus
    var elapsed: TimeInterval? = nil

    var body: some View {
        switch status {
        case .pending:
            Label("等待中", systemImage: "clock").foregroundStyle(.secondary)
        case .running(let p):
            HStack(spacing: 6) {
                ProgressView(value: p).frame(width: 90)
                Text("\(Int(p * 100))%").monospacedDigit().font(.caption)
            }
        case .done:
            Label(elapsed.map { String(format: "完成 %.0fs", $0) } ?? "完成", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let msg):
            Label("失败", systemImage: "xmark.octagon.fill").foregroundStyle(.red).help(msg)
        case .cancelled:
            Label("已取消", systemImage: "minus.circle").foregroundStyle(.secondary)
        }
    }
}
