# Parity with spoti.pw 0.50.0

Every line of upstream's 0.22.0, 0.23.0-beta and 0.50.0 release notes, and where Vitrine stands on it.
Each feature is written from its release note and public APIs, never from upstream's code after
`c790445`, which is PolyForm Strict.

Numbers are the line's position in the three release notes, in order. Status:

- **done**: built and on main. "Device" means it still needs a check on a phone inside Spotify.
- **in progress**: being built on its own branch
- **todo**: to build
- **n/a**: depends on chroma.pw, Plus or the upstream server, so Vitrine leaves it out

A completeness audit on 2026-10-05 checked every done item below against its release note. Its gaps were
fixed in the commits that follow `956e65c`.

## Done

### Apple Music artwork

| # | Item |
|---|---|
| 1, 6 | Lock screen moving artwork: the Canvas, else Apple Music's animated cover |
| 15 | Album page plays the animated cover |
| 114 | Artist page shows Apple Music's artist logo |
| 77 | Low Data Mode switch on the Lock screen widget, Now playing and Albums & artists pages |
| 75 | Albums & artists page: animated covers, logos, a switch for each section the redesign hides |

### Redesigned player artwork

| # | Item |
|---|---|
| 16, 18, 78 | Fluid and Animated artwork behind the player, edge to edge |
| 76, 121, 122 | Blur under the controls and behind the lyrics, the seam and the foot, on and off from the ⋯ menu |
| 106, 120 | Lock screen animates every song: its cover over a moving Fluid field |

### Lyrics

| # | Item |
|---|---|
| 36, 69, 109 | Lyrics take the whole player while untouched, a scroll hides the controls, the translate button goes with them |
| 32, 13 | Tap the cover to bring the player back, tap the progress bar to seek |
| 115 | Sung word glows the longer it is held |
| 111, 88, 124 | Landscape lyrics, with the meanings sheet |
| 94 | Translation: Musixmatch's community translations, or Gemini with your own key |
| 31, 138 | Spicy Lyrics with your own Developer Platform key |
| 82, 93, 125, 60 | Lock screen lyrics as full-screen artwork, a clip per line, Still by default, no progress jump |

### Player and audio

| # | Item |
|---|---|
| 30, 23 | Pitch follows speed, on until turned off |
| 67 | Reverb slider in the player's ⋯ menu |
| 84 | Hold either side of the cover to play faster, under either look |
| 80, 83 | Presets, and AutoEq headphone corrections from AutoEq's public data |
| 27, 28, 29, 20, 103, 87, 55, 130, 53, 56 | Sing: model download, vocals slider, mic button, heat switch, iOS 18 floor |
| 81, 92 | Local files: Edit Info and lyrics |

### System

| # | Item |
|---|---|
| 73, 74 | AirPods gestures: double nod likes, shake skips, learns your motion |
| 97 | Music Haptics through iOS in the background and on the lock screen |
| 90, 105 | Live Activity: the cover, its color, progress, centered and translated lyrics, and a small layout on Apple Watch and CarPlay from iOS 18 |
| 89 | Listening stats, with Spotify's export imported |
| 79, 98 | Apple Music red accent, one font for the whole app |
| 17 | Beta builds update to the next beta, then the release. Mod > Include betas lets a release build opt in |

### Round 2: player, pages, lyrics, settings

| # | Item |
|---|---|
| 85 | Sing's spatial voice with AirPods |
| 22, 123 | App icons: the picker, `icons/`, and Vitrine's own icon |
| 42, 137 | Cover size fixes (the cover fills the lyric preview's room, under either look) |
| 112, 38 | Player page led by a showcase of the player, its background as a menu |
| 39, 40, 49, 61, 64, 136 | Player ⋯ opens the system menu, with speed, pitch, reverb and Animated artwork |
| 110 | Pinned ⋯ on playlist, album and artist pages opens the system menu |
| 104 | Hide Switch to video |
| 63 | Redesigned player for Spotify Free |
| 47 | Local files at another sample rate (device check outstanding) |
| 21, 33, 68, 132, 133 | Tab bar minimizes on scroll, the now playing bar in its row |
| 14, 113, 128, 44 | Add a tab sheet, own names and SF Symbol or Encore icons, Split tabs |
| 45, 59 | Fades under the tab bar |
| 41, 43, 34, 134 | Pages come in whole, cover color, owner pictures, section cards |
| 71, 119 | Album track rows drop the artist line that repeats the album's |
| 101 | Save turns into download on someone else's playlist, for accounts that can download |
| 62 | Playlist Mix can be turned off again |
| 24, 46, 50 | Connect discovery without the multicast entitlement |
| 108 | Lyrics page live preview and presets, a held word's letters rising in a wave |
| 48, 58, 118, 126 | Lyrics fixes |
| 57 | No freeze with EeveeSpotify's lyrics on |
| 95 | Mod Settings in the system Settings' style, Appearance on its own page |
| 70 | A dependent setting grays out instead of vanishing |
| 72 | What's new sheet (empty until the fork's first release) |
| 116, 117, 37 | Tour: glass logo, redesign below iOS 26 after a warning |
| 25, 26 | Say when EeveeSpotify is injected, or Spotify's version differs |
| 127, 135, 52 | Settings fixes |
| 66 | Less main-thread work for the flags Spotify reads at launch |

