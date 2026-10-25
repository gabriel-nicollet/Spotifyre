# Spotifyre Flame Icon Integration

This patch adds a smooth, rounded flame silhouette to all nine existing `.icon` bundles and updates `scripts/app-icons.sh` to preserve custom artwork.

## Changed files
- `icons/{Blue,Glass,Green,Lime,Orange,Pink,Purple,Spotify,White}.icon/Assets/Logo.svg` (new)
- `scripts/app-icons.sh` (updated to prefer each bundle's custom SVG)
- Existing `icon.json` files are preserved, including their current tint/color settings.

## Install
1. Apply these files to the root of your Spotifyre working tree, preserving the folder structure.
2. Review the changes with `git diff`.
3. Build using the repository's normal build pipeline on macOS with Xcode 26 / Icon Composer tooling.
4. Confirm the build log lists the alternate icons, install the IPA, then choose a variant in Spotifyre's App icon settings.

## Notes
- The artwork is a single-color vector so the existing Icon Composer JSON tint settings continue to control the variant colors.
- The flame is a plain rounded silhouette (one main tongue, one small side tongue), about 600 px tall and centred in the 1024 px canvas; the bundles' 1.22 layer scale brings it to roughly 70% of the tile.
- This has not been compiled or tested in an iOS IPA in this environment; validate rendering in Icon Composer before distributing.
