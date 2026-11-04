import SwiftUI
import AppKit

struct FrameOutput: Identifiable {
    var id: String { format }
    let format: String
    let url: URL
    let size: Int64?
}

@MainActor @Observable
final class FrameModel {
    var input: URL?
    var seek: Double = 0.1
    var jpgQuality: Int = 2       // -q:v 2-31，越小越好
    var webpQuality: Double = 90  // 0-100
    var outputs: [FrameOutput] = []
    var preview: NSImage?
    var error: String?
    var log = LogBuffer()
    var isRunning = false

    func setInput(_ url: URL) {
        input = url
        outputs = []
        preview = nil
        error = nil
    }

    func export() {
        guard let input, !isRunning else { return }
        isRunning = true
        error = nil
        outputs = []
        log.clear()
        let base = input.deletingPathExtension().path
        let jpg = URL(fileURLWithPath: base + "_first_frame.jpg")
        let webp = URL(fileURLWithPath: base + "_first_frame.webp")
        let ss = String(format: "%.3f", seek)
        let logger: @Sendable (String) -> Void = { l in Task { @MainActor in self.log.append(l) } }

        Task {
            do {
                try await FFmpeg.run(["-ss", ss, "-i", input.path, "-vframes", "1", "-q:v", "\(jpgQuality)", jpg.path],
                                     log: logger)
                try await FFmpeg.run(["-ss", ss, "-i", input.path, "-vframes", "1", "-update", "1",
                                      "-c:v", "libwebp", "-quality", "\(Int(webpQuality))", webp.path],
                                     log: logger)
                outputs = [
                    FrameOutput(format: "JPG", url: jpg, size: Fmt.fileSize(jpg)),
                    FrameOutput(format: "WebP", url: webp, size: Fmt.fileSize(webp)),
                ]
                preview = NSImage(contentsOf: jpg)
            } catch {
                self.error = error.localizedDescription
            }
            isRunning = false
        }
    }
}

struct FrameView: View {
    @Bindable var model: FrameModel
    @State private var seekText = ""

    static func format(_ v: Double) -> String {
        var t = String(format: "%.3f", v)
        while t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return t
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "导出封面",
                           subtitle: "从视频里截一帧，同时导出 JPG 和 WebP 两种图片，用作视频加载前显示的封面",
                           icon: "photo")

                if let input = model.input {
                    FileChip(url: input, detail: "图片会保存在这个视频旁边",
                             onClear: model.isRunning ? nil : { model.input = nil; model.outputs = [] })
                } else {
                    DropZone(title: "把视频拖到这里，或点击选择", subtitle: "图片会保存在视频所在的文件夹") {
                        if let u = $0.first { model.setInput(u) }
                    }
                }

                Card {
                    Text("设置").font(.headline)
                    ParamRow(title: "截取第几秒",
                             help: "从视频的哪个时间点取画面。默认 0.1 秒，避开开头可能出现的黑屏。") {
                        HStack(spacing: 4) {
                            // 不用带格式化器的 TextField：校验失败时它会一直占着焦点，导致侧边栏点不动
                            TextField("", text: $seekText)
                                .frame(width: 70).multilineTextAlignment(.trailing)
                                .onChange(of: seekText) { _, t in
                                    if let v = Double(t.replacingOccurrences(of: ",", with: ".")), v >= 0 { model.seek = v }
                                }
                            Stepper("", value: $model.seek, in: 0...36000, step: 0.1).labelsHidden()
                                .onChange(of: model.seek) { _, v in
                                    let t = Self.format(v)
                                    if Double(seekText) != v { seekText = t }
                                }
                            Text("秒").foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    ParamRow(title: "JPG 清晰度",
                             help: "1 最清晰、31 最模糊。数字越小图片越清楚，文件也越大。推荐 2。") {
                        Stepper(value: $model.jpgQuality, in: 1...31) {
                            Text("\(model.jpgQuality)").monospacedDigit().frame(width: 26, alignment: .trailing)
                        }
                    }
                    Divider()
                    ParamRow(title: "WebP 质量",
                             help: "100 最清晰。WebP 比 JPG 小很多，90 时肉眼基本看不出差别。推荐 90。") {
                        HStack {
                            Slider(value: $model.webpQuality, in: 10...100, step: 1).frame(width: 160)
                            Text("\(Int(model.webpQuality))").monospacedDigit().frame(width: 30, alignment: .trailing)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button { model.export() } label: {
                        Label("导出封面", systemImage: "photo.badge.arrow.down").frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.input == nil || model.isRunning)
                    .keyboardShortcut(.return, modifiers: .command)
                    if model.isRunning { ProgressView().controlSize(.small) }
                    if model.input == nil {
                        Text("先选择一个视频").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if let err = model.error {
                    Label(err, systemImage: "xmark.octagon").foregroundStyle(.red)
                }

                if !model.outputs.isEmpty {
                    Card {
                        Text("导出完成").font(.headline)
                        HStack(alignment: .top, spacing: 16) {
                            if let img = model.preview {
                                Image(nsImage: img)
                                    .resizable().aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 360, maxHeight: 240)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .shadow(radius: 2)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(model.outputs) { o in
                                    HStack(spacing: 10) {
                                        Text(o.format).bold().frame(width: 44, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(o.size.map(Fmt.bytes) ?? "—").monospacedDigit()
                                            Text(o.url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                                                .lineLimit(1).truncationMode(.middle)
                                        }
                                        Spacer()
                                        Button { NSWorkspace.shared.open(o.url) } label: { Image(systemName: "eye") }
                                            .help("打开图片")
                                        Button { revealInFinder([o.url]) } label: { Image(systemName: "magnifyingglass") }
                                            .help("在 Finder 中显示")
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.callout)
                                }
                                Text("网页上优先用 WebP（更小），JPG 作为老浏览器的备用。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                PageFooter(glossary: [
                    ("JPG", "最通用的图片格式，所有浏览器和软件都能打开。"),
                    ("WebP", "谷歌推出的网页图片格式，同等清晰度下比 JPG 小 25%～35%，现代浏览器都支持。"),
                    ("封面（poster）", "视频还没加载出来时先显示的图片，可以避免页面出现空白或黑框。"),
                ], log: model.log.lines)
            }
            .padding(24)
        }
        .onAppear { seekText = Self.format(model.seek) }
    }
}
