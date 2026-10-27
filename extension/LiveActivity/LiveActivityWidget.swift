// The Live Activity's face, one of three views: the line being sung with the next one under it, the
// tracks up next, or the control menu, a tab bar over Controls, Queue and Timer. A tap reaches the
// tweak as an intent and the new state takes over a second to render, so every on/off control is a
// Toggle, whose look the system flips the moment it is tapped, and what only changes after the render
// is marked invalidatable. iOS clips a lock screen Live Activity at 160 points, so every view is kept
// under it. Built with the tweak's LiveActivityShared.swift by scripts/build-extension.sh.
import ActivityKit
import AppIntents
import SwiftUI
import UIKit
import WidgetKit

private let green = Color(red: 0.12, green: 0.84, blue: 0.38)
private let idle = Color.white.opacity(0.08)

// The accent, Spotify's green or what the page's Colors puts in its place (accentOf), set at the card's
// root and each of the island's, so the views under them read it.
private struct AccentKey: EnvironmentKey {
    static let defaultValue = green
}

private extension EnvironmentValues {
    var accent: Color {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}

private typealias State = SGLyricsAttributes.ContentState
private typealias Tab = SGLyricsAttributes.Tab

@main
struct SGLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        SGLyricsLiveActivity()
        if #available(iOS 18.0, *) {
            SGLyricsWatchLiveActivity()
            SGLikeControl()
            SGSingControl()
            SGSleepTimerControl()
        }
    }
}

private func color(hex: String?) -> Color? {
    guard let hex, hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
    return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                 blue: Double(value & 0xFF) / 255)
}

// The cover's color, RRGGBB, as the card's background, the old translucent black without one; under Plain
// nil, the system's own background.
private func tint(_ state: State) -> Color? {
    if state.colors == 2 { return nil }
    return color(hex: state.tint) ?? Color.black.opacity(0.75)
}

// Spotify's green; under Artwork the cover's color, lightened by the tweak to keep 4.5:1 on the card; under
// Plain white.
private func accentOf(_ state: State) -> Color {
    switch state.colors {
    case 1: color(hex: state.accent) ?? green
    case 2: .white
    default: green
    }
}

private extension View {
    func accented(_ state: State) -> some View {
        environment(\.accent, accentOf(state))
    }
}

private func coverImage(_ state: State) -> UIImage? {
    state.cover.flatMap(UIImage.init(data:))
}

// The cover, a few dozen pixels a side and drawn larger, so it reads as the cover and not as a picture of it.
private struct Cover: View {
    let image: UIImage
    let side: CGFloat

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side / 6, style: .continuous))
            .accessibilityLabel("Album artwork")
    }
}

// The compact and minimal Dynamic Island's leading view, which Apple Watch and CarPlay show too: the
// cover, or a note before it is read.
private struct Badge: View {
    let state: State
    @Environment(\.accent) private var accent

    var body: some View {
        if let image = coverImage(state) {
            Cover(image: image, side: 22)
        } else {
            Image(systemName: "music.note")
                .foregroundStyle(accent)
        }
    }
}

extension SGLyricsAttributes.Tab {
    var symbol: String {
        switch self {
        case .controls: "slider.horizontal.3"
        case .queue: "list.bullet"
        case .timer: "moon.zzz"
        }
    }

    var title: String {
        switch self {
        case .controls: "Controls"
        case .queue: "Queue"
        case .timer: "Timer"
        }
    }
}

struct SGLyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        lyricsActivity(SGLyricsAttributes.self) { FamilyView(state: $0) }
    }
}

// The same activity from iOS 18, with its own small layout on Apple Watch and in CarPlay.
@available(iOS 18.0, *)
struct SGLyricsWatchLiveActivity: Widget {
    var body: some WidgetConfiguration {
        lyricsActivity(SGLyricsWatchAttributes.self) { FamilyAwareView(state: $0) }
            .supplementalActivityFamilies([.small])
    }
}

