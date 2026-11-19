//
//  HomeChipsRow.swift
//  Yattee
//
//  Yattee Y: a single row of small chips that replaces the home page's big
//  shortcut cards when the recommendation feed is shown, so the feed starts
//  near the top of the screen.
//

import SwiftUI

#if !os(tvOS)
struct HomeChip: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var count: Int? = nil
    let action: () -> Void
}

struct HomeChipsRow: View {
    let chips: [HomeChip]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    Button(action: chip.action) {
                        HStack(spacing: 5) {
                            Image(systemName: chip.systemImage)
                                .font(.caption)
                            Text(chip.title)
                            if let count = chip.count, count > 0 {
                                Text("\(count)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.quaternary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }
}
#endif
