//
//  ShareViewController.swift
//  YatteeShareExtension
//
//  Handles shared URLs and opens them in Yattee.
//
//  Yattee Y: a shared YouTube video gets a small card with 现在播 (open in the
//  app, as before) and 稍后看 (put it on the "从 YouTube 带来的" row without
//  leaving YouTube). 稍后看 posts to our Yattee Server with the address and login
//  the app leaves in the app group keychain; without them, the pick waits in the
//  app group inbox until the app next opens. Other links open the app directly.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Must match YouTubePicks in the app.
private enum Shared {
    static let appGroup = "group.com.yuweiliang.yattee.shared"
    static let inboxKey = "yatteeY.pickInbox"
    static let bridgeService = "com.yuweiliang.yattee.sharebridge"
    static let bridgeAccount = "yatteeServer"
}

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleSharedItems()
    }

    private func handleSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            close()
            return
        }

        for extensionItem in extensionItems {
            guard let attachments = extensionItem.attachments else { continue }

            for attachment in attachments {
                // Try to get URL first
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                        DispatchQueue.main.async {
                            if let url = item as? URL {
                                self?.received(url)
                            } else {
                                self?.close()
                            }
                        }
                    }
                    return
                }

                // Try plain text (might contain a URL)
                if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                        DispatchQueue.main.async {
                            if let text = item as? String, let url = self?.extractURL(from: text) {
                                self?.received(url)
                            } else {
                                self?.close()
                            }
                        }
                    }
                    return
                }
            }
        }

        close()
    }

    private func received(_ url: URL) {
        guard let videoID = Self.youTubeVideoID(in: url) else {
            openInYattee(url: url)
            return
        }
        let card = ShareCard(
            videoID: videoID,
            playNow: { [weak self] in self?.openInYattee(url: url) },
            close: { [weak self] in self?.close() }
        )
        let host = UIHostingController(rootView: card)
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    /// watch?v=, youtu.be/, shorts/, live/ and embed/ links; nil for anything else.
    static func youTubeVideoID(in url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let isYouTube = host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
        guard isYouTube else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        var candidate: String?
        if host == "youtu.be" {
            candidate = parts.first
        } else if parts.first == "watch" {
            candidate = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "v" })?.value
        } else if let first = parts.first, ["shorts", "live", "embed", "v"].contains(first), parts.count > 1 {
            candidate = parts[1]
        }
        guard let id = candidate, id.count == 11,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        return id
    }

    private func extractURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           url.scheme == "http" || url.scheme == "https" {
            return url
        }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        if let match = detector?.firstMatch(in: text, options: [], range: range),
           let url = match.url {
            return url
        }

        return nil
    }

    private func openInYattee(url: URL) {
        guard let encodedURL = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let yatteeURL = URL(string: "yattee://open?url=\(encodedURL)") else {
            close()
            return
        }

        openURLViaApplication(yatteeURL)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.close()
        }
    }

    private func openURLViaApplication(_ url: URL) {
        let sharedSelector = NSSelectorFromString("sharedApplication")

        guard let appClass = NSClassFromString("UIApplication") as? NSObject.Type,
              appClass.responds(to: sharedSelector),
              let shared = appClass.perform(sharedSelector)?.takeUnretainedValue() else {
            return
        }

        typealias OpenURLMethod = @convention(c) (AnyObject, Selector, URL, [UIApplication.OpenExternalURLOptionsKey: Any], ((Bool) -> Void)?) -> Void

        let openSelector = NSSelectorFromString("openURL:options:completionHandler:")
        guard shared.responds(to: openSelector) else { return }

        let methodIMP = shared.method(for: openSelector)
        let method = unsafeBitCast(methodIMP, to: OpenURLMethod.self)
        method(shared, openSelector, url, [:], nil)
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

// MARK: - Card

private struct ShareCard: View {
    let videoID: String
    let playNow: () -> Void
    let close: () -> Void

    @State private var title: String?
    @State private var author: String?
    @State private var state: SaveState = .idle

    enum SaveState: Equatable {
        case idle, saving
        case done(String)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { if state == .idle { close() } }

            VStack(spacing: 14) {
                Capsule().fill(.secondary.opacity(0.5)).frame(width: 40, height: 5)

                HStack(alignment: .top, spacing: 12) {
                    AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg")) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.secondary.opacity(0.2)
                    }
                    .frame(width: 128, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title ?? "YouTube 视频")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(3)
                        if let author {
                            Text(author).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }

                switch state {
                case .done(let message):
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, minHeight: 48)
                default:
                    HStack(spacing: 10) {
                        Button(action: playNow) {
                            Label("现在播", systemImage: "play.fill")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            Task { await saveForLater() }
                        } label: {
                            Group {
                                if state == .saving {
                                    ProgressView()
                                } else {
                                    Label("稍后看", systemImage: "text.badge.plus")
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .disabled(state == .saving)
                    }
                    .font(.headline)
                }
            }
            .padding(16)
            .padding(.bottom, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .task { await loadTitle() }
    }

    /// Title and channel from YouTube's public oEmbed endpoint (no login involved).
    private func loadTitle() async {
        var components = URLComponents(string: "https://www.youtube.com/oembed")
        components?.queryItems = [
            URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(videoID)"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        title = json["title"] as? String
        author = json["author_name"] as? String
    }

    private func saveForLater() async {
        state = .saving
        if let count = await postToServer() {
            state = .done(count > 0 ? "已存到 从 YouTube 带来的（\(count) 个）" : "已存到 从 YouTube 带来的")
        } else {
            saveToInbox()
            state = .done("已存，下次打开 Yattee Y 时同步")
        }
        try? await Task.sleep(for: .seconds(1.1))
        close()
    }

    /// Returns the row's new size, or nil when the server could not be reached.
    private func postToServer() async -> Int? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Shared.bridgeService,
            kSecAttrAccount as String: Shared.bridgeAccount,
            kSecAttrAccessGroup as String: Shared.appGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let bridge = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let base = bridge["url"].flatMap(URL.init(string:)) else { return nil }

        var request = URLRequest(url: base.appending(path: "api/v1/recommended/picks"), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth = bridge["auth"] { request.setValue(auth, forHTTPHeaderField: "Authorization") }
        var body: [String: String] = ["videoId": videoID, "origin": "share"]
        if let title { body["title"] = title }
        if let author { body["author"] = author }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (responseData, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        return json?["count"] as? Int ?? 0
    }

    private func saveToInbox() {
        let defaults = UserDefaults(suiteName: Shared.appGroup)
        var inbox = defaults?.array(forKey: Shared.inboxKey) as? [[String: String]] ?? []
        var entry = ["videoId": videoID, "origin": "share"]
        if let title { entry["title"] = title }
        inbox.removeAll { $0["videoId"] == videoID }
        inbox.append(entry)
        defaults?.set(inbox, forKey: Shared.inboxKey)
    }
}