private func lyricsActivity<A: ActivityAttributes, Card: View>(
    _: A.Type, @ViewBuilder card: @escaping (State) -> Card
) -> ActivityConfiguration<A> where A.ContentState == State {
    ActivityConfiguration(for: A.self) { context in
        card(context.state)
            .accented(context.state)
            .foregroundStyle(.white)
            .activityBackgroundTint(tint(context.state))
            .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
        DynamicIsland {
            // The row beside the camera: a note, and the sleep timer or whether it plays.
            DynamicIslandExpandedRegion(.leading) {
                Image(systemName: "music.note")
                    .foregroundStyle(accentOf(context.state))
                    .padding(.leading, 6)
            }
            DynamicIslandExpandedRegion(.trailing) {
                Group {
                    if let end = runningTimer(context.state) {
                        Countdown(end: end)
                    } else {
                        PlayingSymbol(state: context.state)
                    }
                }
                .padding(.trailing, 6)
                .accented(context.state)
            }
            DynamicIslandExpandedRegion(.bottom) {
                Group {
                    if context.state.view == .panel {
                        Summary(state: context.state)
                    } else {
                        ContentView(state: context.state, upNext: 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                // The island is always black, whatever the card's tint.
                .foregroundStyle(.white)
                .accented(context.state)
            }
        } compactLeading: {
            Badge(state: context.state)
                .accented(context.state)
        } compactTrailing: {
            Group {
                if let end = runningTimer(context.state) {
                    Countdown(end: end)
                        .frame(maxWidth: 44)
                } else {
                    ProgressRing(state: context.state)
                }
            }
            .accented(context.state)
        } minimal: {
            Badge(state: context.state)
                .accented(context.state)
        }
    }
}

@available(iOS 18.0, *)
private struct FamilyAwareView: View {
    let state: State
    @Environment(\.activityFamily) private var family

    var body: some View {
        switch family {
        case .small: SmallView(state: state)
        default: FamilyView(state: state)
        }
    }
}

// Apple Watch's Smart Stack and CarPlay: the cover and the line, or the track while the view is not
// the lyrics, and the bar under them. Nothing to tap, since a tap there opens Spotify on the iPhone.
private struct SmallView: View {
    let state: State

    private var lines: (String, String) {
        if state.view == .lyrics, !state.line.isEmpty {
            return (state.line, state.translation.flatMap { $0.isEmpty ? nil : $0 } ?? state.nextLine)
        }
        return (state.title, state.artist)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if let image = coverImage(state) {
                    Cover(image: image, side: 32)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(lines.0)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .direction(of: lines.0)
                    if !lines.1.isEmpty {
                        Text(lines.1)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                            .direction(of: lines.1)
                    }
                }
            }
            ProgressBar(state: state)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
    }
}

// The lock screen's card, and StandBy's: the cover beside what the view shows, and the bar under both.
// The control menu uses the whole width, so it goes without the cover.
private struct FamilyView: View {
    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: state.view == .panel ? 6 : 10) {
            HStack(alignment: .center, spacing: 12) {
                if state.view != .panel, let image = coverImage(state) {
                    Cover(image: image, side: 52)
                }
                ContentView(state: state, upNext: 3)
            }
            ProgressBar(state: state)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, state.view == .panel ? 12 : 16)
        .padding(.vertical, state.view == .panel ? 8 : 12)
        // The tallest view, the menu's Queue, comes to 156 of the 160 points: 16 of padding, 32 of tabs, three
        // rows of at least 28 with 4 between, two gaps of 6 and the 4 point bar. Text at the accessibility sizes
        // would grow the rows past the clip, so it stops at the largest size before them, where a footnote
        // line still fits a 28 point row.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

// The sleep timer's end while it is still ahead; nil once it is up or when none is set, so no countdown
// is drawn from a range that runs backwards.
private func runningTimer(_ state: State) -> Date? {
    state.timerEnd.flatMap { $0 > Date() ? $0 : nil }
}

private struct Countdown: View {
    let end: Date
    @Environment(\.accent) private var accent

    var body: some View {
        Text(timerInterval: Date()...end, countsDown: true)
            .monospacedDigit()
            .foregroundStyle(accent)
    }
}

// Paused or playing, where there is no progress or sleep timer to show.
private struct PlayingSymbol: View {
    let state: State
    @Environment(\.accent) private var accent

    var body: some View {
        Image(systemName: state.paused ? "pause.fill" : "waveform")
            .foregroundStyle(accent)
    }
}

// The track's progress as a ring, for the compact Dynamic Island, which Apple Watch and CarPlay show too.
private struct ProgressRing: View {
    let state: State
    @Environment(\.accent) private var accent

    var body: some View {
        if let start = state.trackStart, let end = state.trackEnd, end > start {
            Group {
                if state.paused, let at = state.pausedAt {
                    ProgressView(value: at)
                } else {
                    ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                }
            }
            .progressViewStyle(.circular)
            .tint(accent)
            .frame(width: 18, height: 18)
        } else {
            PlayingSymbol(state: state)
        }
    }
}

// The track's progress, running by itself between two dates while it plays and held while it is paused.
private struct ProgressBar: View {
    let state: State

    var body: some View {
        if state.progressBar ?? true, let start = state.trackStart, let end = state.trackEnd, end > start {
            Group {
                if state.paused, let at = state.pausedAt {
                    ProgressView(value: at)
                } else {
                    ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                }
            }
            .progressViewStyle(.linear)
            .tint(.white)
            .frame(height: 4)
        }
    }
}

private struct ContentView: View {
    let state: State
    let upNext: Int

    var body: some View {
        switch state.view {
        case .lyrics: LyricsView(state: state)
        case .queue: QueueView(state: state, upNext: upNext)
        case .panel: PanelView(state: state)
        }
    }
}

// MARK: - Lyrics and queue

private struct LyricsView: View {
    let state: State

    // The page's Text size; the scale factor below still keeps a long line inside the 160 point clip.
    private var lineFont: Font {
        switch state.textSize {
        case 0: .headline
        case 2: .title2
        default: .title3
        }
    }

    // The page's Alignment: centered by default, or left. Left is the leading edge, so a line written right to
    // left still starts at the right (direction(of:)).
    private var centered: Bool { (state.alignment ?? 1) == 1 }
    private var edge: HorizontalAlignment { centered ? .center : .leading }
    private var frameEdge: Alignment { centered ? .center : .leading }

    var body: some View {
        // No line being sung (before the first, in a break, without lyrics): the track holds the place, and on a
        // track with no timed lyrics under Without lyrics' Note, at its own size over a line saying so.
        if state.line.isEmpty || state.line == "♪" {
            if state.noLyrics == true, (state.withoutLyrics ?? 0) == 0 {
                note
            } else {
                track
            }
        } else {
            line
        }
    }

    private var track: some View {
        VStack(alignment: edge, spacing: 2) {
            Text(state.title.isEmpty ? "♪" : state.title)
                .font(lineFont.weight(.bold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: frameEdge)
                .direction(of: state.title)
            if !state.title.isEmpty, !state.artist.isEmpty {
                Text(state.artist)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: frameEdge)
                    .direction(of: state.artist)
            }
        }
    }

    private var note: some View {
        VStack(alignment: edge, spacing: 2) {
            Text(state.title)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: frameEdge)
                .direction(of: state.title)
            Text(state.artist)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: frameEdge)
                .direction(of: state.artist)
            Text("No synced lyrics for this song")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: frameEdge)
                .padding(.top, 4)
        }
    }

    private var line: some View {
        VStack(alignment: edge, spacing: 4) {
            Text(state.line)
                .font(lineFont.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(centered ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: frameEdge)
                .direction(of: state.line)
            if let translation = state.translation, !translation.isEmpty {
                Text(translation)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                    .multilineTextAlignment(centered ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: frameEdge)
                    .direction(of: translation)
            }
            if !state.nextLine.isEmpty {
                Text(state.nextLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: frameEdge)
                    .direction(of: state.nextLine)
            }
        }
    }
}