### Beta gaps (0.23.0-beta, described by behavior)

A separate describer compared upstream's beta branch with Vitrine by behavior only (local notes, not in the
repo). Rounds 3 and 4 closed most of it: Spicy Lyrics' key, credit, pronunciations and back-off; the paused cover;
the clip's pause, Spotify's video, late Canvas, next-track fetch and give-up; the lyrics left alone; tap to seek;
the lock screen's Canvas shape, late Canvas and Canvas service; the lit custom tab; the update check; EeveeSpotify
by class; the app icon error; Signed until; two output chains; and Karaoke's memory, heat, hardware, hysteresis
and download. The rest, on `fix/beta-gaps`:

| Item | Commit |
|---|---|
| The player's clip gives way to Fluid under Reduce Motion and Low Power Mode, and goes at once when the track changes unseen | `992f379` |
| The player's clip is dimmed by its brightness, 4.5:1 (7:1 with Increase Contrast) for white text | `992f379` |
| A failed clip download is tried again once | `e0ee995` |
| Apple Music's catalog: 10 minutes alone after a 403 or 429, searched without the album's edition | `54eb39b` |
| A settings section whose rows all hide takes its heading and note; the ticker follows rows, sliders and menus | `08a9eeb` |
| Below iOS 26 the Lock screen page says Full-screen artwork needs iOS 26 | `be1a478` |
| The Mod Settings row comes back when Spotify empties its settings list or drawer | `8f9f839` |
| The install warning waits for Spotify in front; an unreadable version is not a wrong one | `e26e8a5` |
| Lyrics are looked up for the next track in the background | `28e9e2e` |
| Speed and pitch: no second mixer pull after a failed render, a silent mixer buffer zeroed | `b7bb9d7` |

Still open from the beta gaps: Fluid artwork's settings (SGRFluid.m is being changed elsewhere); the lyrics
opening for Karaoke on a song without lyrics; Karaoke's background download, output latency, interruption and
route handling, seeks and read-ahead limit (the Karaoke rewrite owns them); a change to or from Lyrics on the lock
screen still needs a restart. Deliberate differences: the Off default for the lock screen artwork, the lock
screen page's flag rows, the Reinvented Free player mode turned off, the title kept over the lyrics left alone.
Not gaps: Hide social proof (both flags ship off), recvmsg (Spotify 9.1.78 does not import it).

### From upstream pull requests

Rebuilt from behavior-only descriptions; each commit credits the PR's author.

| PR | Item |
|---|---|
| 165, 192 | QQ Music and KuGou lyrics sources; Thai, Lao, Burmese and Khmer lines wrap |
| 153 | Imported LRC files, a native-look lyrics page for local files, local covers |
| 179, 184 | A scrub never closes the player; lyrics left alone keep the title and scroll |
| 195 | The Live Activity ends when Spotify is swiped away |
| 200 | Music Haptics: None, Generated or Native iOS, by exact ISRC |
| 120, 99 | Accent preset menu with a swatch; custom .ttf and .otf fonts |
| 138 | The now playing bar's glass stays on the card in a Jam |
| 180, 187, 134 | Clean shared links, dead code removed, Mix row fix |

### Before the fork point, or not needed any more

| # | Item |
|---|---|
| 2 | Audio effects on the mod's own engine (`413b2d3`) |
| 3 | Find in playlist |
| 4 | Genius line meanings |
| 5 | Mod > Licenses |
| 7, 9 | Follow and add to library glyphs |
| 8, 10, 11, 12 | 0.22.0 fixes |
| 51, 65 | Update sheet once per release (debug line removed in `0f1d768`) |

## Leave out

| # | Item | Why |
|---|---|---|
| 19, 35, 86 | Certificate offer, Arctic Sign card, usage ping | Third-party signing upsell and upstream telemetry |
| 91, 99, 100, 102, 131 | Plus categories, locks and offer | No paid tier |
| 95 (Account page) | chroma.pw account | No account. The system Settings style is below |
| 129 | "sing limit" | Says nothing buildable |
| 96 | "More visualisations" | One commit in upstream's private repo after 0.23.0-beta. Nothing public says what it adds |
| 107 | The lock screen widget's star switches artwork and lyrics | iOS has no public star command for the lock screen. The Lock screen widget page's choice does the same |

## Still open

- Device checks: Settings, the player footer and the Lyrics Style sheet were checked on an iPhone 15 Pro
  (iOS 27) for beta.1. Still unchecked: Karaoke with a freshly downloaded model, Delay with AirPods, the Live
  Activity options and preview, the font families, Settings at the largest accessibility text size, and
  VoiceOver. Each commit body lists what to check.
