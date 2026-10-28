// The shortcut intents of LiveActivityShared.swift, performed for real against observer.m: an answer after
// the player comes up, a failure that reaches Siri as the error's message, and the give-up when Spotify
// never answers.
import Foundation

@MainActor
func check(_ ok: Bool, _ what: String) {
    print(ok ? "ok   \(what)" : "FAIL \(what)")
    if !ok { exit(1) }
}

@main
struct Harness {
    @MainActor
    static func main() async {
        SGHarnessObserve(3)

        // Like: three posts unanswered while the player loads, the fourth answered.
        do {
            _ = try await SGLikeIntent().perform()
            check(SGHarnessPosts == 4, "like asked again until answered (\(SGHarnessPosts) posts)")
        } catch {
            check(false, "like threw \(error)")
        }

        SGHarnessPosts = 0
        do {
            _ = try await SGSingIntent(.on).perform()
            check(false, "sing:on should fail")
        } catch let error as SGShortcutError {
            check(error.message == "Karaoke needs its voice model." && SGHarnessPosts == 1, "a failure is thrown at once with its message")
            check(String(localized: error.localizedStringResource) == error.message, "the message reads out as it is")
        } catch {
            check(false, "sing threw \(error)")
        }

        SGHarnessPosts = 0
        _ = try? await SGSleepTimerIntent(.endOfTrack).perform()
        _ = try? await SGNextTrackIntent().perform()
        _ = try? await SGPlayPauseIntent().perform()
        check(SGHarnessPosts == 3, "timer, next and play or pause each answered first time")

        // End of album reaches LiveActivity.x as the Live Activity's own action, which SleepTimer.h's end of album sets.
        _ = try? await SGSleepTimerIntent(.endOfAlbum).perform()
        check(SGHarnessLastAction == "timer:album", "end of album posts \(String(describing: SGHarnessLastAction))")

        SGHarnessPosts = 0
        let start = Date()
        do {
            _ = try await SGPreviousTrackIntent().perform()
            check(false, "previous should give up")
        } catch let error as SGShortcutError {
            let took = Date().timeIntervalSince(start)
            check(SGHarnessPosts == 32 && took > 7.5 && took < 10, "gives up after 32 posts in \(String(format: "%.1f", took)) s: \(error.message)")
        } catch {
            check(false, "previous threw \(error)")
        }
        print("all passed")
    }
}