// Whether a line is written right to left, told by its first letter the way the Unicode bidi algorithm
// tells a paragraph's direction. Each line is asked on its own, since a song can mix scripts, and the
// phone's language has no say in it. The tweak's lyrics page asks the same (SGRKaraokeView.m).
private func readsRightToLeft(_ text: String) -> Bool {
    guard let first = text.unicodeScalars.first(where: { $0.properties.isAlphabetic }) else { return false }
    switch first.value {
    case 0x0590...0x08FF,      // Hebrew, Arabic, Syriac, Thaana, N'Ko and on
         0xFB1D...0xFDFF,      // Hebrew and Arabic presentation forms
         0xFE70...0xFEFF,      // Arabic presentation forms B
         0x10800...0x10FFF,    // the old scripts written right to left
         0x1E800...0x1EFFF:    // Mende Kikakui and Adlam
        return true
    default:
        return false
    }
}

private extension View {
    // A line written right to left is laid out right to left, against the right edge; any other is left
    // the way it was.
    @ViewBuilder func direction(of line: String) -> some View {
        if readsRightToLeft(line) {
            frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .rightToLeft)
        } else {
            self
        }
    }
}

private struct QueueView: View {
    let state: State
    let upNext: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Up next")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
            if state.tracks.isEmpty {
                Text("Nothing up next")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            ForEach(Array(state.tracks.prefix(upNext).enumerated()), id: \.offset) { _, track in
                // A tap skips ahead to the track.
                Button(intent: SGPlayQueuedTrackIntent(track.uri)) {
                    (Text(track.title).fontWeight(.semibold) + Text("  " + track.artist).foregroundColor(.white.opacity(0.6)))
                        .font(.subheadline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Control menu

// The expanded Dynamic Island has room for one line of the menu.
private struct Summary: View {
    let state: State

    var body: some View {
        Group {
            switch state.tab {
            case .controls:
                Text("\(state.title) · \(state.artist)")
            case .queue:
                Text(state.tracks.first.map { "Next: \($0.title)" } ?? "Nothing up next")
            case .timer:
                if let end = state.timerEnd, end > Date() {
                    Text("Music stops in \(Text(timerInterval: Date()...end, countsDown: true))")
                } else if state.timerEndOfTrack {
                    Text("Music stops at the end of this track")
                } else if state.timerEndOfAlbum == true {
                    Text("Music stops at the end of this album")
                } else {
                    Text("No sleep timer")
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .invalidatableContent()
    }
}

private struct PanelView: View {
    let state: State

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Toggle(isOn: tab == state.tab, intent: SGLiveActivityActionIntent("tab:\(tab.rawValue)")) {
                        Text(tab.title)
                    }
                    .toggleStyle(TabStyle(tab: tab))
                    .accessibilityLabel(tab.title)
                    .accessibilityValue(tab == state.tab ? "Selected" : "Not selected")
                }
            }
            Group {
                switch state.tab {
                case .controls: ControlsPage(state: state)
                case .queue: QueuePage(state: state)
                case .timer: TimerPage(state: state)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TabStyle: ToggleStyle {
    let tab: Tab
    @Environment(\.accent) private var accent

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            Image(systemName: tab.symbol)
            if configuration.isOn {
                configuration.label
            }
        }
        .font(.caption.weight(.semibold))
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .background(Capsule().fill(configuration.isOn ? accent.opacity(0.22) : idle))
        .foregroundStyle(configuration.isOn ? accent : .white.opacity(0.7))
    }
}

private struct ChipLabel: View {
    let symbol: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
            Text(label)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
    }
}

private struct ChipStyle: ToggleStyle {
    let symbol: String
    var onSymbol: String?
    let label: String
    var onLabel: String?
    // Play and pause flips its symbol but is not a setting, so it keeps the idle fill either way.
    var lights = true
    @Environment(\.accent) private var accent

    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        ChipLabel(symbol: on ? onSymbol ?? symbol : symbol, label: on ? onLabel ?? label : label)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on && lights ? accent.opacity(0.22) : idle))
            .foregroundStyle(on && lights ? accent : .white)
    }
}

private struct ChipButton: View {
    let action: String
    let symbol: String
    let label: String
    var lit = false
    // What VoiceOver and Voice Control say, where the short label on the chip would read wrong: "15m" as 15 meters.
    var spoken: String?
    @Environment(\.accent) private var accent

    var body: some View {
        Button(intent: SGLiveActivityActionIntent(action)) {
            ChipLabel(symbol: symbol, label: label)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(lit ? accent.opacity(0.22) : idle))
                .foregroundStyle(lit ? accent : .white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken ?? label)
    }
}

private struct ControlsPage: View {
    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(state.title)
                    .font(.subheadline.weight(.semibold))
                Text(state.artist)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            .invalidatableContent()
            HStack(spacing: 10) {
                ChipButton(action: "previous", symbol: "backward.fill", label: "Previous")
                // Named for what it shows, so Voice Control's "Tap Pause" finds it while it plays.
                Toggle(isOn: !state.paused, intent: SGLiveActivityActionIntent("toggle")) { Text(state.paused ? "Play" : "Pause") }
                    .accessibilityLabel(state.paused ? "Play" : "Pause")
                    .toggleStyle(ChipStyle(symbol: "play.fill", onSymbol: "pause.fill", label: "Play", onLabel: "Pause", lights: false))
                ChipButton(action: "next", symbol: "forward.fill", label: "Next")
                Toggle(isOn: state.shuffle, intent: SGLiveActivityActionIntent("shuffle")) { Text("Shuffle") }
                    .accessibilityLabel("Shuffle")
                    .accessibilityValue(state.shuffle ? "On" : "Off")
                    .toggleStyle(ChipStyle(symbol: "shuffle", label: "Shuffle"))
                // Three states, so a button: the new one shows once the render lands.
                ChipButton(action: "repeat", symbol: state.repeatMode == 2 ? "repeat.1" : "repeat",
                           label: "Repeat", lit: state.repeatMode != 0)
                    .accessibilityValue(["Off", "All", "One"][min(max(state.repeatMode, 0), 2)])
                    .invalidatableContent()
            }
        }
    }
}

private struct QueuePage: View {
    let state: State
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(spacing: 4) {
            if state.tracks.isEmpty {
                Text("Nothing up next")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            ForEach(Array(state.tracks.prefix(3).enumerated()), id: \.offset) { _, track in
                Button(intent: SGPlayQueuedTrackIntent(track.uri)) {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .foregroundStyle(accent)
                        Text(track.title)
                            .font(.footnote.weight(.semibold))
                        Text(track.artist)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer(minLength: 0)
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(idle))
                }
                .buttonStyle(.plain)
            }
        }
        .invalidatableContent()
    }
}

