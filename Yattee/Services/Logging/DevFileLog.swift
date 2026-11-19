//
//  DevFileLog.swift
//  Yattee
//
//  Development builds only (compiled with YATTEE_DEV_LOG): appends mpv log lines and a
//  one-off font report to Documents/dev.log, so the file can be read back from a test
//  device with `xcrun devicectl device copy from --domain-type appDataContainer`.
//

import Foundation

#if YATTEE_DEV_LOG
import CoreText

enum DevFileLog {
    private static let queue = DispatchQueue(label: "com.yuweiliang.yattee.devfilelog")
    private static let url: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("dev.log")
    }()
    private static var reportedFonts = false

    static func write(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("\(stamp) \(line)\n".utf8)
        queue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// Logs which CJK-capable families CoreText can see, once per launch.
    static func reportFontsOnce() {
        guard !reportedFonts else { return }
        reportedFonts = true
        let families = (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
        let cjk = families.filter { $0.localizedCaseInsensitiveContains("PingFang")
            || $0.localizedCaseInsensitiveContains("Heiti")
            || $0.localizedCaseInsensitiveContains("Hiragino")
            || $0.localizedCaseInsensitiveContains("Songti") }
        write("fonts: \(families.count) families; CJK-looking: \(cjk)")
        let font = CTFontCreateWithName("PingFang SC" as CFString, 16, nil)
        let family = CTFontCopyFamilyName(font) as String
        let path = (CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL)?.path ?? "nil"
        write("fonts: CTFontCreateWithName(\"PingFang SC\") -> family=\(family) path=\(path)")
        if let fontsDir = try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Fonts") {
            write("fonts: /System/Library/Fonts = \(fontsDir)")
        }
    }
}
#endif
