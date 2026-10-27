# Fluid clip harness

`SGFluidClip.m`, the clip the lock screen shows for a song with no Canvas and no animated cover when
Full-screen artwork is Every song, run on the Mac. It renders the loop over a stand-in cover or the image
given, reads the file back with AVFoundation and checks it: 8 s long, 3:4 at the size the tweak asks
for, H.264, 192 frames, the field moving between the start and the middle, no jump where the loop goes
round from the last frame to the first, the cover holding still and sharp in the middle, and the preview
image the same as the first frame. It prints how long the clip took to write.

    ./build.sh && build/fluid-clip [cover.jpg]

The clip lands in `build/clips/`, with its first and middle frames as PNGs.
