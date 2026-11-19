//
//  SubtitleFonts.swift
//  Yattee
//
//  Yattee Y: bundled CJK subtitle font for mpv/libass.
//
//  On iOS the system CJK fonts (PingFang etc.) are downloaded font assets under
//  /var/mobile/Library/UserFonts, outside the app sandbox. libass gets their paths
//  from CoreText but cannot open the files, so Chinese subtitles render as boxes.
//  We ship Noto Sans SC (SIL OFL) and point mpv's `sub-fonts-dir` at a folder that
//  holds only that font: libass reads every file in the folder into memory, so the
//  app bundle itself is not a suitable fonts dir.
//

import Foundation

enum SubtitleFonts {
    /// Family name of the bundled font, as libass matches it.
    static let family = "Noto Sans SC"
    private static let resource = "NotoSansSC-Regular"

    /// A directory containing only the bundled subtitle font, copying it there on
    /// first use. Nil if the font is missing from the bundle or cannot be copied.
    static let directory: String? = {
        guard let source = Bundle.main.url(forResource: resource, withExtension: "otf") else { return nil }
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = support.appendingPathComponent("SubtitleFonts", isDirectory: true)
        let target = dir.appendingPathComponent(source.lastPathComponent)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let sourceSize = (try? fm.attributesOfItem(atPath: source.path)[.size] as? Int) ?? -1
            let targetSize = (try? fm.attributesOfItem(atPath: target.path)[.size] as? Int) ?? -2
            if sourceSize != targetSize {
                try? fm.removeItem(at: target)
                try fm.copyItem(at: source, to: target)
            }
            return dir.path
        } catch {
            return nil
        }
    }()
}
