import Foundation
import AppKit

/// 通过 GitHub Releases 检查和安装新版本。
///
/// - 「自动检查更新」：启动时和之后每 24 小时检查一次，发现新版本弹窗提示。
/// - 「自动下载并安装」：发现新版本后在后台下载，退出应用时自动替换，下次打开就是新版本。
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    static let autoCheckKey = "autoCheckUpdates"
    static let autoInstallKey = "autoInstallUpdates"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let skippedVersionKey = "skippedUpdateVersion"

    static let repo = "itinglight/ReelLite"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case downloading(String)
        case readyToInstall(String)
        case failed(String)

        var text: String {
            switch self {
            case .idle: return ""
            case .checking: return "正在检查…"
            case .upToDate: return "已是最新版本"
            case .available(let v): return "发现新版本 \(v)"
            case .downloading(let v): return "正在下载 \(v)…"
            case .readyToInstall(let v): return "\(v) 已下载，退出应用时自动安装"
            case .failed(let m): return "检查失败：\(m)"
            }
        }
    }

    struct Release {
        let version: String
        let notes: String
        let pageURL: URL
        let dmgURL: URL?
    }

    @Published private(set) var status: Status = .idle

    /// 已下载并解出、等待安装的新版 .app
    private var stagedApp: URL?
    private var timer: Timer?

    private init() {
        UserDefaults.standard.register(defaults: [Self.autoCheckKey: true, Self.autoInstallKey: false])
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// 通过 `swift run` 启动时没有 .app bundle，只能检查，不能自动安装
    static var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    private var autoCheck: Bool { UserDefaults.standard.bool(forKey: Self.autoCheckKey) }
    private var autoInstall: Bool { UserDefaults.standard.bool(forKey: Self.autoInstallKey) }

    // MARK: - 定时检查

    func start() {
        timer?.invalidate()
        // 每小时看一眼是否到了检查时间；开关随时可以在设置里改
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            Task { @MainActor in Updater.shared.checkIfDue() }
        }
        Task {
            try? await Task.sleep(for: .seconds(3))   // 等主窗口出来再检查
            checkIfDue()
        }
    }

    private func checkIfDue() {
        guard autoCheck else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last >= Self.checkInterval else { return }
        Task { await check(userInitiated: false) }
    }

    // MARK: - 检查

    /// - Parameter userInitiated: 用户手动点「检查更新」时为 true，会显示“已是最新”等结果，也不受“跳过此版本”影响
    func check(userInitiated: Bool) async {
        switch status {
        case .checking, .downloading: return
        case .readyToInstall(let v):
            if userInitiated { promptInstallNow(version: v) }
            return
        default: break
        }

        status = .checking
        let release: Release
        do {
            release = try await fetchLatest()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
        } catch {
            status = .failed(error.localizedDescription)
            if userInitiated { showError("检查更新失败", error) }
            return
        }

        guard Self.isNewer(release.version, than: Self.currentVersion) else {
            status = .upToDate
            if userInitiated {
                let alert = NSAlert()
                alert.messageText = "已是最新版本"
                alert.informativeText = "当前版本 \(Self.currentVersion) 就是最新版。"
                alert.runModal()
            }
            return
        }

        status = .available(release.version)

        if !userInitiated {
            if UserDefaults.standard.string(forKey: Self.skippedVersionKey) == release.version { return }
            if autoInstall && canInstallInPlace && release.dmgURL != nil {
                await download(release, installImmediately: false)
                return
            }
        }
        promptAvailable(release)
    }

    private func fetchLatest() async throws -> Release {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("ReelLite/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ToolError.message("无效的响应") }
        guard http.statusCode == 200 else { throw ToolError.message("GitHub 返回 \(http.statusCode)") }

        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Payload: Decodable { let tag_name: String; let body: String?; let html_url: URL; let assets: [Asset] }
        let p = try JSONDecoder().decode(Payload.self, from: data)

        let version = p.tag_name.hasPrefix("v") ? String(p.tag_name.dropFirst()) : p.tag_name
        let dmg = p.assets.first { $0.name.lowercased().hasSuffix(".dmg") }?.browser_download_url
        return Release(version: version, notes: p.body ?? "", pageURL: p.html_url, dmgURL: dmg)
    }

    /// 按数字逐段比较版本号，如 0.0.10 > 0.0.9
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // MARK: - 弹窗

    private func promptAvailable(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "轻片 \(release.version) 可以更新了"
        let notes = release.notes.count > 600 ? String(release.notes.prefix(600)) + "…" : release.notes
        alert.informativeText = "当前版本 \(Self.currentVersion)。\n\n\(notes)"

        let installable = canInstallInPlace && release.dmgURL != nil
        alert.addButton(withTitle: installable ? "立即更新" : "前往下载")
        alert.addButton(withTitle: "稍后")
        alert.addButton(withTitle: "跳过此版本")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if installable {
                Task { await download(release, installImmediately: true) }
            } else {
                NSWorkspace.shared.open(release.pageURL)
            }
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.version, forKey: Self.skippedVersionKey)
        default:
            break
        }
    }

    private func promptInstallNow(version: String) {
        let alert = NSAlert()
        alert.messageText = "轻片 \(version) 已下载好"
        alert.informativeText = "现在重启轻片完成安装吗？不重启的话，下次退出时也会自动安装。"
        alert.addButton(withTitle: "立即重启")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn { installAndRelaunch() }
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    // MARK: - 下载

    /// 应用所在位置能否直接被替换（从 DMG 里直接打开、被系统隔离运行、目录没有写权限时都不行）
    var canInstallInPlace: Bool {
        guard Self.isBundled else { return false }
        let path = Bundle.main.bundlePath
        if path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/") { return false }
        let parent = (path as NSString).deletingLastPathComponent
        return FileManager.default.isWritableFile(atPath: parent)
            && FileManager.default.isWritableFile(atPath: path)
    }

    private func download(_ release: Release, installImmediately: Bool) async {
        guard let dmgURL = release.dmgURL else { return }
        status = .downloading(release.version)
        do {
            let app = try await Self.downloadAndExtract(dmgURL, expectedVersion: release.version)
            stagedApp = app
            status = .readyToInstall(release.version)
            if installImmediately { installAndRelaunch() }
        } catch {
            status = .failed(error.localizedDescription)
            if installImmediately { showError("下载更新失败", error) }
        }
    }

    /// 下载 DMG，挂载后把里面的 .app 复制到缓存目录，并核对 Bundle ID 和版本号
    private nonisolated static func downloadAndExtract(_ url: URL, expectedVersion: String) async throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("ReelLiteUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        var req = URLRequest(url: url)
        req.setValue("ReelLite", forHTTPHeaderField: "User-Agent")
        let (tmp, response) = try await URLSession.shared.download(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ToolError.message("下载失败（HTTP \(http.statusCode)）")
        }
        let dmg = work.appendingPathComponent("update.dmg")
        try fm.moveItem(at: tmp, to: dmg)

        let mount = work.appendingPathComponent("mnt")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        defer { try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }

        guard let name = try fm.contentsOfDirectory(atPath: mount.path).first(where: { $0.hasSuffix(".app") }) else {
            throw ToolError.message("安装包里没有找到应用")
        }
        let staged = work.appendingPathComponent(name)
        try run("/usr/bin/ditto", [mount.appendingPathComponent(name).path, staged.path])

        guard let info = Bundle(url: staged)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw ToolError.message("安装包里的应用和当前应用不一致")
        }
        if let v = info["CFBundleShortVersionString"] as? String, v != expectedVersion {
            throw ToolError.message("安装包版本（\(v)）和发布版本（\(expectedVersion)）不一致")
        }
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        return staged
    }

    private nonisolated static func run(_ exe: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        let err = Pipe()
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ToolError.failed(p.terminationStatus, msg)
        }
    }

    // MARK: - 安装

    /// 立即退出并安装，装好后重新打开
    func installAndRelaunch() {
        guard stagedApp != nil else { return }
        launchInstaller(relaunch: true)
        NSApp.terminate(nil)
    }

    /// 退出应用时调用：有已下载的更新就安装（不重新打开）
    func installOnQuitIfNeeded() {
        guard stagedApp != nil, !installerLaunched else { return }
        launchInstaller(relaunch: false)
    }

    private var installerLaunched = false

    /// 启动一个独立的脚本：等当前进程退出后替换 .app
    private func launchInstaller(relaunch: Bool) {
        guard let staged = stagedApp, !installerLaunched else { return }
        installerLaunched = true

        let target = Bundle.main.bundlePath
        let backup = target + ".old"
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "$BACKUP"
        mv "$TARGET" "$BACKUP" || exit 1
        if /usr/bin/ditto "$STAGED" "$TARGET"; then
          rm -rf "$BACKUP"
        else
          rm -rf "$TARGET"; mv "$BACKUP" "$TARGET"
        fi
        rm -rf "$(dirname "$STAGED")"
        [ "$RELAUNCH" = 1 ] && /usr/bin/open "$TARGET"
        exit 0
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", script]
        p.environment = [
            "TARGET": target, "BACKUP": backup, "STAGED": staged.path,
            "RELAUNCH": relaunch ? "1" : "0", "PATH": "/usr/bin:/bin",
        ]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
