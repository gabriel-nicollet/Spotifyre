// Controls for Control Center, the lock screen and the Action button (iOS 18): Like, Sing and the sleep
// timer. Each runs one of LiveActivityShared.swift's shortcut intents, which perform inside Spotify. They are
// buttons, not toggles: what Sing is doing lives in Spotify, and this extension shares no container with it
// to read it from, so a toggle's on and off would be a guess.
import AppIntents
import SwiftUI
import WidgetKit

private let green = Color(red: 0.12, green: 0.84, blue: 0.38)

@available(iOS 18.0, *)
struct SGLikeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "spotifyglass.control.like") {
            ControlWidgetButton(action: SGLikeIntent()) {
                Label("Like This Song", systemImage: "heart")
                    .controlWidgetActionHint("Like")
            }
            .tint(green)
        }
        .displayName("Like This Song")
        .description("Adds the song playing in Spotify to Liked Songs.")
    }
}

@available(iOS 18.0, *)
struct SGSingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "spotifyglass.control.sing") {
            ControlWidgetButton(action: SGSingIntent(.toggle)) {
                Label("Karaoke", systemImage: "music.mic")
                    .controlWidgetActionHint("Turn Karaoke On or Off")
            }
            .tint(green)
        }
        .displayName("Karaoke")
        .description("Turns the vocals down in Spotify so you can sing along, or brings them back.")
    }
}

// Which length the sleep timer control sets, picked when it is added.
@available(iOS 18.0, *)
struct SGSleepTimerControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Sleep Timer"
    static let isDiscoverable = false

    @Parameter(title: "Length", default: .thirty)
    var length: SGSleepTimerLength
}

@available(iOS 18.0, *)
struct SGSleepTimerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "spotifyglass.control.sleeptimer", intent: SGSleepTimerControlConfiguration.self) { configuration in
            ControlWidgetButton(action: SGSleepTimerIntent(configuration.length)) {
                Label {
                    Text("Sleep Timer")
                    Text(SGSleepTimerLength.caseDisplayRepresentations[configuration.length]?.title ?? "")
                } icon: {
                    Image(systemName: "moon.zzz")
                }
                .controlWidgetActionHint(configuration.length == .off ? "Turn Off the Sleep Timer" : "Start the Sleep Timer")
            }
            .tint(green)
        }
        .displayName("Sleep Timer")
        .description("Pauses Spotify after the length you pick, or at the end of the track or the album.")
        .promptsForUserConfiguration()
    }
}
