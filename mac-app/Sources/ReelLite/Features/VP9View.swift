import SwiftUI

enum VP9ItemState: Equatable {
    case checking
    case compliant          // 已符合 Safari 要求
    case notVP9(String)     // 非 VP9，跳过
    case needsConvert
    case converting(Double)
    case done(URL, Int64?)
    case failed(String)
    case cancelled
}

struct VP9Item: Identifiable {
    let id = UUID()
    let url: URL
    var codec: String?
    var profile: String?
    var pixFmt: String?
    var duration: Double?
    var state: VP9ItemState = .checking
}

@MainActor @Observable
final class VP9Model {
    var items: [VP9Item] = []
    var crf: Int = 30
    var log = LogBuffer()
    var isRunning = false
    private var task: Task<Void, Never>?

    var pendingCount: Int { items.filter { $0.state == .needsConvert }.count }

    /// 接收文件或文件夹（文件夹仅扫描一层 .webm，与脚本一致）
    func add(_ urls: [URL]) {
        var files: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                files += contents.filter { $0.pathExtension.lowercased() == "webm" && !$0.lastPathComponent.hasPrefix(".") }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
            } else if url.pathExtension.lowercased() == "webm" {
                files.append(url)
            }
        }
        let existing = Set(items.map(\.url))
        for f in files where !existing.contains(f) {
            let item = VP9Item(url: f)
            items.append(item)
            let id = item.id
            Task {
                do {
                    let p = try await FFprobe.probe(f)
                    update(id) { it in
                        let v = p.video
                        it.codec = v?.codecName
                        it.profile = v?.profile
                        it.pixFmt = v?.pixFmt
                        it.duration = p.duration
                        if v?.codecName != "vp9" {
                            it.state = .notVP9(v?.codecName ?? "无视频流")
                        } else {
                            it.state = VP9Check.isSafariCompatible(v) ? .compliant : .needsConvert
                        }
                    }
                } catch {
                    update(id) { $0.state = .failed(error.localizedDescription) }
                }
            }
        }
    }

    func start() {
        guard !isRunning, pendingCount > 0 else { return }
        isRunning = true
        log.clear()
        let crf = self.crf
        task = Task {
            for i in items.indices where items[i].state == .needsConvert {
                if Task.isCancelled { break }
                let item = items[i]
                let out = URL(fileURLWithPath: item.url.deletingPathExtension().path + "_p0.webm")
                log.append("▶ \(item.url.lastPathComponent)  Profile: \(item.profile ?? "?")  PixFmt: \(item.pixFmt ?? "?")")
                items[i].state = .converting(0)
                do {
                    try await FFmpeg.run(
                        ["-i", item.url.path, "-c:v", "libvpx-vp9", "-profile:v", "0", "-pix_fmt", "yuv420p",
                         "-b:v", "0", "-crf", "\(crf)", "-row-mt", "1", "-threads", "8", "-an", out.path],
                        duration: item.duration,
                        log: { l in Task { @MainActor in self.log.append(l) } },
                        progress: { p in Task { @MainActor in
                            if case .converting = self.items[i].state { self.items[i].state = .converting(p) }
                        } }
                    )
                    items[i].state = .done(out, Fmt.fileSize(out))
                    log.append("✅ 完成 → \(out.lastPathComponent)")
                } catch ToolError.cancelled {
                    items[i].state = .cancelled
                    try? FileManager.default.removeItem(at: out)
                } catch {
                    items[i].state = .failed(error.localizedDescription)
                    log.append("❌ \(error.localizedDescription)")
                }
            }
            log.append("🎉 处理完成")
            isRunning = false
        }
    }

    func cancel() { task?.cancel() }

    func clear() {
        guard !isRunning else { return }
        items.removeAll()
    }

    func remove(_ id: UUID) {
        guard !isRunning else { return }
        items.removeAll { $0.id == id }
    }

    private func update(_ id: UUID, _ change: (inout VP9Item) -> Void) {
        if let i = items.firstIndex(where: { $0.id == id }) { change(&items[i]) }
    }
}

