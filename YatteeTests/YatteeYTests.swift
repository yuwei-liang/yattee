//
//  YatteeYTests.swift
//  YatteeTests
//
//  Tests for Yattee Y fork additions: the add-source link and CJK subtitle fonts.
//

import Foundation
import Testing
@testable import Yattee

// MARK: - Source Link

@Suite("Source Link")
struct SourceLinkTests {

    @Test("Parses a full add-source link")
    func parsesFullLink() throws {
        let url = try #require(URL(string:
            "yattee://add-source?url=http%3A%2F%2Fnas.example.ts.net%3A8085&name=NAS&proxy=1&user=me&pass=p%40ss%26w0rd"))
        let request = try #require(SourceLink.parse(url))
        #expect(request.url.absoluteString.hasPrefix("http://nas.example.ts.net:8085"))
        #expect(request.name == "NAS")
        #expect(request.proxiesVideos)
        #expect(request.username == "me")
        #expect(request.password == "p@ss&w0rd")
    }

    @Test("Proxy defaults on and can be turned off")
    func proxyFlag() throws {
        let on = try #require(SourceLink.parse(URL(string: "yattee://add-source?url=http://a.example:8085")!))
        #expect(on.proxiesVideos)
        let off = try #require(SourceLink.parse(URL(string: "yattee://add-source?url=http://a.example:8085&proxy=0")!))
        #expect(!off.proxiesVideos)
        #expect(off.username == nil && off.password == nil)
    }

    @Test("Ignores other links and links without a server")
    func ignoresOtherLinks() {
        #expect(SourceLink.parse(URL(string: "yattee://video/dQw4w9WgXcQ")!) == nil)
        #expect(SourceLink.parse(URL(string: "yattee://add-source")!) == nil)
        #expect(SourceLink.parse(URL(string: "https://add-source?url=http://a.example")!) == nil)
    }
}

// MARK: - Subtitle Fonts

@Suite("Subtitle Fonts")
struct SubtitleFontTests {

    @Test("Text font options use the bundled CJK font")
    func cjkFamilies() {
        #expect(SubtitleFont.sansSerif.mpvFontName == "Noto Sans SC")
        #expect(SubtitleFont.serif.mpvFontName == "Noto Sans SC")
    }

    @Test("Bundled font is copied into its own fonts directory")
    func fontsDirectory() throws {
        let dir = try #require(SubtitleFonts.directory)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir)
        #expect(files == ["NotoSansSC-Regular.otf"])
    }
}

// MARK: - Tap Behavior

@Suite("Tap Behavior")
@MainActor
struct TapBehaviorTests {

    @Test("Tapping a video's title plays it by default, like YouTube")
    func textAreaDefaultsToPlay() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "textAreaTapAction")
        defaults.removeObject(forKey: "textAreaTapAction")
        defer { if let saved { defaults.set(saved, forKey: "textAreaTapAction") } }
        #expect(SettingsManager().textAreaTapAction == .playVideo)
    }
}

// MARK: - Watch Progress

@Suite("Watch Progress")
@MainActor
struct WatchProgressTests {

    @Test("Watching a finished video again puts it back in Continue Watching")
    func rewatchClearsFinished() {
        let entry = WatchEntry(
            videoID: "rewatch", sourceRawValue: "youtube", title: "T",
            authorName: "C", authorID: "c", duration: 100
        )
        entry.updateProgress(seconds: 95)
        #expect(entry.isFinished)
        entry.updateProgress(seconds: 20)
        #expect(!entry.isFinished)
        #expect(entry.finishedAt == nil)
    }
}

// MARK: - Sleep Timer

@Suite("Sleep Timer", .serialized)
@MainActor
struct SleepTimerTests {

    @Test("Countdown shows minutes and seconds, and cancel clears it")
    func countdown() {
        let timer = SleepTimer.shared
        defer { timer.cancel() }
        timer.start(minutes: 15, environment: nil)
        #expect(timer.isActive)
        #expect(["15:00", "14:59"].contains(timer.caption ?? ""))
        #expect(timer.selectedMinutes == 15)
        timer.cancel()
        #expect(!timer.isActive && timer.caption == nil)
    }

    @Test("End-of-video mode stops playback once, then turns off")
    func endOfVideo() {
        let timer = SleepTimer.shared
        defer { timer.cancel() }
        #expect(!timer.consumeEndOfVideo())
        timer.startEndOfVideo(environment: nil)
        #expect(timer.caption == "播完这条")
        #expect(timer.consumeEndOfVideo())
        #expect(!timer.isActive)
        #expect(!timer.consumeEndOfVideo())
    }
}
