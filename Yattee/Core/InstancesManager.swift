//
//  InstancesManager.swift
//  Yattee
//
//  Manages configured backend instances with iCloud sync.
//

import Foundation
import SwiftUI

/// Manages the list of configured backend instances with iCloud sync.
@MainActor
@Observable
final class InstancesManager {
    // MARK: - Storage

    private let localDefaults: UserDefaults
    private let ubiquitousStore = NSUbiquitousKeyValueStore.default
    private let instancesKey = "configuredInstances"
    private let activeInstanceKey = "activeInstanceID"

    // MARK: - Dependencies

    private weak var settingsManager: SettingsManager?

    // MARK: - State

    private(set) var instances: [Instance] = []
    private(set) var activeInstanceID: UUID?

    // MARK: - Initialization

    /// - Parameter defaults: where the configured instances are read and
    ///   written. The app's own defaults, except under test: a manager built on
    ///   the shared ones edits the list the app on that device is using, which
    ///   is how test fixtures ended up in it.
    init(settingsManager: SettingsManager? = nil, defaults: UserDefaults = .standard) {
        self.settingsManager = settingsManager
        self.localDefaults = defaults

        loadInstances()
        loadActiveInstance()
        startServerProbing()

        // Listen for external changes from iCloud
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: ubiquitousStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleiCloudChange()
            }
        }
    }

    /// Sets the settings manager reference for checking iCloud sync status.
    func setSettingsManager(_ manager: SettingsManager) {
        self.settingsManager = manager
    }

    /// Whether iCloud sync is currently enabled.
    private var iCloudSyncEnabled: Bool {
        settingsManager?.iCloudSyncEnabled ?? false
    }

    /// Whether instance sync is enabled (requires both master toggle and category toggle).
    private var instanceSyncEnabled: Bool {
        iCloudSyncEnabled && (settingsManager?.syncInstances ?? true)
    }

    /// Handles external iCloud changes by replacing local data with iCloud data.
    private func handleiCloudChange() {
        // Only process iCloud changes if instance sync is enabled
        guard instanceSyncEnabled else { return }

        guard let iCloudData = ubiquitousStore.data(forKey: instancesKey),
              let iCloudInstances = try? JSONDecoder().decode([Instance].self, from: iCloudData) else {
            return
        }

        // Replace local instances with iCloud data
        instances = iCloudInstances
        // Save to local defaults for offline access
        localDefaults.set(iCloudData, forKey: instancesKey)

        // Update sync time
        settingsManager?.updateLastSyncTime()

        // Instances arriving from iCloud are as much a change as a local edit.
        // Without this, a legacy authenticated instance delivered here never
        // reaches account migration — the account, and the adoption of its
        // saved login, would happen only after an unrelated edit or a relaunch.
        NotificationCenter.default.post(name: .instancesDidChange, object: nil)
    }

    /// Syncs local data to iCloud (called when enabling iCloud sync).
    /// Only syncs if instance sync is enabled.
    func syncToiCloud() {
        guard instanceSyncEnabled else { return }

        guard let data = try? JSONEncoder().encode(instances) else { return }
        ubiquitousStore.set(data, forKey: instancesKey)
        ubiquitousStore.synchronize()
        settingsManager?.updateLastSyncTime()
    }

    /// Replaces local data with iCloud data (called when enabling iCloud sync).
    /// Only replaces if instance sync is enabled.
    func replaceWithiCloudData() {
        guard instanceSyncEnabled else { return }

        ubiquitousStore.synchronize()

        guard let iCloudData = ubiquitousStore.data(forKey: instancesKey),
              let iCloudInstances = try? JSONDecoder().decode([Instance].self, from: iCloudData) else {
            // No iCloud data exists, sync local data to iCloud
            syncToiCloud()
            return
        }

        // Replace local with iCloud data
        instances = iCloudInstances
        localDefaults.set(iCloudData, forKey: instancesKey)
        settingsManager?.updateLastSyncTime()

        NotificationCenter.default.post(name: .instancesDidChange, object: nil)
    }

    // MARK: - Public Methods

    func add(_ instance: Instance) {
        instances.append(instance)
        saveInstances()
    }

    func remove(_ instance: Instance) {
        instances.removeAll { $0.id == instance.id }

        // Clear active instance if it was the removed one
        if activeInstanceID == instance.id {
            activeInstanceID = nil
            localDefaults.removeObject(forKey: activeInstanceKey)
        }

        saveInstances()
        Task { await ProxyDetectionCache.shared.invalidate(instance: instance) }
    }

    func update(_ instance: Instance) {
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index] = instance
            saveInstances()
            // Editing a source can change the proxy answer (URL change, toggle
            // flip). Drop the cached auto-detect verdict so the next playback
            // re-probes.
            Task { await ProxyDetectionCache.shared.invalidate(instance: instance) }
        }
    }

    /// Toggles the enabled state of an instance.
    func toggleEnabled(_ instance: Instance) {
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            var updated = instances[index]
            updated.isEnabled.toggle()
            instances[index] = updated
            saveInstances()
        }
    }

    /// Records whether an instance sits behind HTTP Basic Auth.
    /// Persisted (and synced to iCloud) so missing Keychain credentials can be
    /// detected after a reinstall.
    func setUsesBasicAuth(_ value: Bool, for instance: Instance) {
        guard let index = instances.firstIndex(where: { $0.id == instance.id }),
              instances[index].usesBasicAuth != value else { return }
        instances[index].usesBasicAuth = value
        saveInstances()
    }

    /// Records that a pre-revamp single login existed on an instance.
    ///
    /// Migration-only: every caller is migration machinery (a Yattee 1 import,
    /// the credential backfill, or the last account on the instance going
    /// away). Signing in deliberately never calls this — accounts describe
    /// logins now (see `AccountSignInHandler`, and `Instance.usesAccountLogin`
    /// for who writes it and why).
    func setUsesAccountLogin(_ value: Bool, for instance: Instance) {
        guard let index = instances.firstIndex(where: { $0.id == instance.id }),
              instances[index].usesAccountLogin != value else { return }
        instances[index].usesAccountLogin = value
        saveInstances()
    }

    // MARK: - Computed Properties

    var enabledInstances: [Instance] {
        instances.filter(\.isEnabled)
    }

    var peertubeInstances: [Instance] {
        instances.filter(\.isPeerTubeInstance)
    }

    var yatteeServerInstances: [Instance] {
        instances.filter(\.isYatteeServerInstance)
    }

    var hasYouTubeInstances: Bool {
        instances.contains { $0.isYouTubeInstance }
    }

    var hasPeerTubeInstances: Bool {
        instances.contains { $0.isPeerTubeInstance }
    }

    var hasYatteeServerInstances: Bool {
        instances.contains { $0.isYatteeServerInstance }
    }

    /// Instances whose backend has accounts at all, asked of the capability
    /// table rather than a type list.
    var accountCapableInstances: [Instance] {
        instances.filter { $0.type.accountCapabilities.supportsAccounts }
    }

    var hasAccountCapableInstances: Bool {
        instances.contains { $0.type.accountCapabilities.supportsAccounts }
    }

    /// Enabled Yattee Servers, the one in use first. Yattee Y: with several enabled
    /// (a laptop on the trip plus the home NAS), the fastest one that answers leads.
    var enabledYatteeServerInstances: [Instance] {
        var enabled = yatteeServerInstances.filter(\.isEnabled)
        if enabled.count > 1, let id = preferredYatteeServerID,
           let index = enabled.firstIndex(where: { $0.id == id }) {
            enabled.insert(enabled.remove(at: index), at: 0)
        }
        return enabled
    }

    // MARK: - Yattee Y: pick the fastest Yattee Server

    /// The enabled Yattee Server that answered fastest at the last check; nil until checked
    /// or when only one is enabled.
    private(set) var preferredYatteeServerID: UUID?
    private var lastServerProbe: Date?
    private var serverProbeLoop: Task<Void, Never>?

    /// Checks every enabled Yattee Server's /health and switches to the fastest one that
    /// answers. Keeps the current one unless it stopped answering or another is clearly
    /// faster, so the choice doesn't flap.
    func probeYatteeServers(force: Bool = false) async {
        let servers = yatteeServerInstances.filter(\.isEnabled)
        guard servers.count > 1 else {
            preferredYatteeServerID = nil
            return
        }
        if !force, let last = lastServerProbe, Date().timeIntervalSince(last) < 30 { return }
        lastServerProbe = Date()

        let times = await withTaskGroup(of: (UUID, TimeInterval?).self) { group in
            for server in servers {
                let url = server.url
                group.addTask { (server.id, await Self.healthTime(of: url)) }
            }
            var answered: [UUID: TimeInterval] = [:]
            for await (id, time) in group {
                if let time { answered[id] = time }
            }
            return answered
        }
        guard let best = times.min(by: { $0.value < $1.value }) else { return }
        if let current = preferredYatteeServerID, let currentTime = times[current],
           currentTime <= best.value * 1.5 + 0.05 {
            return
        }
        if preferredYatteeServerID != best.key {
            let name = servers.first { $0.id == best.key }?.displayName ?? "?"
            LoggingService.shared.info("Yattee Server switched to \(name) (\(Int(best.value * 1000)) ms)", category: .general)
            preferredYatteeServerID = best.key
        }
    }

    /// Re-checks every minute while the app runs (and on returning to the foreground).
    func startServerProbing() {
        guard serverProbeLoop == nil else { return }
        serverProbeLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.probeYatteeServers(force: true)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private nonisolated static func healthTime(of base: URL) async -> TimeInterval? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let start = Date()
        guard let (_, response) = try? await session.data(from: base.appendingPathComponent("health")),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return Date().timeIntervalSince(start)
    }

    /// Selects an enabled instance appropriate for the given video's content source.
    /// - For PeerTube videos: prefers the exact instance, falls back to any PeerTube instance
    /// - For YouTube/extracted content: uses YouTube-capable instance (Invidious, Piped, Yattee Server)
    func instance(for video: Video) -> Instance? {
        instance(for: video.id.source)
    }

    /// Selects the instance to load a remote playlist from: Invidious first for
    /// YouTube (Invidious playlists are Invidious-specific), the playlist's own
    /// server for federated content, Yattee Server for extracted content.
    func playlistInstance(for source: ContentSource) -> Instance? {
        switch source {
        case .global:
            // For global content (YouTube), prefer Invidious instances over Yattee Server
            // since Invidious playlists (IVPL*) are Invidious-specific
            if let invidiousInstance = enabledInstances.first(where: { $0.type == .invidious }) {
                return invidiousInstance
            }
            // Fall back to any YouTube-compatible instance
            return enabledInstances.first(where: { $0.isYouTubeInstance })
        case .federated(let provider, let instanceURL):
            // For federated content, find matching instance by URL
            if let existingInstance = instances.first(where: { $0.url == instanceURL }) {
                return existingInstance
            }
            // If no configured instance matches, create a temporary one for PeerTube
            if provider == ContentSource.peertubeProvider {
                return Instance(type: .peertube, url: instanceURL)
            }
            return nil
        case .extracted:
            // For extracted content, use Yattee Server
            return yatteeServerInstances.first
        }
    }

    /// Selects an enabled instance appropriate for the given content source.
    /// - For PeerTube content: prefers the exact instance, falls back to any PeerTube instance
    /// - For extracted content: requires Yattee Server (only backend with yt-dlp)
    /// - For YouTube content: uses YouTube-capable instance (Invidious, Piped, Yattee Server)
    func instance(for contentSource: ContentSource) -> Instance? {
        switch contentSource {
        case .federated(let provider, let instanceURL) where provider == ContentSource.peertubeProvider:
            // PeerTube content - prefer the exact instance, fall back to any PeerTube instance
            return enabledInstances.first { $0.url.host == instanceURL.host }
                ?? enabledInstances.first(where: \.isPeerTubeInstance)
        case .extracted:
            // Extracted content requires Yattee Server (yt-dlp)
            return enabledYatteeServerInstances.first ?? yatteeServerInstances.first
        case .global, .federated:
            // YouTube content - prefer Yattee Server (the active one if it is one),
            // then the active instance, then any other YouTube-capable instance
            let active = activeInstance
            if let active, active.isYatteeServerInstance {
                return enabledYatteeServerInstances.first ?? active
            }
            if let yatteeServer = enabledYatteeServerInstances.first {
                return yatteeServer
            }
            if let active, active.isYouTubeInstance {
                return active
            }
            return enabledInstances.first(where: \.isYouTubeInstance)
        }
    }

    /// Disables all Yattee Server instances except the specified one.
    func disableOtherYatteeServerInstances(except instanceID: UUID) {
        for instance in enabledYatteeServerInstances where instance.id != instanceID {
            var updated = instance
            updated.isEnabled = false
            update(updated)
        }
    }

    /// The currently active instance for browsing content.
    /// Falls back to the first enabled instance if no active instance is set.
    var activeInstance: Instance? {
        if let id = activeInstanceID,
           let instance = enabledInstances.first(where: { $0.id == id }) {
            return instance
        }
        return enabledInstances.first
    }

    // MARK: - Private Methods

    private func loadInstances() {
        // Only load from local defaults - never automatically pull from iCloud
        // User must explicitly enable iCloud sync to get iCloud data
        if let data = localDefaults.data(forKey: instancesKey),
           let decoded = try? JSONDecoder().decode([Instance].self, from: data) {
            instances = decoded
        }
    }

    private func saveInstances() {
        guard let data = try? JSONEncoder().encode(instances) else { return }

        // Always write to local storage
        localDefaults.set(data, forKey: instancesKey)

        // Only write to iCloud if instance sync is enabled
        if instanceSyncEnabled {
            ubiquitousStore.set(data, forKey: instancesKey)
            settingsManager?.updateLastSyncTime()
        }

        NotificationCenter.default.post(name: .instancesDidChange, object: nil)
    }

    private func loadActiveInstance() {
        if let idString = localDefaults.string(forKey: activeInstanceKey),
           let uuid = UUID(uuidString: idString) {
            activeInstanceID = uuid
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let instancesDidChange = Notification.Name("stream.yattee.instancesDidChange")
}
