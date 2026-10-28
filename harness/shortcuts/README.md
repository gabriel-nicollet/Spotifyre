# Shortcuts harness

The shortcut intents of `Shared/LiveActivity/LiveActivityShared.swift`, as the tweak compiles them, performed
for real in the simulator against `observer.m`, a stand-in for `LiveActivity.x`'s `SGShortcut` observer
registered the same way:

- Like with the player not up for three posts: asked again every 250 ms and done on the fourth.
- Karaoke on refused: thrown at once, the message read out as the observer wrote it.
- Sleep timer, Next and Play or pause: each answered on the first post.
- Sleep timer at End of album: posted as `timer:album`, the Live Activity's own action.
- Previous never answered: given up after 32 posts, about 8 s, with "Spotify isn't ready yet".

It checks that the post is made on the main thread and that the reply is a mutable dictionary the
observer can write into, which is how the answer gets back. What Spotify does with each action is not
here: that needs Spotify's player.

    xcrun simctl boot <udid>
    SIM=<udid> harness/shortcuts/build.sh
