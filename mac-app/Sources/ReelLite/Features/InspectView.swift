import SwiftUI

struct InspectReport: Identifiable {
    let id = UUID()
    let url: URL
    var size: Int64?
    var probe: ProbeResult?
    var error: String?
    var loading = true
}

@MainActor @Observable
final class InspectModel {
    var reports: [InspectReport] = []
    var isRunning: Bool { reports.contains { $0.loading } }

    func add(_ urls: [URL]) {
        for url in urls {
            let report = InspectReport(url: url, size: Fmt.fileSize(url))
            reports.insert(report, at: 0)
            let id = report.id
            Task {
                do {
                    let p = try await FFprobe.probe(url)
                    update(id) { $0.probe = p; $0.loading = false }
                } catch {
                    update(id) { $0.error = error.localizedDescription; $0.loading = false }
                }
            }
        }
    }

    func remove(_ id: UUID) { reports.removeAll { $0.id == id } }
    func clear() { reports.removeAll() }

    private func update(_ id: UUID, _ change: (inout InspectReport) -> Void) {
        if let i = reports.firstIndex(where: { $0.id == id }) { change(&reports[i]) }
    }
}

struct InspectView: View {
    @Bindable var model: InspectModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "检查视频",
                           subtitle: "看看视频是什么格式、清晰度多少，以及 Chrome 和 Safari 能不能正常播放",
                           icon: "stethoscope")

                DropZone(title: "把视频拖到这里，或点击选择", subtitle: "可以一次放入多个视频",
                         allowsMultiple: true, compact: !model.reports.isEmpty) { model.add($0) }

                if !model.reports.isEmpty {
                    HStack {
                        Text("共 \(model.reports.count) 个视频").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("清空") { model.clear() }.buttonStyle(.borderless)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(model.reports) { report in
                        ReportCard(report: report) { model.remove(report.id) }
                    }
                }

                PageFooter(glossary: [Terms.codec, Terms.profile, Terms.pixFmt, Terms.fps, Terms.bitrate,
                                      ("兼容性评分", "5 分表示该浏览器能稳定播放；1 分表示基本播不了，需要转换。")],
                           log: [])
            }
            .padding(24)
        }
    }
}

private struct ReportCard: View {
    var report: InspectReport
    var onRemove: () -> Void

    var body: some View {
        Card {
            HStack {
                Text(report.url.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button { revealInFinder([report.url]) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless).help("在 Finder 中显示")
                Button(action: onRemove) { Image(systemName: "xmark") }.buttonStyle(.borderless).help("移除")
            }
            if report.loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else if let err = report.error {
                Label(err, systemImage: "xmark.octagon").foregroundStyle(.red).font(.callout)
            } else if let probe = report.probe {
                content(probe)
            }
        }
    }

    @ViewBuilder
    private func content(_ probe: ProbeResult) -> some View {
        let v = probe.video
        let compat = Compatibility.evaluate(v)
        // 结论放最上面
        HStack(spacing: 10) {
            Image(systemName: compat.safari >= 4 ? "checkmark.seal.fill" : compat.safari == 0 ? "questionmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(compat.safari >= 4 ? Color.green : compat.safari == 0 ? .secondary : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(compat.remark).font(.callout.weight(.semibold))
                Text(advice(compat, v)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.07)))

        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text("Chrome").foregroundStyle(.secondary)
                ScoreView(score: compat.chrome)
            }
            GridRow {
                Text("Safari").foregroundStyle(.secondary)
                ScoreView(score: compat.safari)
            }
        }
        .font(.callout)
        Divider()
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            row("编码", v.map { "\($0.codecName ?? "?")  ·  \($0.codecLongName ?? "-")" } ?? "无视频流",
                help: "视频的压缩算法")
            row("Profile", v?.profile ?? "-", help: "编码档次，VP9 只有 Profile 0 能在 Safari 播放")
            row("分辨率", v.flatMap { s in s.width.map { "\($0) × \(s.height ?? 0)" } } ?? "-",
                help: "画面的宽 × 高（像素）")
            row("帧率", v?.fps.map { String(format: "%.2f 帧/秒", $0) } ?? "-", help: "每秒画面数，越高越流畅")
            row("像素格式", v?.pixFmt ?? "-", help: "颜色存储方式，yuv420p 兼容性最好")
            row("码率", Fmt.kbps(v?.bitRate ?? probe.format?.bitRate), help: "每秒数据量，越高通常越清晰")
            row("时长", probe.duration.map(Fmt.duration) ?? "-", help: "视频总长度")
            row("声音", probe.audio.map { "有（\($0.codecName ?? "?")）" } ?? "无", help: "是否包含音轨")
            row("文件大小", report.size.map(Fmt.bytes) ?? "-", help: "占用的磁盘空间")
        }
    }

    private func advice(_ c: Compatibility, _ v: ProbeStream?) -> String {
        if v?.codecName == "vp9" && c.safari < 4 { return "可以到「修复 Safari 播放」里一键转换" }
        if c.safari == 0 { return "不常见的编码，建议到「压缩视频」里转成 VP9 或 AV1" }
        return "可以直接用在网页上"
    }

    private func row(_ k: String, _ value: String, help: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary).help(help)
            Text(value).textSelection(.enabled).lineLimit(2).help(help)
        }
        .font(.callout)
    }
}
