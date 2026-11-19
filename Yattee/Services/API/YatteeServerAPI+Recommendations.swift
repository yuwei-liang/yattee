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
}
