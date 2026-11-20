//
//  WatchRatingBar.swift
//  Yattee
//
//  Yattee Y: the one-tap "这条怎么样？" bar shown after a watch (see WatchRater).
//

import SwiftUI

struct WatchRatingBar: View {
    let prompt: WatchRater.Prompt
    private var rater: WatchRater { .shared }

    #if os(tvOS)
    @FocusState private var focused: WatchRater.Rating?
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            switch prompt.stage {
            case .rate: rateRow
            case .followUp: followUpRow
            }
        }
        .padding(padding)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        #if os(tvOS)
        .focusSection()
        .onAppear { focused = .fun }
        #endif
    }

    // MARK: - Rows

    private var rateRow: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(alignment: .firstTextBaseline) {
                Text("这条怎么样？").font(.headline)
                Spacer()
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            chips
        }
    }

    @ViewBuilder
    private var chips: some View {
        #if os(tvOS)
        HStack(spacing: 24) {
            ForEach(WatchRater.Rating.allCases) { rating in
                Button { rater.toggle(rating) } label: { chipLabel(rating) }
                    .focused($focused, equals: rating)
            }
        }
        #else
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(WatchRater.Rating.allCases) { rating in
                Button { rater.toggle(rating) } label: {
                    chipLabel(rating)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(chipBackground(rating), in: Capsule())
                        .overlay(Capsule().strokeBorder(chipColor(rating).opacity(isOn(rating) ? 1 : 0), lineWidth: 2))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        #endif
    }

    private var followUpRow: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text("被带节奏了，要不要：").font(.headline)
            followUpButton("少推这个频道") { rater.followUp(lessChannel: true, unspin: false) }
            followUpButton("交给 unspin 分析这条") { rater.followUp(lessChannel: false, unspin: true) }
            followUpButton("不用了", secondary: true) { rater.followUp(lessChannel: false, unspin: false) }
        }
    }

    private func followUpButton(_ title: String, secondary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(secondary ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                #if !os(tvOS)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                #endif
        }
        #if !os(tvOS)
        .buttonStyle(.plain)
        #endif
    }

    // MARK: - Chip styling

    private func chipLabel(_ rating: WatchRater.Rating) -> some View {
        Text(isOn(rating) ? "\(rating.label) ✓" : rating.label)
            .font(.body.weight(isOn(rating) ? .semibold : .regular))
            .foregroundStyle(rating == .manipulative || isOn(rating) ? chipColor(rating) : .primary)
    }

    private func isOn(_ rating: WatchRater.Rating) -> Bool { prompt.selected.contains(rating) }

    private func chipColor(_ rating: WatchRater.Rating) -> Color {
        switch rating {
        case .fun: .orange
        case .learn: .green
        case .manipulative: .red
        case .meh: .secondary
        }
    }

    private func chipBackground(_ rating: WatchRater.Rating) -> AnyShapeStyle {
        isOn(rating) ? AnyShapeStyle(chipColor(rating).opacity(0.15)) : AnyShapeStyle(.quaternary)
    }

    // MARK: - Platform sizes

    private var hint: String {
        #if os(tvOS)
        "左右选，按下确认 · 不选也行"
        #else
        "可多选 · 不选也行"
        #endif
    }

    private var spacing: CGFloat {
        #if os(tvOS)
        20
        #else
        10
        #endif
    }

    private var padding: CGFloat {
        #if os(tvOS)
        32
        #else
        14
        #endif
    }

    private var cornerRadius: CGFloat {
        #if os(tvOS)
        28
        #else
        18
        #endif
    }

    private var maxWidth: CGFloat {
        #if os(tvOS)
        1100
        #else
        460
        #endif
    }
}

// MARK: - Placement

private struct WatchRatingOverlay: ViewModifier {
    /// True where the player is the top window content (expanded player); false for the main window.
    let inPlayer: Bool
    @Environment(\.appEnvironment) private var appEnvironment

    private var showsHere: Bool {
        (appEnvironment?.navigationCoordinator.isPlayerExpanded == true) == inPlayer
    }

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if showsHere, let prompt = WatchRater.shared.prompt {
                WatchRatingBar(prompt: prompt)
                    .padding(.horizontal, 16)
                    .padding(.bottom, bottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(prompt.id)
            }
        }
        .animation(.smooth(duration: 0.3), value: WatchRater.shared.prompt?.id)
        .animation(.smooth(duration: 0.2), value: WatchRater.shared.prompt?.stage == .followUp)
    }

    private var bottomPadding: CGFloat {
        #if os(tvOS)
        60
        #elseif os(macOS)
        20
        #else
        // Clear the tab bar and mini player in the main window.
        inPlayer ? 24 : 120
        #endif
    }
}

extension View {
    /// Yattee Y: shows the after-watch rating bar in this window when it belongs here.
    func watchRatingOverlay(inPlayer: Bool) -> some View {
        modifier(WatchRatingOverlay(inPlayer: inPlayer))
    }
}
