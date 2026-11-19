//
//  UnspinReportsView.swift
//  Yattee
//
//  Yattee Y: the unspin queue and finished reports, opened from the home chips.
//  Active jobs show their stage or queue position; finished ones show the score
//  (red / yellow / green) and the one-line verdict, and open the report page.
//

import SwiftUI

#if !os(tvOS)
struct UnspinReportsView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var jobs: [UnspinJob] = []
    @State private var loadError: String?
    @State private var hasLoaded = false

    private var server: Instance? {
        appEnvironment?.instancesManager.enabledYatteeServerInstances.first
    }

    private var active: [UnspinJob] { jobs.filter(\.isActive) }
    private var finished: [UnspinJob] { jobs.filter { !$0.isActive } }

    var body: some View {
        NavigationStack {
            List {
                if !active.isEmpty {
                    Section("进行中") {
                        ForEach(active) { job in activeRow(job) }
                    }
                }
                Section("报告") {
                    if finished.isEmpty {
                        Text(hasLoaded ? "还没有报告。看到带节奏的视频，在「⋯」或长按菜单里选「用 unspin 分析」。" : "加载中…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(finished) { job in finishedRow(job) }
                }
                if let loadError {
                    Section { Text(loadError).font(.caption).foregroundStyle(.red) }
                }
            }
            .navigationTitle("unspin 报告")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .refreshable { await load() }
            .task {
                // Poll while anything is queued or running.
                while !Task.isCancelled {
                    await load()
                    try? await Task.sleep(for: .seconds(active.isEmpty ? 60 : 15))
                }
            }
        }
    }

    // MARK: - Rows

    private func activeRow(_ job: UnspinJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
            HStack(spacing: 6) {
                if job.state == "running" {
                    ProgressView().controlSize(.mini)
                    Text("分析中 · \(job.stage ?? "开始")").foregroundStyle(.orange)
                } else {
                    Text("排队中 · 第 \(job.position ?? 1) 个").foregroundStyle(.secondary)
                }
                if let author = job.author { Text("· \(author)").foregroundStyle(.secondary) }
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func finishedRow(_ job: UnspinJob) -> some View {
        if job.state == "done", let result = job.result, let url = URL(string: result.url) {
            Button { openURL(url) } label: {
                HStack(alignment: .top, spacing: 12) {
                    ScoreBadge(score: result.score)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(job.displayTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text([job.author, finishedDate(job)].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        if let verdict = result.verdict {
                            Text(verdict).font(.caption).foregroundStyle(.primary.opacity(0.85)).lineLimit(2)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(job.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text("没做完：\(job.error ?? "未知原因")").font(.caption).foregroundStyle(.red).lineLimit(3)
                Button("再试一次") { retry(job) }.font(.caption.weight(.semibold))
            }
        }
    }

    private func finishedDate(_ job: UnspinJob) -> String? {
        guard let ts = job.finishedAt else { return nil }
        return Date(timeIntervalSince1970: ts).formatted(.dateTime.month().day())
    }

    // MARK: - Data

    private func load() async {
        guard let server, let appEnvironment else {
            loadError = "没有启用的 Yattee Server 源。"
            return
        }
        do {
            jobs = try await appEnvironment.contentService.unspinJobs(instance: server)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        hasLoaded = true
    }

    private func retry(_ job: UnspinJob) {
        guard let server, let appEnvironment else { return }
        Task {
            _ = try? await appEnvironment.contentService.enqueueUnspin(
                videoID: job.id, title: job.title, author: job.author, instance: server)
            await load()
        }
    }
}

/// Score out of 100 in a colored tile: red under 50, yellow under 70, green above.
private struct ScoreBadge: View {
    let score: Int?

    private var color: Color {
        guard let score else { return .gray }
        return score < 50 ? .red : score < 70 ? .yellow : .green
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(score.map(String.init) ?? "–").font(.title3.bold()).monospacedDigit()
            Text("/100").font(.system(size: 9, weight: .semibold)).opacity(0.7)
        }
        .foregroundStyle(.black)
        .frame(width: 52, height: 52)
        .background(color.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
    }
}
#endif
