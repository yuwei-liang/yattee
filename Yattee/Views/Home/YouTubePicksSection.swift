//
//  YouTubePicksSection.swift
//  Yattee
//
//  Yattee Y: the home row "从 YouTube 带来的" and the clipboard banner that
//  offers to play a copied link. See YouTubePicks for where picks come from.
//

import SwiftUI

struct YouTubePicksSection: View {
    private var picks: YouTubePicks { .shared }

    #if os(tvOS)
    private let horizontalPadding: CGFloat = 48
    #else
    private let horizontalPadding: CGFloat = 16
    #endif

    var body: some View {
        Group {
            if !picks.videos.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("从 YouTube 带来的")
                            #if os(tvOS)
                            .font(.title3.bold())
                            #else
                            .font(.headline)
                            #endif
                        Spacer()
                        Text("\(picks.videos.count) 个 · 看完自动移走")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 8)

                    HomeHorizontalCards(
                        videos: picks.videos,
                        queueSource: .manual,
                        sourceLabel: "从 YouTube 带来的",
                        loadMoreVideos: nil,
                        customActions: { video in
                            [VideoContextAction("从这一排移走", systemImage: "minus.circle", role: .destructive) {
                                YouTubePicks.shared.remove(video)
                            }]
                        }
                    )
                }
                .padding(.bottom, 12)
            }
        }
        .task { await picks.reload() }
    }
}

#if os(iOS)
/// "剪贴板里有个链接" with the system paste button, which needs no permission prompt.
struct ClipboardLinkBanner: View {
    private var picks: YouTubePicks { .shared }

    var body: some View {
        if picks.clipboardOffer {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("剪贴板里有个链接")
                        .font(.subheadline.weight(.medium))
                    Text("粘贴就播放")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                PasteButton(payloadType: URL.self) { urls in
                    guard let url = urls.first else { return }
                    Task { @MainActor in
                        YouTubePicks.shared.dismissClipboardOffer()
                        NotificationCenter.default.post(name: .openDescriptionLink, object: url)
                    }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                Button {
                    picks.dismissClipboardOffer()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("不用了")
            }
            .padding(12)
            .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
#endif
