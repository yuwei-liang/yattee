//
//  YouTubePicks.swift
//  Yattee
//
//  Yattee Y: videos the viewer brings over from YouTube itself ("从 YouTube 带来的").
//  They live on our Yattee Server, so iPhone, Mac and Apple TV show the same row,
//  and the curator treats them as the viewer's own picks.
//
//  Ways in: the share extension's 稍后看 (posts directly, or leaves the pick in
//  the app group inbox when it cannot), `yattee://pick?url=…` (the Mac
//  bookmarklet), and the row's own remove button. A pick leaves the row once
//  most of it has been watched.
//

import Foundation
import Observation
import Security
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
@Observable
final class YouTubePicks {
    static let shared = YouTubePicks()

    /// The row, newest first.
    private(set) var videos: [Video] = []
    /// A web link sits on the clipboard that the viewer has not been offered yet.
    private(set) var clipboardOffer = false

    /// Share of a video that counts as watched (matches the server's PICK_DONE_SHARE).
    static let doneShare = 0.8

    /// App group keys shared with the share extension (string literals there too).
    static let inboxKey = "yatteeY.pickInbox"
    static let bridgeService = "com.yuweiliang.yattee.sharebridge"
    static let bridgeAccount = "yatteeServer"

    private var lastClipboardChange = -1

    private init() {}

    private var server: Instance? {
        AppEnvironment.shared.instancesManager.enabledYatteeServerInstances.first
    }

    // MARK: - Row

    func reload() async {
        guard let server else {
            videos = []
            return
        }
        do {
            videos = try await AppEnvironment.shared.contentService.youTubePicks(instance: server)
        } catch {
            LoggingService.shared.warning("Picks not loaded: \(error.localizedDescription)", category: .general)
        }
    }

    /// Adds a YouTube link to the row. Returns false (after telling the viewer) when it can't.
    @discardableResult
    func add(url: URL, origin: String, quiet: Bool = false) async -> Bool {
        guard let videoID = Self.youTubeVideoID(in: url) else {
            if !quiet {
                AppEnvironment.shared.toastManager.showError("只能带 YouTube 视频", subtitle: url.absoluteString)
            }
            return false
        }
        return await add(videoID: videoID, title: nil, origin: origin, quiet: quiet)
    }

    @discardableResult
    func add(videoID: String, title: String?, origin: String, quiet: Bool = false) async -> Bool {
        let toasts = AppEnvironment.shared.toastManager
        guard let server else {
            if !quiet { toasts.showError("没有启用的 Yattee Server 源") }
            return false
        }
        do {
            let body = YouTubePickBody(videoId: videoID, title: title, author: nil, origin: origin)
            let response = try await AppEnvironment.shared.contentService.addYouTubePick(body, instance: server)
            if !quiet {
                let count = response.count.map { "（\($0) 个）" } ?? ""
                toasts.showSuccess("已存到 从 YouTube 带来的\(count)", subtitle: response.title)
            }
            await reload()
            return true
        } catch {
            if !quiet { toasts.showError("没存上", subtitle: error.localizedDescription) }
            return false
        }
    }

    func remove(_ video: Video) {
        videos.removeAll { $0.id == video.id }
        guard let server else { return }
        let videoID = video.id.videoID
        Task {
            try? await AppEnvironment.shared.contentService.removeYouTubePick(videoID: videoID, instance: server)
        }
    }

    /// A watch report went out; drop a pick that was mostly watched (the server does the same).
    func watched(videoID: String, watched: TimeInterval, duration: TimeInterval, ended: Bool) {
        guard ended || (duration > 0 && watched >= Self.doneShare * duration) else { return }
        videos.removeAll { $0.id.videoID == videoID }
    }

    // MARK: - App lifecycle

    /// Called whenever the app comes to the front.
    func appBecameActive() {
        Task {
            await writeShareBridge()
            await flushInbox()
            await reload()
        }
        checkClipboard()
    }

    /// Picks the share extension could not send itself.
    private func flushInbox() async {
        let defaults = AppGroup.defaults
        guard let inbox = defaults.array(forKey: Self.inboxKey) as? [[String: String]], !inbox.isEmpty else { return }
        defaults.removeObject(forKey: Self.inboxKey)
        var left: [[String: String]] = []
        for entry in inbox {
            guard let videoID = entry["videoId"] else { continue }
            if !(await add(videoID: videoID, title: entry["title"], origin: entry["origin"] ?? "share", quiet: true)) {
                left.append(entry)
            }
        }
        if !left.isEmpty {
            defaults.set(left, forKey: Self.inboxKey)
        } else {
            AppEnvironment.shared.toastManager.showSuccess("已同步 \(inbox.count) 个从 YouTube 带来的视频")
        }
    }

    /// Hands the server address and login to the share extension through the app
    /// group's keychain, so 稍后看 works without opening the app. Device-only, never synced.
    private func writeShareBridge() async {
        #if os(iOS)
        guard let server else { return }
        let header = AppEnvironment.shared.basicAuthCredentialsManager.basicAuthHeader(for: server)
        var payload = ["url": server.url.absoluteString]
        if let header { payload["auth"] = header }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.bridgeService,
            kSecAttrAccount as String: Self.bridgeAccount,
            kSecAttrAccessGroup as String: AppGroup.identifier,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        } else if status != errSecSuccess {
            LoggingService.shared.warning("Share bridge not written: \(status)", category: .general)
        }
        #endif
    }

    // MARK: - Clipboard

    /// Offers a "paste" banner when a web link was copied since the last offer.
    /// Only asks the system whether there is a link, so no paste permission prompt shows.
    func checkClipboard() {
        #if os(iOS)
        let board = UIPasteboard.general
        guard board.changeCount != lastClipboardChange else { return }
        lastClipboardChange = board.changeCount
        board.detectPatterns(for: [.probableWebURL]) { result in
            let found = (try? result.get())?.contains(.probableWebURL) ?? false
            Task { @MainActor in self.clipboardOffer = found }
        }
        #elseif os(macOS)
        let board = NSPasteboard.general
        guard board.changeCount != lastClipboardChange else { return }
        lastClipboardChange = board.changeCount
        guard #available(macOS 15.4, *) else { return }
        board.detectPatterns(for: [.probableWebURL]) { result in
            let found = (try? result.get())?.contains(.probableWebURL) ?? false
            Task { @MainActor in self.clipboardOffer = found }
        }
        #endif
    }

    func dismissClipboardOffer() {
        clipboardOffer = false
    }

    // MARK: - Links

    static func youTubeVideoID(in url: URL) -> String? {
        let router = URLRouter()
        guard case .video(let source, _) = router.route(router.unwrapped(url)),
              case .id(let id) = source,
              case .global(let provider) = id.source, provider == ContentSource.youtubeProvider
        else { return nil }
        return id.videoID
    }

    /// `yattee://pick?url=<encoded link>`: put the link on the row instead of playing it.
    static func pickLink(in url: URL) -> URL? {
        guard url.scheme?.lowercased() == "yattee", url.host?.lowercased() == "pick",
              let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value
        else { return nil }
        return URL(string: raw)
    }
}
