//
//  RecommendedFeedSection.swift
//  Yattee
//
//  Yattee Y: the home page's recommendation feed, YouTube style. Shows the
//  list Claude curates on our Yattee Server (`/api/v1/popular`), each with the
//  reason it was picked, and sends feedback (more / deeper / less / channel)
//  back so the next round learns from it.
//

import SwiftUI

struct RecommendedFeedSection: View {
    @Environment(\.appEnvironment) private var appEnvironment
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var videos: [Video] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var isRebuilding = false
    /// What the last curated round changed because of the viewer's ratings and feedback.
    @State private var note = ""
    /// Videos the viewer dismissed, waiting out the undo window or showing reasons.
    @State private var dismissed: [String: DismissState] = [:]
    @State private var pendingSends: [String: Task<Void, Never>] = [:]
    /// 「跟推荐说一句」: what the viewer asked for, and the panel.
    @State private var wishStatus: FeedWishesStatus?
    @State private var showingWishSheet = false
    @State private var rebuildingForWish = false
    /// The ⋯ menu's 「已下载」 item asks before deleting.
    @State private var showingDeleteDownloadConfirmation = false
    @State private var downloadToDelete: Download?

    private enum DismissState { case undoable, thanked }

    private static let reasons = ["看过了", "对这个话题没兴趣", "太长", "标题党"]
    private static let undoWindow: Duration = .seconds(6)

    private var server: Instance? {
        appEnvironment?.instancesManager.enabledYatteeServerInstances.first
    }

