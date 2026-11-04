import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 拖放 / 点击选择文件的区域
struct DropZone: View {
    var title: String
    var subtitle: String
    var allowsMultiple = false
    var allowsDirectories = false
    var allowedExtensions: [String]? = nil
    var compact = false
    var onPick: ([URL]) -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: compact ? 4 : 10) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: compact ? 20 : 34, weight: .light))
                .foregroundStyle(hovering ? Color.accentColor : .secondary)
            Text(title).font(compact ? .callout.weight(.medium) : .headline)
            if !compact {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 70 : 150)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(hovering ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(hovering ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: openPanel)
        .dropDestination(for: URL.self) { urls, _ in
            let filtered = filter(urls)
            guard !filtered.isEmpty else { return false }
            onPick(allowsMultiple ? filtered : [filtered[0]])
            return true
        } isTargeted: { hovering = $0 }
    }

    private func filter(_ urls: [URL]) -> [URL] {
        urls.filter { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue { return allowsDirectories }
            if let exts = allowedExtensions { return exts.contains(url.pathExtension.lowercased()) }
            return true
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = allowsDirectories
        panel.allowsMultipleSelection = allowsMultiple
        if let exts = allowedExtensions {
            panel.allowedContentTypes = exts.compactMap { UTType(filenameExtension: $0) }
        } else {
            panel.allowedContentTypes = [.movie, .video, .audiovisualContent]
        }
        if panel.runModal() == .OK { onPick(panel.urls) }
    }
}

/// 页面标题
struct PageHeader: View {
    var title: String
    var subtitle: String
    var icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.bold())
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// 卡片容器
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
    }
}

/// 选中文件信息条
struct FileChip: View {
    var url: URL
    var detail: String?
    var onClear: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "film").foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent).font(.body.weight(.medium)).lineLimit(1).truncationMode(.middle)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                Image(systemName: "magnifyingglass")
            }.buttonStyle(.borderless).help("在 Finder 中显示")
            if let onClear {
                Button(action: onClear) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("移除")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
}

/// 星级 (x / 5)
struct ScoreView: View {
    var score: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < score ? "star.fill" : "star")
                    .foregroundStyle(i < score ? color : Color.secondary.opacity(0.4))
            }
            Text("\(score) / 5").font(.caption.monospacedDigit()).foregroundStyle(.secondary).padding(.leading, 4)
        }
        .font(.caption)
    }
    var color: Color { score >= 5 ? .green : score >= 3 ? .orange : .red }
}

/// 日志控制台
struct LogConsole: View {
    var lines: [String]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(line.hasPrefix("$") ? Color.accentColor : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 160)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.06)))
                .onChange(of: lines.count) { _, n in
                    if n > 0 { proxy.scrollTo(n - 1, anchor: .bottom) }
                }
            }
        } label: {
            HStack {
                Text("详细日志（出错时查看）").font(.callout.weight(.medium))
                Text("\(lines.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !lines.isEmpty {
                    Button("复制") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
                    }.buttonStyle(.borderless).font(.caption)
                }
            }
        }
    }
}

/// 日志缓冲（限制最大行数）
struct LogBuffer {
    private(set) var lines: [String] = []
    var limit = 2000
    mutating func append(_ s: String) {
        lines.append(s)
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
    }
    mutating func clear() { lines.removeAll() }
}

func revealInFinder(_ urls: [URL]) {
    NSWorkspace.shared.activateFileViewerSelecting(urls)
}

/// 参数行：左边是名称 + 灰色说明，右边是控件
struct ParamRow<Control: View>: View {
    var title: String
    var help: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.medium))
                Text(help).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 4)
    }
}

/// 名词解释（默认收起）
struct Glossary: View {
    var items: [(String, String)]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items, id: \.0) { term, desc in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(term).font(.callout.weight(.semibold))
                        Text(desc).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("名词解释", systemImage: "questionmark.circle").font(.callout.weight(.medium))
        }
    }
}

/// 页面底部：名词解释 + 日志
struct PageFooter: View {
    var glossary: [(String, String)]
    var log: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Glossary(items: glossary)
            LogConsole(lines: log)
        }
        .padding(.top, 8)
    }
}

enum Terms {
    static let crf = ("CRF（画质系数）", "控制画质与体积的平衡。数值越小，画质越好、文件越大；数值越大，文件越小、画质越差。一般 23～35 之间肉眼差别不大。")
    static let codec = ("编码（VP8 / VP9 / AV1 / H.264）", "视频的压缩算法。H.264 兼容性最好；VP9 比 H.264 小约 30%；AV1 是最新一代，同画质下体积最小，但压缩速度最慢。")
    static let container = ("格式（WebM / MP4）", "装视频的“外壳”。WebM 是网页常用格式，常配 VP8/VP9；MP4 最通用，可以装 H.264 或 AV1。")
    static let profile = ("Profile（编码档次）", "同一种编码的不同“版本档次”。VP9 的 Profile 0 是最基础的 8 位色彩，Safari 只支持这一种；Profile 1～3 支持更高色彩，但 Safari 播不了。")
    static let pixFmt = ("像素格式", "颜色的存储方式。yuv420p 是最常见、兼容性最好的；yuv444p、10 位色等格式画质更好，但很多播放器不支持。")
    static let fps = ("帧率", "每秒播放多少张画面。常见 24、25、30、60。帧率越高越流畅，文件也越大。")
    static let bitrate = ("码率", "每秒视频占用的数据量，单位 kbps。码率越高，画质通常越好、文件越大。")
    static let ratio = ("压缩比", "原文件大小 ÷ 新文件大小。例如 5.00x 表示新文件只有原来的 1/5。")
}
