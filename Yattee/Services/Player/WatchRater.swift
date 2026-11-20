//
//  WatchRater.swift
//  Yattee
//
//  Yattee Y: after a watch, tell the recommender how it went. Every watch of a
//  YouTube video reports seconds watched of the length; a long enough one also
//  asks for a one-tap rating (爽 / 涨知识 / 被带节奏了 / 一般) that the curator
//  weighs above clicks.
//

import Foundation
import Observation

@MainActor
@Observable
final class WatchRater {
    static let shared = WatchRater()

    enum Rating: String, CaseIterable, Identifiable {
        case fun, learn, manipulative, meh
        var id: String { rawValue }
        var label: String {
            switch self {
            case .fun: "爽"
            case .learn: "涨知识"
            case .manipulative: "被带节奏了"
            case .meh: "一般"
            }
        }
    }

    enum Stage { case rate, followUp }

    struct Prompt: Identifiable {
        let id = UUID()
        let video: Video
        let watched: TimeInterval
        let duration: TimeInterval
        let ended: Bool
        var selected: Set<Rating> = []
        var stage: Stage = .rate
    }

    /// The question on screen, if any.
    private(set) var prompt: Prompt?

    /// Seconds before an untouched prompt closes by itself.
    static let autoClose: Duration = .seconds(8)
    /// Shorter wait after a tap, so the answer goes out soon.
    static let closeAfterTap: Duration = .seconds(2.5)
    static let minimumLength: TimeInterval = 180
    static let minimumWatchToAsk: TimeInterval = 300
    /// Prompts ignored in a row before taking a break, and how many to skip then.
    static let ignoredLimit = 3
    static let breakLength = 5

    private var asked: Set<String> = []
    private var ignoredInARow = 0
    private var skipNext = 0
    private var closeTask: Task<Void, Never>?
    /// The last watch reported, so the several ways a watch can end report it once.
    private var lastReported: (id: String, at: Date)?

    private init() {}

    // MARK: - From the player

    /// A watch is over: the video ended, another one replaced it, or the player closed.
    func watchEnded(video: Video, watched: TimeInterval, duration: TimeInterval, ended: Bool) {
        guard isYouTube(video), server != nil, duration > 0, !video.isLive else { return }
        let videoID = video.id.videoID
        if let last = lastReported, last.id == videoID, Date().timeIntervalSince(last.at) < 10 { return }
        lastReported = (videoID, Date())
        let watched = min(max(0, watched), duration)

        if let current = prompt {
            send(current, followUp: nil)
            prompt = nil
        }

        guard shouldAsk(video: video, watched: watched, duration: duration, ended: ended) else {
            if watched >= 10 {
                send(Prompt(video: video, watched: watched, duration: duration, ended: ended), followUp: nil)
            }
            return
        }
        asked.insert(video.id.videoID)
        prompt = Prompt(video: video, watched: watched, duration: duration, ended: ended)
        scheduleClose(after: Self.autoClose)
    }

    private func shouldAsk(video: Video, watched: TimeInterval, duration: TimeInterval, ended: Bool) -> Bool {
        guard duration >= Self.minimumLength, !asked.contains(video.id.videoID) else { return false }
        #if os(tvOS)
        // On TV, leaving mid-video usually means getting up; only ask at the end.
        guard ended else { return false }
        #else
        guard ended || watched >= Self.minimumWatchToAsk else { return false }
        #endif
        if skipNext > 0 {
            skipNext -= 1
            return false
        }
        return true
    }

    // MARK: - From the bar

    func toggle(_ rating: Rating) {
        guard var current = prompt else { return }
        if rating == .manipulative {
            current.selected = [.manipulative]
            current.stage = .followUp
            prompt = current
            closeTask?.cancel()
            scheduleClose(after: .seconds(15))
            return
        }
        if current.selected.contains(rating) {
            current.selected.remove(rating)
        } else {
            if rating == .meh { current.selected = [] } else { current.selected.remove(.meh) }
            current.selected.insert(rating)
        }
        prompt = current
        scheduleClose(after: Self.closeAfterTap)
    }

    /// 被带节奏了 → 少推这个频道 / 交给 unspin / 不用了.
    func followUp(lessChannel: Bool, unspin: Bool) {
        guard let current = prompt else { return }
        if unspin { UnspinSubmitter.submit(current.video, in: AppEnvironment.shared) }
        finish(followUp: lessChannel ? "less_channel" : nil)
    }

    /// Close now and send what was chosen (nothing chosen counts as ignored).
    func finish(followUp: String? = nil) {
        guard let current = prompt else { return }
        closeTask?.cancel()
        prompt = nil
        if current.selected.isEmpty {
            ignoredInARow += 1
            if ignoredInARow >= Self.ignoredLimit {
                ignoredInARow = 0
                skipNext = Self.breakLength
            }
        } else {
            ignoredInARow = 0
        }
        send(current, followUp: followUp)
        if !current.selected.isEmpty {
            _ = AppEnvironment.shared.toastManager.showSuccess(
                current.selected.contains(.manipulative) ? "收到，以后少推这种" : "收到，推荐会参考")
        }
    }

    // MARK: - Helpers

    private func scheduleClose(after delay: Duration) {
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private var server: Instance? {
        AppEnvironment.shared.instancesManager.enabledYatteeServerInstances.first
    }

    private func isYouTube(_ video: Video) -> Bool {
        if case .global(let provider) = video.id.source { return provider == ContentSource.youtubeProvider }
        return false
    }

    private func send(_ prompt: Prompt, followUp: String?) {
        guard let server else { return }
        let report = WatchReport(
            videoId: prompt.video.id.videoID,
            title: prompt.video.title,
            author: prompt.video.author.name,
            watched: prompt.watched.rounded(),
            duration: prompt.duration.rounded(),
            ended: prompt.ended,
            ratings: Rating.allCases.filter(prompt.selected.contains).map(\.rawValue),
            followUp: followUp
        )
        let contentService = AppEnvironment.shared.contentService
        Task {
            do {
                try await contentService.sendWatchReport(report, instance: server)
            } catch {
                LoggingService.shared.warning("Watch report not sent: \(error.localizedDescription)", category: .player)
            }
        }
    }
}
