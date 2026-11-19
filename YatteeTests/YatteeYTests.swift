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

    @Test("Text font options name real CJK-capable families")
    func cjkFamilies() {
        #expect(SubtitleFont.sansSerif.mpvFontName == "PingFang SC")
        #expect(SubtitleFont.serif.mpvFontName != "serif")
    }
}
