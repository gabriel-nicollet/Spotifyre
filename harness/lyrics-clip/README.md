# Lyrics clip harness

`SGLyricsClip.m`, the clips the lock screen shows a line of lyrics in, run on the Mac. It renders a
short line, a long one, a CJK one, a break (the next line only), the last line and an empty clip, each
as a Still and as Animated, over a stand-in cover or the image given. Every file is read back with
AVFoundation and checked: its length (2 s for a still, 4 s for an animated loop), its 3:4 size, H.264,
how many frames it holds (1 or 60), white words in the middle band and none under the clock or the
controls, and the words the same at the end as at the start. It prints how long each clip took to
write. The first frame of each clip is saved next to it as a PNG.

    ./build.sh && build/lyrics-clip [cover.jpg]

The clips land in `build/clips/`.

`motion` renders Moving artwork with lyrics (`SGLyricsClipWriteOverMotion`, `motion.m`) over two stand-ins
it makes, a bright busy flag (720x1280, 30 fps, a Canvas's shape) and a dark field (904x1206, 24 fps, an
Apple Music cover's), and over any videos given: a line with the one before and after, a long line, a
stretch round the video's end, one longer than the video (written whole), a break and no words. Each is
read back and checked: length, the 3:4 cut's size, H.264, frames at up to 30 fps, words in the middle and
nothing white under the clock or the controls, the picture moving, and the preview the same as the first
frame. A video whose frames decode at another size than it states (non-square pixels, made with ffmpeg's
`setsar=4/3`) must not be written and give no preview, so the line falls back to the cover; so must a video
that is gone or cut short. It also checks the artwork ID's ending (`SGLyricsClipLook`): another style or
another video gives another one. It prints each clip's time a frame against the video cut alone (`SGMotionClipShape`) and the
Animated lyrics clip, the contrast of the words with the brightest of the picture behind them, and the
memory used.

    ./build.sh && build/lyrics-clip motion [video.mp4 ...]
    build/lyrics-clip motion one video.mp4    # one line's clip alone, for its memory peak
    build/lyrics-clip motion cut video.mp4    # the video cut alone, to compare

These land in `build/motion/`. AVFoundation's encoder needs the sandbox off.
