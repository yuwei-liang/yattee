//
//  FeedWishes.swift
//  Yattee
//
//  Yattee Y: "跟推荐说一句". The viewer tells the feed in plain words what they
//  want right now (「我想要几个纪录片看看」). Wishes live on our Yattee Server,
//  so every device sees them, and Claude reads them on the next curated round:
//  either the next scheduled update (free) or a rebuild started right away.
//

import SwiftUI

/// How long a wish stays in force.
enum FeedWishScope: String, CaseIterable, Identifiable {
    case today, week, always

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "今天"
        case .week: "这周"
        case .always: "一直"
        }
    }

    /// "今天" lasts until 5 the next morning (at least six hours), "这周" seven days, "一直" until removed.
    func until(from now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .today:
            var fiveAM = calendar.date(bySettingHour: 5, minute: 0, second: 0, of: now) ?? now
            while fiveAM < now.addingTimeInterval(6 * 3600) {
                fiveAM = calendar.date(byAdding: .day, value: 1, to: fiveAM) ?? now.addingTimeInterval(86400)
            }
            return fiveAM
        case .week:
            return now.addingTimeInterval(7 * 86400)
        case .always:
            return nil
        }
    }
}

extension FeedWish {
    /// 「今天有效」「到周四」「一直有效」
    var scopeLabel: String {
        guard let until else { return "一直有效" }
        let end = Date(timeIntervalSince1970: until)
        if end.timeIntervalSinceNow < 30 * 3600 { return "今天有效" }
        return "到" + end.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "zh_CN")))
    }
}

extension FeedWishesStatus {
    /// 「约 3 小时后」, for the free button.
    var nextUpdateLabel: String {
        let hours = (nextUpdate - Date().timeIntervalSince1970) / 3600
        if hours < 1 { return "1 小时内" }
        return "约 \(Int(hours.rounded())) 小时后"
    }
}

/// One wish on the feed: what they said, how long it lasts, what the last round did, and ✕.
struct FeedWishRow: View {
    let wish: FeedWish
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "text.bubble")
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("你说：\(wish.text)")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    #if !os(tvOS)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    #endif
            }
            #if !os(tvOS)
            .buttonStyle(.plain)
            #endif
            .accessibilityLabel("撤回这句")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var detail: String {
        if !wish.result.isEmpty { return "\(wish.scopeLabel) · \(wish.result)" }
        if wish.used == nil { return "\(wish.scopeLabel) · 等下次更新时用" }
        return wish.scopeLabel
    }
}

/// The 「说一句」 panel: say one or several things, pick how long they last, then queue them or rebuild now.
struct FeedWishSheet: View {
    let status: FeedWishesStatus?
    let remove: (FeedWish) -> Void
    /// texts, until, rebuild now
    let submit: ([String], Date?, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var lines: [String] = []
    @State private var scope: FeedWishScope = .today
    @FocusState private var fieldFocused: Bool

    private static let suggestions = ["想看几部纪录片", "来点轻松的", "少点游戏", "想学点东西", "长一点的", "短一点的"]

    private var texts: [String] {
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return lines + (typed.isEmpty ? [] : [typed])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let wishes = status?.wishes, !wishes.isEmpty {
                        section("还在生效的") {
                            ForEach(wishes) { wish in
                                FeedWishRow(wish: wish) { remove(wish) }
                            }
                        }
                    }

                    section("想跟推荐说什么（可以连着说好几句）") {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            HStack {
                                Text(line).font(.subheadline)
                                Spacer()
                                Button {
                                    lines.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle").foregroundStyle(.secondary)
                                }
                                #if !os(tvOS)
                                .buttonStyle(.plain)
                                #endif
                                .accessibilityLabel("删掉这句")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                        }
                        HStack(spacing: 8) {
                            TextField("比如：我想要几个纪录片看看", text: $draft)
                                .focused($fieldFocused)
                                .submitLabel(.next)
                                .onSubmit(addDraft)
                                #if !os(tvOS)
                                .textFieldStyle(.roundedBorder)
                                #endif
                            Button("加一句", action: addDraft)
                                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Self.suggestions, id: \.self) { text in
                                    Button(text) {
                                        if !lines.contains(text) { lines.append(text) }
                                    }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                }
                            }
                        }
                    }

                    section("多久有效") {
                        Picker("多久有效", selection: $scope) {
                            ForEach(FeedWishScope.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    buttons
                }
                .padding(20)
            }
            .navigationTitle("跟推荐说一句")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #elseif os(macOS)
        .frame(minWidth: 460, minHeight: 480)
        #endif
        .onAppear { fieldFocused = true }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button {
                send(now: false)
            } label: {
                VStack(spacing: 2) {
                    Text("下次更新时用").font(.headline)
                    Text("免费 · \(status?.nextUpdateLabel ?? "几小时内")").font(.caption2)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)

            Button {
                send(now: true)
            } label: {
                VStack(spacing: 2) {
                    Text("现在就重挑").font(.headline)
                    Text("多挑一次 · 约 1 分钟").font(.caption2)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .tint(.purple)
        .disabled(texts.isEmpty)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func addDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        lines.append(text)
        draft = ""
        fieldFocused = true
    }

    private func send(now: Bool) {
        let all = texts
        guard !all.isEmpty else { return }
        submit(all, scope.until(), now)
        dismiss()
    }
}
