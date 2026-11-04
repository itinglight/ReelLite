import SwiftUI
import AppKit

@main
struct ReelLiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup("轻片") {
            ContentView()
                .frame(minWidth: 920, minHeight: 620)
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 通过 `swift run` 启动时没有 .app bundle，需要手动设为前台应用
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// 把视频拖到 Dock 图标上，或在 Finder 中“打开方式 → 轻片”
    func application(_ application: NSApplication, open urls: [URL]) {
        OpenFileRouter.shared.pending.append(contentsOf: urls)
    }
}

/// 暂存外部打开的文件，等界面就绪后交给「检查视频」页
final class OpenFileRouter: ObservableObject {
    static let shared = OpenFileRouter()
    @Published var pending: [URL] = []
}

enum Tool: String, CaseIterable, Identifiable {
    case inspect, compress, frame, vp9
    var id: Tool { self }   // 让行标识与 selection 类型一致

    var title: String {
        switch self {
        case .inspect: return "检查视频"
        case .compress: return "压缩视频"
        case .frame: return "导出封面"
        case .vp9: return "修复 Safari 播放"
        }
    }

    var subtitle: String {
        switch self {
        case .inspect: return "看格式、判断浏览器能否播放"
        case .compress: return "一次生成多种体积更小的版本"
        case .frame: return "截取一帧做成封面图"
        case .vp9: return "把 Safari 播不了的 WebM 转好"
        }
    }

    var icon: String {
        switch self {
        case .inspect: return "stethoscope"
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .frame: return "photo"
        case .vp9: return "safari"
        }
    }
}

struct ContentView: View {
    @State private var selection: Tool? = .inspect
    @State private var inspect = InspectModel()
    @State private var compress = CompressModel()
    @State private var frame = FrameModel()
    @State private var vp9 = VP9Model()
    @State private var ffmpegPath = ToolLocator.ffmpeg
    @State private var ffprobePath = ToolLocator.ffprobe
    @ObservedObject private var router = OpenFileRouter.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Tool.allCases) { tool in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tool.title)
                            Text(tool.subtitle).font(.caption2).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: tool.icon)
                    }
                    .padding(.vertical, 2)
                    .badge(badge(for: tool))
                    .tag(tool)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
            .safeAreaInset(edge: .bottom) { toolStatus }
        } detail: {
            Group {
                if ffmpegPath == nil || ffprobePath == nil {
                    missingView
                } else {
                    detail(for: selection ?? .inspect)
                        .id(selection)   // 切换时强制重建右侧内容
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(router.$pending) { urls in
            guard !urls.isEmpty else { return }
            router.pending = []
            selection = .inspect
            inspect.add(urls)
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            ffmpegPath = ToolLocator.ffmpeg
            ffprobePath = ToolLocator.ffprobe
        }
    }

    @ViewBuilder
    private func detail(for tool: Tool) -> some View {
        switch tool {
        case .inspect: InspectView(model: inspect)
        case .compress: CompressView(model: compress)
        case .frame: FrameView(model: frame)
        case .vp9: VP9View(model: vp9)
        }
    }

    private func badge(for tool: Tool) -> Text? {
        let running: Bool
        switch tool {
        case .inspect: running = inspect.isRunning
        case .compress: running = compress.isRunning
        case .frame: running = frame.isRunning
        case .vp9: running = vp9.isRunning
        }
        return running ? Text("●") : nil
    }

    private var toolStatus: some View {
        HStack(spacing: 6) {
            Circle().fill(ffmpegPath != nil ? Color.green : Color.red).frame(width: 7, height: 7)
            Text(ffmpegPath ?? "未找到 ffmpeg")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var missingView: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 44)).foregroundStyle(.orange)
            Text("未找到 ffmpeg / ffprobe").font(.title2.bold())
            Text("请在终端安装：").foregroundStyle(.secondary)
            Text("brew install ffmpeg").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                .padding(8).background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
            HStack {
                Button("重新检测") {
                    ffmpegPath = ToolLocator.ffmpeg
                    ffprobePath = ToolLocator.ffprobe
                }
                SettingsLink { Text("手动指定目录…") }
            }
        }
        .padding(40)
    }
}

struct SettingsView: View {
    @AppStorage(ToolLocator.customDirKey) private var customDir = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("ffmpeg 所在目录", text: $customDir, prompt: Text("留空则自动检测"))
                    Button("选择…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK, let url = panel.url { customDir = url.path }
                    }
                }
                LabeledContent("ffmpeg", value: ToolLocator.ffmpeg ?? "未找到")
                LabeledContent("ffprobe", value: ToolLocator.ffprobe ?? "未找到")
            } header: {
                Text("FFmpeg 路径")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 220)
    }
}
