//
//  YatteeServerAPI+Recommendations.swift
//  Yattee
//
//  Yattee Y: the personal recommendation endpoints on our Yattee Server
//  (feedback from the home feed, and "换一批" rebuilds).
//

import Foundation

/// Feedback the home feed can send about a recommended video.
enum RecommendationFeedback: String, Sendable, CaseIterable {
    case more      // 多来点这种
    case deeper    // 顺着这个深挖
    case less      // 不感兴趣
    case channel   // 别再推这个频道
}

private struct RecommendationFeedbackBody: Encodable, Sendable {
    let videoId: String
    let action: String
    let reason: String?
}

private struct RecommendationFeedbackResponse: Decodable, Sendable {
    let ok: Bool
    let removed: Int?
}

private struct RecommendationRebuildResponse: Decodable, Sendable {
    let results: Int
}

/// How a watch went, for the curator: seconds watched of the length, and the one-tap rating.
struct WatchReport: Encodable, Sendable {
    let videoId: String
    let title: String?
    let author: String?
    let watched: Double
    let duration: Double
    let ended: Bool
    let ratings: [String]
    let followUp: String?
}

private struct OKResponse: Decodable, Sendable {
    let ok: Bool
}

private struct RecommendationStatusResponse: Decodable, Sendable {
    let note: String?
}

extension YatteeServerAPI {
    /// Sends one piece of feedback. Returns how many items the server dropped from the list.
    @discardableResult
    func sendRecommendationFeedback(
        videoID: String, action: RecommendationFeedback, reason: String?, instance: Instance
    ) async throws -> Int {
        let body = RecommendationFeedbackBody(videoId: videoID, action: action.rawValue, reason: reason)
        let endpoint = GenericEndpoint.post("/api/v1/recommended/feedback", body: body)
        let response: RecommendationFeedbackResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.removed ?? 0
    }

    /// Asks Claude for a fresh list now (takes about a minute; costs one curator call).
    func rebuildRecommendations(instance: Instance) async throws -> Int {
        let endpoint = GenericEndpoint(path: "/api/v1/recommended/rebuild", method: .post, timeout: 300)
        let response: RecommendationRebuildResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.results
    }

    func sendWatchReport(_ report: WatchReport, instance: Instance) async throws {
        let endpoint = GenericEndpoint.post("/api/v1/recommended/watch-report", body: report)
        let _: OKResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)
    }

    /// What the last curated round changed because of the viewer's feedback ("" when nothing).
    func recommendationNote(instance: Instance) async throws -> String {
        let response: RecommendationStatusResponse = try await httpClient.fetch(
            GenericEndpoint.get("/api/v1/recommended/status"), baseURL: instance.url)
        return response.note ?? ""
    }
}

/// A video brought over from YouTube, for the home row "从 YouTube 带来的".
struct YouTubePickBody: Encodable, Sendable {
    let videoId: String
    let title: String?
    let author: String?
    let origin: String?
}

struct YouTubePickResponse: Decodable, Sendable {
    let ok: Bool
    let title: String?
    let count: Int?
}

extension YatteeServerAPI {
    /// The row: picks not watched yet, newest first.
    func youTubePicks(instance: Instance) async throws -> [Video] {
        let response: [YatteeVideo] = try await httpClient.fetch(
            GenericEndpoint.get("/api/v1/recommended/picks"), baseURL: instance.url)
        return response.map { $0.toVideo() }
    }

    func addYouTubePick(_ body: YouTubePickBody, instance: Instance) async throws -> YouTubePickResponse {
        let endpoint = GenericEndpoint.post("/api/v1/recommended/picks", body: body)
        return try await httpClient.fetch(endpoint, baseURL: instance.url)
    }

    func removeYouTubePick(videoID: String, instance: Instance) async throws {
        let endpoint = GenericEndpoint.delete("/api/v1/recommended/picks/\(videoID)")
        let _: OKResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)
    }
}

extension ContentService {
    func youTubePicks(instance: Instance) async throws -> [Video] {
        try await yatteeServerAPI(for: instance).youTubePicks(instance: instance)
    }

    func addYouTubePick(_ body: YouTubePickBody, instance: Instance) async throws -> YouTubePickResponse {
        try await yatteeServerAPI(for: instance).addYouTubePick(body, instance: instance)
    }

    func removeYouTubePick(videoID: String, instance: Instance) async throws {
        try await yatteeServerAPI(for: instance).removeYouTubePick(videoID: videoID, instance: instance)
    }
}

extension ContentService {
    func sendRecommendationFeedback(
        videoID: String, action: RecommendationFeedback, reason: String?, instance: Instance
    ) async throws -> Int {
        try await yatteeServerAPI(for: instance)
            .sendRecommendationFeedback(videoID: videoID, action: action, reason: reason, instance: instance)
    }

    func rebuildRecommendations(instance: Instance) async throws -> Int {
        try await yatteeServerAPI(for: instance).rebuildRecommendations(instance: instance)
    }

    func sendWatchReport(_ report: WatchReport, instance: Instance) async throws {
        try await yatteeServerAPI(for: instance).sendWatchReport(report, instance: instance)
    }

    func recommendationNote(instance: Instance) async throws -> String {
        try await yatteeServerAPI(for: instance).recommendationNote(instance: instance)
    }
}

// MARK: - Wishes ("跟推荐说一句")

/// Something the viewer told the feed in their own words.
struct FeedWish: Decodable, Sendable, Identifiable, Equatable {
    let id: String
    let text: String
    let ts: Double
    /// Epoch seconds; nil keeps the wish until removed.
    let until: Double?
    /// When a curated round first used it; nil while it waits for the next update.
    let used: Double?
    /// What the last round did about it, e.g. 「前面放了4部纪录片」.
    let result: String
}

struct FeedWishesStatus: Decodable, Sendable, Equatable {
    let wishes: [FeedWish]
    /// Epoch seconds of the next scheduled update.
    let nextUpdate: Double
    /// Watches that would bring the next update forward.
    let watchesToUpdate: Int
    let rebuilding: Bool
}

private struct FeedWishesBody: Encodable, Sendable {
    let texts: [String]
    let until: Double?
}

extension YatteeServerAPI {
    func feedWishes(instance: Instance) async throws -> FeedWishesStatus {
        try await httpClient.fetch(GenericEndpoint.get("/api/v1/recommended/wishes"), baseURL: instance.url)
    }

    func addFeedWishes(_ texts: [String], until: Date?, instance: Instance) async throws -> FeedWishesStatus {
        let body = FeedWishesBody(texts: texts, until: until?.timeIntervalSince1970)
        return try await httpClient.fetch(GenericEndpoint.post("/api/v1/recommended/wishes", body: body), baseURL: instance.url)
    }

    func removeFeedWish(id: String, instance: Instance) async throws -> FeedWishesStatus {
        try await httpClient.fetch(GenericEndpoint.delete("/api/v1/recommended/wishes/\(id)"), baseURL: instance.url)
    }
}

extension ContentService {
    func feedWishes(instance: Instance) async throws -> FeedWishesStatus {
        try await yatteeServerAPI(for: instance).feedWishes(instance: instance)
    }

    func addFeedWishes(_ texts: [String], until: Date?, instance: Instance) async throws -> FeedWishesStatus {
        try await yatteeServerAPI(for: instance).addFeedWishes(texts, until: until, instance: instance)
    }

    func removeFeedWish(id: String, instance: Instance) async throws -> FeedWishesStatus {
        try await yatteeServerAPI(for: instance).removeFeedWish(id: id, instance: instance)
    }
}
