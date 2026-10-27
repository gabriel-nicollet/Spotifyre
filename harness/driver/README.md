# Phone driver harness

`Diagnostics/Diagnostics.x`'s tree server and `Diagnostics/Driver.m`, compiled as a FLEX build compiles them
(`SG_DRIVER=1`), run in the simulator on a mock app, and `proof.py` drives it through `scripts/phone.py` the
way an agent drives the phone. Simulator apps share the Mac's loopback, so no iproxy; the harness serves on
127.0.0.1:8095 (`PORT=` at build time) so an iproxy to the phone keeps 8085.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/DriverHarness.app
    xcrun simctl launch <udid> com.vitrine.driverharness
    ./proof.py

The mock (`main.m`): a tab bar (Home, Search); on Home a button with a touch-up-inside action, a view with a
tap recognizer, a button whose menu is its primary action, a scroll view and a text field; a now playing bar
under Spotify's bar controller's class name that presents a player under `NPVScrollViewController`'s, with the
down arrow and the ⋯ by Spotify's identifiers and a system menu on the ⋯; a player behind
`SGDiagnosticsPlayer`; and `SGOpenModSettings` pushing a 40-row list. Each reacts with an `SGLog` line, read
back through the driver's `log` and `wait --log`, and `proof.py` prints a `PASS` or `FAIL` line per check:
the button's action, the recognizer, the menu up before the finger lifts, a pick, a scroll, a fling, typing,
a screenshot, the player's open, ⋯, pick and close, seek/pause/play/next, tabs by title and index, Mod
Settings and a row below its fold, and the tree served while a wait runs.
