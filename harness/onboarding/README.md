# Onboarding harness

The welcome tour (`App/Onboarding/Tour.m`) and the What's new sheet (`WhatsNew.m`) on the simulator, over a
plain screen standing in for Home. `build.sh` writes CHANGELOG.md's section for the version it builds
(0.20.0 by default, upstream's sections allowed) into the generated notes header, so the sheet has lines;
the tweak's next make writes its own version's back.

    ./build.sh [version]
    xcrun simctl install <udid> build/OnboardingHarness.app
    xcrun simctl launch <udid> com.vitrine.onboardingharness [tour | old | whatsnew | environment] [pick]

`tour` is a first launch on iOS 26 and up: the logo lands, then the page comes in with Redesigned picked.
`old` fakes an OS below 26: Legacy picked, the redesign card untested. `pick` taps the other card three
seconds in, which shows the note under the cards: what Legacy goes without, or below 26 what the redesign
risks. `whatsnew` puts the sheet up instead. `environment` loads a stand-in `EeveeSpotify.dylib` from the
app and runs the install check, which finds it and the harness's own version (1.0, not Spotify's) and says
both in one alert about five seconds in.
