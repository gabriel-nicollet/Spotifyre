# Album credits check

    ./build.sh && build/album-credits-check

runs `Redesigned/Album/AlbumCredits.m` on the Mac: which track artist lines an album page in the redesign drops
as repeats of the album's artist, and the cases that keep theirs (another guest, another order, another
separator, a guest with no featured-artist marker, Ann against Anne, a compilation, no header yet). Each line
prints ok or FAIL; the exit status is the number of failures. How a dropped line looks is the album harness's.
