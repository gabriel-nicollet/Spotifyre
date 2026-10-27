# Presets and AutoEq check

Audio effects > Presets and Headphones (`tweak/Sources/Shared/AudioEffects/AudioEffectsPresets.h`) on the Mac,
with no UI: `AudioEffectsPresets.m`, `AutoEq.m`, `AudioEffectsSettings.m` and `Core/SGPrefs.m` as the tweak
compiles them, `shim/Core/SGCore.h` keeping SGCore.h's UIKit half out, and `SGDSPApply` counted rather than
run.

    ./build.sh && build/autoeq-check            # offline
    build/autoeq-check online                   # also AutoEq's real index and files

Offline: INDEX.md lines with parentheses in folders, brackets in names, `&` and `$`, and broken lines; the raw
GraphicEQ addresses made from them; search; a GraphicEQ file applied (switch, nodes, headphone, the master
switch on with it); each built-in preset over the others, keeping the headphone's correction and turning the
master switch on; a saved preset reset and loaded back, Graphic EQ included, the master switch left out of it
and turned on by loading it.

Online: `results/INDEX.md` fetched from raw.githubusercontent.com (8850 headphones in October 2026), cached
and read back, Sennheiser HD 600 by oratory1990 found and its GraphicEQ applied, and a dozen headphones spread
across the index checked to have their GraphicEQ file where the address says. The cached copy is removed after.

The settings live in the check's own defaults domain and are cleared before and after. What it does not cover:
the two pages themselves, which the audio-effects-page harness shows.
