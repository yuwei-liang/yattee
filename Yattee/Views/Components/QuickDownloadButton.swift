//
//  QuickDownloadButton.swift
//  Yattee
//
//  Yattee Y: a one-tap download button for the recommendation cards, so the
//  viewer can fill the queue on Wi-Fi before a trip. Tap: download the video
//  (default quality). Long-press: video or sound only. The icon shows the
//  state: ⬇︎ → queued → progress ring → ✓.
//

#if !os(tvOS)
import SwiftUI

struct QuickDownloadButton: View {
    let video: Video

    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.presentAppSheet) private var presentAppSheet

    private var download: Download? {
        appEnvironment?.downloadManager.download(for: video.id)
    }

    private var isDownloaded: Bool {
        appEnvironment?.downloadManager.isDownloaded(video.id) ?? false
    }

    private var isPreparing: Bool {
        appEnvironment?.downloadManager.preparingVideoIDs.contains(video.id) ?? false
    }

    private var canStart: Bool {
        download == nil && !isDownloaded && !isPreparing
    }

    var body: some View {
        Menu {
            if canStart {
                Button {
                    startVideo()
                } label: {
                    Label("下载视频", systemImage: "arrow.down.circle")
                }
                Button {
                    startAudio()
                } label: {
                    Label("只要声音（省空间）", systemImage: "music.note")
                }
            } else if isPreparing {
                Label("正在准备下载…", systemImage: "hourglass")
            } else if isDownloaded {
                Label("已下载", systemImage: "checkmark.circle.fill")
            } else if let download {
                Button(role: .destructive) {
                    Task { await appEnvironment?.downloadManager.cancel(download) }
                } label: {
                    Label("取消下载", systemImage: "xmark.circle")
                }
            }
        } label: {
            icon
                .frame(width: 40, height: 32)
                .contentShape(Rectangle())
        } primaryAction: {
            if canStart {
                startVideo()
            }
        }
        .menuIndicator(.hidden)
        #if os(macOS)
        .menuStyle(.borderlessButton)
        .fixedSize()
        #endif
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var icon: some View {
        if isDownloaded {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
        } else if isPreparing {
            // Optimistic: reacts on the tap while the streams are being fetched.
            ZStack {
                Circle()
                    .stroke(.tint.opacity(0.35), lineWidth: 2.5)
                ProgressView()
                    .controlSize(.mini)
            }
            .frame(width: 20, height: 20)
        } else if let download, download.status == .downloading {
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.25), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0.03, min(1, download.progress)))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 20, height: 20)
        } else if let download, download.status == .failed {
            Image(systemName: "exclamationmark.circle")
                .font(.title3)
                .foregroundStyle(.orange)
        } else if download != nil {
            Image(systemName: "clock")
                .font(.title3)
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: "arrow.down.circle")
                .font(.title3)
                .foregroundStyle(.tint)
        }
    }

    private var accessibilityText: String {
        if isDownloaded { return "已下载" }
        if isPreparing { return "正在准备下载" }
        if let download {
            return download.status == .downloading ? "正在下载 \(Int(download.progress * 100))%" : "在下载队列里"
        }
        return "下载"
    }

    private func startVideo() {
        guard let appEnvironment else { return }
        let settings = appEnvironment.downloadSettings
        guard settings.preferredDownloadQuality != .ask,
              let instance = appEnvironment.instancesManager.instance(for: video) else {
            presentAppSheet(.downloadOptions(video))
            return
        }
        markPreparing(appEnvironment)
        Task {
            defer { appEnvironment.downloadManager.preparingVideoIDs.remove(video.id) }
            do {
                try await appEnvironment.downloadManager.autoEnqueue(
                    video,
                    preferredQuality: settings.preferredDownloadQuality,
                    preferredAudioLanguage: appEnvironment.settingsManager.preferredAudioLanguage,
                    preferredSubtitlesLanguage: appEnvironment.settingsManager.preferredSubtitlesLanguage,
                    includeSubtitles: settings.includeSubtitlesInAutoDownload,
                    contentService: appEnvironment.contentService,
                    instance: instance
                )
            } catch {
                showError(error)
            }
        }
    }

    private func startAudio() {
        guard let appEnvironment,
              let instance = appEnvironment.instancesManager.instance(for: video) else { return }
        markPreparing(appEnvironment)
        Task {
            defer { appEnvironment.downloadManager.preparingVideoIDs.remove(video.id) }
            do {
                try await appEnvironment.downloadManager.autoEnqueueAudioOnly(
                    video,
                    preferredAudioLanguage: appEnvironment.settingsManager.preferredAudioLanguage,
                    contentService: appEnvironment.contentService,
                    instance: instance
                )
            } catch {
                showError(error)
            }
        }
    }

    private func markPreparing(_ appEnvironment: AppEnvironment) {
        appEnvironment.downloadManager.preparingVideoIDs.insert(video.id)
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func showError(_ error: Error) {
        appEnvironment?.toastManager.show(
            category: .error,
            title: String(localized: "download.error.title"),
            subtitle: error.localizedDescription,
            icon: "exclamationmark.triangle",
            iconColor: .red
        )
    }
}
#endif
