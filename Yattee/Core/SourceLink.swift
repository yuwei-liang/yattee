//
//  SourceLink.swift
//  Yattee
//
//  Yattee Y: one-tap source setup.
//
//  yattee://add-source?url=<server>&name=<label>&proxy=1&user=<u>&pass=<p>
//
//  Adds (or updates) a Yattee Server source, stores the Basic Auth login in the
//  Keychain, and makes it the enabled Yattee Server. Handled before any other
//  link parsing or logging so the password never reaches a log. Meant to be
//  delivered straight to the device (e.g. `xcrun devicectl ... --payload-url`),
//  not pasted into chats or notes.
//

import Foundation

enum SourceLink {
    static let host = "add-source"

    struct Request: Equatable, Sendable {
        let url: URL
        let name: String?
        let proxiesVideos: Bool
        let username: String?
        let password: String?
    }

    /// Parses an add-source link; nil for any other URL.
    static func parse(_ url: URL) -> Request? {
        guard url.scheme?.lowercased() == "yattee", url.host?.lowercased() == host,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        func value(_ key: String) -> String? {
            items.first { $0.name == key }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let raw = value("url"), let server = Instance.normalizeSourceURL(raw) else { return nil }
        let proxy = value("proxy").map { ["1", "true", "yes"].contains($0.lowercased()) } ?? true
        return Request(url: server, name: value("name"), proxiesVideos: proxy,
                       username: value("user"), password: value("pass"))
    }

    /// Applies the request. Returns the source's display name.
    @MainActor
    @discardableResult
    static func apply(_ request: Request, in environment: AppEnvironment) -> String {
        let manager = environment.instancesManager
        let hasLogin = request.username != nil && request.password != nil
        let target: Instance

        if var existing = manager.instances.first(where: { $0.url == request.url }) {
            existing.proxiesVideos = request.proxiesVideos
            existing.isEnabled = true
            if let name = request.name { existing.name = name }
            if hasLogin { existing.usesBasicAuth = true }
            manager.update(existing)
            target = existing
        } else {
            target = Instance(
                type: .yatteeServer,
                url: request.url,
                name: request.name,
                proxiesVideos: request.proxiesVideos,
                usesBasicAuth: hasLogin
            )
            manager.add(target)
        }

        if let username = request.username, let password = request.password {
            environment.basicAuthCredentialsManager.setCredentials(
                username: username, password: password, for: target)
        }
        manager.disableOtherYatteeServerInstances(except: target.id)
        return target.name ?? request.url.host ?? request.url.absoluteString
    }
}