struct VP9View: View {
    @Bindable var model: VP9Model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "修复 Safari 播放",
                           subtitle: "有些 WebM 视频在 Chrome 正常、在 Safari / iPhone 上却黑屏，这里可以一键转成 Safari 能播的版本",
                           icon: "safari")

                DropZone(title: "把 .webm 文件或整个文件夹拖到这里", subtitle: "会自动检查每个文件，只转换有问题的",
                         allowsMultiple: true, allowsDirectories: true, allowedExtensions: ["webm"],
                         compact: !model.items.isEmpty) { model.add($0) }

                Card {
                    ParamRow(title: "画质（CRF）",
                             help: "数字越小越清晰、文件越大。推荐 30；觉得画质不够可以调到 24 左右。") {
                        Stepper(value: $model.crf, in: 10...50) {
                            Text("\(model.crf)").monospacedDigit().frame(width: 26, alignment: .trailing)
                        }
                        .disabled(model.isRunning)
                    }
                    Divider()
                    ParamRow(title: "保存方式",
                             help: "不会覆盖原文件，转换后的文件名会多一个 _p0，保存在原文件旁边。") { EmptyView() }
                }

                HStack(spacing: 12) {
                    if model.isRunning {
                        Button(role: .destructive) { model.cancel() } label: { Label("停止", systemImage: "stop.fill") }
                            .controlSize(.large)
                        ProgressView().controlSize(.small)
                    } else {
                        Button { model.start() } label: {
                            Label(model.pendingCount == 0 ? "没有需要转换的文件" : "开始转换（\(model.pendingCount) 个）",
                                  systemImage: "play.fill")
                                .frame(minWidth: 140)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(model.pendingCount == 0)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                    Spacer()
                    if !model.items.isEmpty {
                        Button("清空列表") { model.clear() }
                            .buttonStyle(.borderless).disabled(model.isRunning)
                    }
                }

                if !model.items.isEmpty {
                    Card {
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                            GridRow {
                                Text("文件"); Text("Profile"); Text("像素格式"); Text("结果"); Text("")
                            }
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Divider().gridCellColumns(5)
                            ForEach(model.items) { item in
                                GridRow {
                                    Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                        .frame(minWidth: 160, alignment: .leading)
                                    Text(item.profile ?? "—")
                                        .foregroundStyle(item.profile == nil || item.profile == "Profile 0" ? Color.primary : .orange)
                                    Text(item.pixFmt ?? "—")
                                        .foregroundStyle(item.pixFmt == nil || item.pixFmt == "yuv420p" ? Color.primary : .orange)
                                    stateView(item.state).frame(width: 190, alignment: .leading)
                                    HStack(spacing: 6) {
                                        Button { revealInFinder([doneURL(item) ?? item.url]) } label: {
                                            Image(systemName: "magnifyingglass")
                                        }.help("在 Finder 中显示")
                                        Button { model.remove(item.id) } label: { Image(systemName: "xmark") }
                                            .help("从列表移除").disabled(model.isRunning)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .font(.callout)
                            }
                        }
                        Text("橙色表示 Safari 不支持的值。Safari 需要 Profile 0 + yuv420p。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                PageFooter(glossary: [Terms.profile, Terms.pixFmt, Terms.crf,
                                      ("为什么会这样", "很多软件导出 WebM 时默认用了更高的色彩档次（Profile 1/2/3 或 yuv444p），Chrome 能播，但 Safari 和 iPhone 只认最基础的 Profile 0。")],
                           log: model.log.lines)
            }
            .padding(24)
        }
    }

    private func doneURL(_ item: VP9Item) -> URL? {
        if case .done(let u, _) = item.state { return u }
        return nil
    }

    @ViewBuilder
    private func stateView(_ s: VP9ItemState) -> some View {
        switch s {
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("检测中").foregroundStyle(.secondary) }
        case .compliant:
            Label("没问题，无需转换", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
        case .notVP9(let c):
            Label("不是 VP9（\(c)），跳过", systemImage: "arrow.uturn.right").foregroundStyle(.secondary)
        case .needsConvert:
            Label("Safari 播不了，待转换", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .converting(let p):
            HStack(spacing: 6) {
                ProgressView(value: p).frame(width: 100)
                Text("\(Int(p * 100))%").monospacedDigit().font(.caption)
            }
        case .done(let u, let size):
            Label("\(u.lastPathComponent.hasSuffix("_p0.webm") ? "已转换" : "完成") \(size.map(Fmt.bytes) ?? "")",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let m):
            Label("失败", systemImage: "xmark.octagon.fill").foregroundStyle(.red).help(m)
        case .cancelled:
            Label("已取消", systemImage: "minus.circle").foregroundStyle(.secondary)
        }
    }
}