    private var visibleVideos: [Video] {
        videos.filter { dismissed[$0.id.videoID] == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if videos.isEmpty {
                placeholder
            } else {
                if usesGrid {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: gridSpacing) { cards }
                } else {
                    cards
                }
                footer
            }
        }
        #if os(tvOS)
        .padding(.horizontal, 48)
        .padding(.bottom, 60)
        #else
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        #endif
        .task { if videos.isEmpty { await load() } }
        .sheet(isPresented: $showingWishSheet) {
            FeedWishSheet(status: wishStatus, remove: removeWish, submit: submitWishes)
        }
        #if !os(tvOS)
        .alert(String(localized: "videoInfo.download.remove.title"), isPresented: $showingDeleteDownloadConfirmation) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "videoInfo.download.remove.confirm"), role: .destructive) {
                if let download = downloadToDelete {
                    Task { await appEnvironment?.downloadManager.delete(download) }
                }
            }
        } message: {
            Text(String(localized: "videoInfo.download.remove.message"))
        }
        #endif
    }

    // MARK: - Pieces

    /// Mac and wide iPad show the feed as a YouTube-style grid; iPhone keeps one column.
    private var usesGrid: Bool {
        #if os(macOS) || os(tvOS)
        true
        #elseif os(iOS)
        horizontalSizeClass == .regular
        #else
        false
        #endif
    }

    /// Apple TV: four fixed columns read from the couch; elsewhere cards fill the width.
    private var gridColumns: [GridItem] {
        #if os(tvOS)
        Array(repeating: GridItem(.flexible(), spacing: 48, alignment: .top), count: 4)
        #else
        [GridItem(.adaptive(minimum: 280), spacing: 20, alignment: .top)]
        #endif
    }

    private var gridSpacing: CGFloat {
        #if os(tvOS)
        56
        #else
        28
        #endif
    }

    @ViewBuilder
    private var cards: some View {
        ForEach(Array(videos.enumerated()), id: \.element.id.videoID) { index, video in
            if let state = dismissed[video.id.videoID] {
                dismissedCard(video: video, state: state)
            } else {
                feedCard(video: video, index: index)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("推荐")
                    .font(.title2.bold())
                Button {
                    showingWishSheet = true
                } label: {
                    Label("说一句", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.purple)
                .disabled(server == nil)
                Spacer()
                if !videos.isEmpty {
                    Text("Claude 为你挑的 \(visibleVideos.count) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if rebuildingForWish {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在按你说的重挑，大约一分钟…")
                        .font(.subheadline)
                        .foregroundStyle(.purple)
                }
                .padding(.vertical, 4)
            }
            if let wishes = wishStatus?.wishes, !wishes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(wishes.prefix(3)) { wish in
                        FeedWishRow(wish: wish) { removeWish(wish) }
                    }
                    if wishes.count > 3 {
                        Button("还有 \(wishes.count - 3) 句") { showingWishSheet = true }
                            .font(.caption)
                    }
                }
                #if !os(tvOS)
                .frame(maxWidth: usesGrid ? 560 : .infinity, alignment: .leading)
                #endif
            }
            if !note.isEmpty {
                Label(note, systemImage: "checkmark.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
        } else if let loadError {
            VStack(spacing: 10) {
                Text("推荐没加载出来").font(.headline)
                Text(loadError).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("重试") { Task { await load() } }
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            Text("服务器还没有推荐。看几个视频后会自动生成。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    private func feedCard(video: Video, index: Int) -> some View {
        let list = visibleVideos
        return VStack(alignment: .leading, spacing: 6) {
            VideoCardView(video: video, reservesTitleSpace: usesGrid)
                .tappableVideo(
                    video,
                    customActions: cardMenuActions(for: video),
                    sourceLabel: "推荐",
                    videoList: list,
                    videoIndex: list.firstIndex(where: { $0.id == video.id }) ?? index
                )

            HStack(spacing: 8) {
                if let why = video.description?.trimmingCharacters(in: .whitespacesAndNewlines), !why.isEmpty {
                    Label(why, systemImage: "sparkles")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tint)
                        .lineLimit(usesGrid ? 1 : 2)
                        #if !os(tvOS)
                        .help(why)
                        #endif
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }
                Spacer(minLength: 0)
                #if !os(tvOS)
                // Same items as the long-press menu: feedback first, then the app's usual video actions.
                Menu {
                    VideoContextMenuContent(
                        video: video,
                        customActions: feedbackActions(for: video),
                        showingDeleteDownloadConfirmation: $showingDeleteDownloadConfirmation,
                        downloadToDelete: $downloadToDelete,
                        appEnvironment: appEnvironment
                    )
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
                .menuIndicator(.hidden)
                #if os(macOS)
                .menuStyle(.borderlessButton)
                .fixedSize()
                #endif
                .accessibilityLabel("推荐选项")
                #endif
            }
        }
        // One column: extra room after each card's reason row, so the row clearly belongs to the card above.
        .padding(.bottom, usesGrid ? 0 : 14)
    }

    private func dismissedCard(video: Video, state: DismissState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(state == .thanked ? "收到，以后少推这类" : "已从推荐里拿掉")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if state == .undoable {
                    Button("撤销") { undoDismiss(video) }
                        .font(.subheadline.weight(.semibold))
                }
            }
            if state == .undoable {
                Text("顺便说一下原因（可以不选）：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FlowChips(items: Self.reasons) { reason in
                    sendDismiss(video, reason: reason)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 8) {
            if isRebuilding {
                ProgressView()
                Text("Claude 正在重新挑，大约一分钟…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await rebuild() }
                } label: {
                    Label("换一批", systemImage: "arrow.clockwise")
                        .frame(maxWidth: usesGrid ? 320 : .infinity)
                }
                .buttonStyle(.bordered)
                Text("让 Claude 马上重新挑一批")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func feedbackActions(for video: Video) -> [VideoContextAction] {
        [
            VideoContextAction("多来点这种", systemImage: "plus.circle") { send(.more, for: video, toast: "好的，多推这种") },
            VideoContextAction("顺着这个深挖", systemImage: "arrow.down.forward.circle") { send(.deeper, for: video, toast: "好的，下一轮帮你深挖") },
            VideoContextAction("不感兴趣", systemImage: "hand.thumbsdown") { beginDismiss(video) },
            VideoContextAction("别再推这个频道", systemImage: "person.crop.circle.badge.xmark", role: .destructive) { blockChannel(of: video) },
        ]
    }

    /// The card's long-press menu. On Apple TV it also carries unspin, since there is no ⋯ button.
    private func cardMenuActions(for video: Video) -> [VideoContextAction] {
        #if os(tvOS)
        menuActions(for: video)
        #else
        feedbackActions(for: video)
        #endif
    }

    /// The card's ⋯ menu: unspin first (as in the design), then the feedback actions.
    private func menuActions(for video: Video) -> [VideoContextAction] {
        [VideoContextAction("用 unspin 分析", systemImage: "scope") { UnspinSubmitter.submit(video, in: appEnvironment) }]
            + feedbackActions(for: video)
    }

    private func load() async {
        guard let server, let appEnvironment else {
            loadError = "没有启用的 Yattee Server 源。"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await appEnvironment.contentService.popular(for: server)
            videos = list
            note = (try? await appEnvironment.contentService.recommendationNote(instance: server)) ?? ""
            wishStatus = try? await appEnvironment.contentService.feedWishes(instance: server)
            dismissed = [:]
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func rebuild() async {
        guard let server, let appEnvironment else { return }
        isRebuilding = true
        defer { isRebuilding = false }
        do {
            try await runRebuild(on: server, appEnvironment: appEnvironment)
        } catch {
            _ = appEnvironment.toastManager.showError("换一批失败", subtitle: error.localizedDescription)
        }
    }

    /// Starts a rebuild on the server, waits for it by polling (up to five minutes), then reloads the feed.
    private func runRebuild(on server: Instance, appEnvironment: AppEnvironment) async throws {
        try await appEnvironment.contentService.startRecommendationRebuild(instance: server)
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline {
            try? await Task.sleep(for: .seconds(4))
            // A failed poll (flaky network) just means "ask again".
            if let status = try? await appEnvironment.contentService.feedWishes(instance: server), !status.rebuilding {
                break
            }
        }
        await load()
    }

    // MARK: - Wishes

    private func removeWish(_ wish: FeedWish) {
        guard let server, let appEnvironment else { return }
        Task {
            do {
                let status = try await appEnvironment.contentService.removeFeedWish(id: wish.id, instance: server)
                withAnimation { wishStatus = status }
            } catch {
                _ = appEnvironment.toastManager.showError("没撤回成功", subtitle: error.localizedDescription)
            }
        }
    }

    private func submitWishes(_ texts: [String], until: Date?, now: Bool) {
        guard let server, let appEnvironment else { return }
        Task {
            do {
                let status = try await appEnvironment.contentService.addFeedWishes(texts, until: until, instance: server)
                withAnimation { wishStatus = status }
                guard now else {
                    _ = appEnvironment.toastManager.showSuccess("记下了", subtitle: "下次更新时用：\(status.nextUpdateLabel)\(status.sooner)")
                    return
                }
                let newIDs = Set(status.wishes.filter { $0.used == nil }.map(\.id))
                rebuildingForWish = true
                defer { rebuildingForWish = false }
                try await runRebuild(on: server, appEnvironment: appEnvironment)
                let unused = wishStatus?.wishes.contains { newIDs.contains($0.id) && $0.used == nil } ?? false
                if unused {
                    _ = appEnvironment.toastManager.showError("这次没用上", subtitle: "可能今天的重挑次数用完了，会在下次更新时用")
                }
            } catch {
                rebuildingForWish = false
                _ = appEnvironment.toastManager.showError("没发出去", subtitle: error.localizedDescription)
            }
        }
    }

    private func send(_ action: RecommendationFeedback, for video: Video, reason: String? = nil, toast: String? = nil) {
        guard let server, let appEnvironment else { return }
        let videoID = video.id.videoID
        Task {
            do {
                _ = try await appEnvironment.contentService.sendRecommendationFeedback(
                    videoID: videoID, action: action, reason: reason, instance: server)
                if let toast { _ = appEnvironment.toastManager.showSuccess(toast) }
            } catch {
                _ = appEnvironment.toastManager.showError("反馈没发出去", subtitle: error.localizedDescription)
            }
        }
    }

    /// "不感兴趣": hide now, send after the undo window unless a reason is picked first.
    private func beginDismiss(_ video: Video) {
        let videoID = video.id.videoID
        withAnimation { dismissed[videoID] = .undoable }
        pendingSends[videoID]?.cancel()
        pendingSends[videoID] = Task {
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            await MainActor.run { sendDismiss(video, reason: nil) }
        }
    }

    private func sendDismiss(_ video: Video, reason: String?) {
        let videoID = video.id.videoID
        pendingSends[videoID]?.cancel()
        pendingSends[videoID] = nil
        send(.less, for: video, reason: reason)
        withAnimation { dismissed[videoID] = .thanked }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { withAnimation { videos.removeAll { $0.id.videoID == videoID } } }
        }
    }

    private func undoDismiss(_ video: Video) {
        let videoID = video.id.videoID
        pendingSends[videoID]?.cancel()
        pendingSends[videoID] = nil
        withAnimation { dismissed[videoID] = nil }
    }

    private func blockChannel(of video: Video) {
        let author = video.author.name
        send(.channel, for: video, toast: "以后不推「\(author)」")
        withAnimation { videos.removeAll { $0.author.name == author } }
    }
}

/// Small wrapping row of tappable chips.
private struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Button(item) { onTap(item) }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
            }
        }
    }
}
