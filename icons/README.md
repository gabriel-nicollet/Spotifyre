# Alternate icons

Each `NAME.png` here becomes an app icon that Appearance > App icon offers. `scripts/pipeline.sh`
scales it for iPhone and iPad and adds it to Spotify's `Info.plist`.

- Square, 1024 × 1024, no transparency.
- `NAME` is letters, digits, `_` and `-`. An `_` shows as a space in the list.

`Vitrine.png` is drawn by `source/reeded-light.html` (the idea is in `source/reeded-light.md`). Open the
page to try other seeds and settings, or render one headless at 1024 × 1024:

    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars \
      --window-size=1024,1024 --virtual-time-budget=60000 --screenshot=icons/Vitrine.png \
      "file://$PWD/icons/source/reeded-light.html?render=1&seed=7"

## Liquid Glass icons (`NAME.icon`)

Each `NAME.icon` is an Icon Composer document (artwork in `Assets/`). `scripts/app-icons.sh` compiles them with
Xcode 26's `actool`, merges their glass stacks into Spotify's `Assets.car` and lists them as `SGAppIcon<Name>`;
iOS 26 and up draws them, and a build without Icon Composer simply goes without. Appearance > App icon lists
them first, in the order `tweak/Sources/Shared/AppIcon/AppIcon.m` gives, and the flat `NAME.png` ones after.
