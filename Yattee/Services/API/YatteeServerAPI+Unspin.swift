//
//  YatteeServerAPI+Unspin.swift
//  Yattee
//
//  Yattee Y: send a video to "unspin" (argument analysis) through our Yattee
//  Server's queue, and list the queue and finished reports. A worker on the
//  owner's Mac runs the analysis and posts the report link back.
//

import Foundation
import SwiftUI

/// One analysis job as the server reports it.
struct UnspinJob: Decodable, Identifiable, Hashable, Sendable {
    struct Result: Decodable, Hashable, Sendable {
        let url: String
        let title: String?
        let score: Int?
        let verdict: String?
        let summary: String?
    }

    let id: String
    let title: String?
    let author: String?
    let state: String          // queued | running | done | failed
    let stage: String?
    let position: Int?
    let requestedAt: Double?
    let finishedAt: Double?
    let result: Result?
    let error: String?

    var isActive: Bool { state == "queued" || state == "running" }
    var displayTitle: String { result?.title ?? title ?? id }
}

private struct UnspinEnqueueBody: Encodable, Sendable {
    let videoId: String
    let title: String?
    let author: String?
}

private struct UnspinListResponse: Decodable, Sendable {
    let jobs: [UnspinJob]
}

extension YatteeServerAPI {
    func enqueueUnspin(videoID: String, title: String?, author: String?, instance: Instance) async throws -> UnspinJob {
        let endpoint = GenericEndpoint.post("/api/v1/unspin", body: UnspinEnqueueBody(videoId: videoID, title: title, author: author))
        return try await httpClient.fetch(endpoint, baseURL: instance.url)
    }

    func unspinJobs(instance: Instance) async throws -> [UnspinJob] {
        let response: UnspinListResponse = try await httpClient.fetch(GenericEndpoint.get("/api/v1/unspin"), baseURL: instance.url)
        return response.jobs
    }
}

extension ContentService {
    func enqueueUnspin(videoID: String, title: String?, author: String?, instance: Instance) async throws -> UnspinJob {
        try await yatteeServerAPI(for: instance).enqueueUnspin(videoID: videoID, title: title, author: author, instance: instance)
    }

    func unspinJobs(instance: Instance) async throws -> [UnspinJob] {
        try await yatteeServerAPI(for: instance).unspinJobs(instance: instance)
    }
}

/// Shared "用 unspin 分析" action for menus.
enum UnspinSubmitter {
    /// Whether the action applies: a YouTube video and an enabled Yattee Server.
    @MainActor
    static func canSubmit(_ video: Video, in environment: AppEnvironment?) -> Bool {
        guard let environment, !environment.instancesManager.enabledYatteeServerInstances.isEmpty else { return false }
        if case .global(let provider) = video.id.source { return provider == ContentSource.youtubeProvider }
        return false
    }

    @MainActor
    static func submit(_ video: Video, in environment: AppEnvironment?) {
        guard let environment, let server = environment.instancesManager.enabledYatteeServerInstances.first else { return }
        let videoID = video.id.videoID
        let title = video.title
        let author = video.author.name
        Task {
            do {
                let job = try await environment.contentService.enqueueUnspin(
                    videoID: videoID, title: title, author: author, instance: server)
                let message: String
                switch job.state {
                case "done": message = "这个视频已经分析过了，在 unspin 报告里"
                case "running": message = "正在分析，好了会发 Telegram"
                default: message = "已交给 unspin，好了会发 Telegram"
                }
                _ = environment.toastManager.showSuccess(message)
            } catch {
                _ = environment.toastManager.showError("没交给 unspin", subtitle: error.localizedDescription)
            }
        }
    }
}