private struct TimerPage: View {
    let state: State
    @Environment(\.accent) private var accent

    var body: some View {
        Group {
            if (state.timerEnd.map { $0 > Date() } ?? false) || state.timerEndOfTrack || state.timerEndOfAlbum == true {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Music stops")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                        if let end = state.timerEnd {
                            Text(timerInterval: Date()...end, countsDown: true)
                                .font(.system(size: 34, weight: .bold).monospacedDigit())
                                .foregroundStyle(accent)
                        } else {
                            Text(state.timerEndOfAlbum == true ? "End of album" : "End of track")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(accent)
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        if state.timerEnd != nil {
                            ChipButton(action: "timer:add", symbol: "plus", label: "15m", spoken: "Add 15 minutes")
                        }
                        ChipButton(action: "timer:cancel", symbol: "xmark", label: "Cancel")
                    }
                    .frame(width: state.timerEnd != nil ? 140 : 66)
                }
            } else {
                HStack(spacing: 8) {
                    ChipButton(action: "timer:15", symbol: "moon", label: "15m", spoken: "15 minutes")
                    ChipButton(action: "timer:30", symbol: "moon", label: "30m", spoken: "30 minutes")
                    ChipButton(action: "timer:60", symbol: "moon", label: "1h", spoken: "1 hour")
                    ChipButton(action: "timer:track", symbol: "music.note", label: "Track", spoken: "End of track")
                    ChipButton(action: "timer:album", symbol: "square.stack", label: "Album", spoken: "End of album")
                }
            }
        }
        .invalidatableContent()
    }
}
