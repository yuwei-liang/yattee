//
//  SleepTimer.swift
//  Yattee
//
//  Yattee Y: bedtime sleep timer. Pauses playback after N minutes or at the end
//  of the current video. Counts wall-clock time (a late timer tick after the
//  app was backgrounded cannot stretch it), fades the volume over the last
//  30 seconds, and offers "再放 15 分钟" when it fires. Logic adapted from
//  7inh/yattee 5fd6c3d.
//

import Foundation
import Observation
import SwiftUI

#if os(iOS) || os(macOS)
@MainActor
@Observable
final class SleepTimer {
    enum Mode: Equatable {
        case off
        case until(Date)
        case endOfVideo
    }

    static let shared = SleepTimer()
    static let minuteOptions = [15, 30, 45, 60]
    static let fadeSeconds: Double = 30
    private static let fadeKey = "yatteeY.sleepTimer.fade"

    private(set) var mode: Mode = .off
    private(set) var remainingSeconds = 0

    /// Fade the volume out over the last 30 seconds (default on).
    var fadeEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.fadeKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.fadeKey) }
    }

    @ObservationIgnored private weak var environment: AppEnvironment?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var volumeBeforeFade: Float?

    private init() {}

    var isActive: Bool { mode != .off }

    /// Short label for badges: "17:02" or "播完这条".
    var caption: String? {
        switch mode {
        case .off: nil
        case .until: String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60)
        case .endOfVideo: "播完这条"
        }
    }

    var selectedMinutes: Int? {
        guard case .until(let end) = mode else { return nil }
        return Self.minuteOptions.min { abs(Double($0 * 60) - end.timeIntervalSinceNow) < abs(Double($1 * 60) - end.timeIntervalSinceNow) }
    }

    // MARK: - Control

    func start(minutes: Int, environment: AppEnvironment?) {
        cancel()
        self.environment = environment
        mode = .until(Date().addingTimeInterval(Double(minutes) * 60))
        tick()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func startEndOfVideo(environment: AppEnvironment?) {
        cancel()
        self.environment = environment
        mode = .endOfVideo
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        restoreVolume()
        mode = .off
        remainingSeconds = 0
    }

    /// Called by PlayerService when a video finishes. Returns true when the timer
    /// was waiting for this ending, so the player stops instead of playing on.
    func consumeEndOfVideo() -> Bool {
        guard mode == .endOfVideo else { return false }
        mode = .off
        announceStop()
        return true
    }

    // MARK: - Ticking

    private func tick() {
        guard case .until(let end) = mode else { return }
        let left = end.timeIntervalSinceNow
        remainingSeconds = max(0, Int(left.rounded(.up)))
        if left <= 0 {
            fire()
        } else if fadeEnabled, left <= Self.fadeSeconds, let backend = environment?.playerService.currentBackend {
            if volumeBeforeFade == nil { volumeBeforeFade = backend.volume }
            backend.volume = (volumeBeforeFade ?? 1) * Float(left / Self.fadeSeconds)
        }
    }

    private func fire() {
        timer?.invalidate()
        timer = nil
        environment?.playerService.pause()
        restoreVolume()
        mode = .off
        remainingSeconds = 0
        announceStop()
    }

    private func restoreVolume() {
        if let volume = volumeBeforeFade, let backend = environment?.playerService.currentBackend {
            backend.volume = volume
        }
        volumeBeforeFade = nil
    }

    private func announceStop() {
        guard let environment else { return }
        _ = environment.toastManager.show(
            category: .info,
            title: "🌙 晚安，已暂停",
            subtitle: "停在这里，下次接着看",
            action: ToastAction(label: "再放 15 分钟", systemImage: "moon.zzz") { [weak self] in
                self?.start(minutes: 15, environment: environment)
                environment.playerService.resume()
            },
            autoDismissDelay: 20
        )
    }
}

// MARK: - Views

/// Small moon badge with the time left; tap to cancel.
struct SleepTimerBadge: View {
    private let timer = SleepTimer.shared

    var body: some View {
        if let caption = timer.caption {
            Menu {
                Button("关闭睡眠定时", systemImage: "moon.zzz") { timer.cancel() }
            } label: {
                Label(caption, systemImage: "moon.fill")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.79, green: 0.72, blue: 1.0))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("睡眠定时，剩余 \(caption)")
        }
    }
}

/// "睡眠定时" submenu for the player's menu.
struct SleepTimerMenu: View {
    @Environment(\.appEnvironment) private var appEnvironment
    private let timer = SleepTimer.shared

    var body: some View {
        Menu {
            ForEach(SleepTimer.minuteOptions, id: \.self) { minutes in
                Button {
                    timer.start(minutes: minutes, environment: appEnvironment)
                } label: {
                    if timer.selectedMinutes == minutes {
                        Label("\(minutes) 分钟", systemImage: "checkmark")
                    } else {
                        Text("\(minutes) 分钟")
                    }
                }
            }
            Button {
                timer.startEndOfVideo(environment: appEnvironment)
            } label: {
                if timer.mode == .endOfVideo {
                    Label("播完这条", systemImage: "checkmark")
                } else {
                    Text("播完这条")
                }
            }
            Divider()
            Toggle("到点前音量渐弱", isOn: Binding(get: { timer.fadeEnabled }, set: { timer.fadeEnabled = $0 }))
            if let settings = appEnvironment?.settingsManager {
                Toggle("自动接着播下一条", isOn: Binding(get: { settings.queueAutoPlayNext }, set: { settings.queueAutoPlayNext = $0 }))
            }
            if timer.isActive {
                Divider()
                Button("关闭定时", systemImage: "xmark", role: .destructive) { timer.cancel() }
            }
        } label: {
            Label(timer.caption.map { "睡眠定时 · \($0)" } ?? "睡眠定时", systemImage: timer.isActive ? "moon.fill" : "moon")
        }
    }
}
#endif
