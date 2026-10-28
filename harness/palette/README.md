# Palette check

    ./build.sh && build/palette-check

runs `Redesigned/Kit/SGRPalette.m` on the Mac (as Mac Catalyst, for UIKit): a blue cover with a pale border along
its foot, read once by its bottom edge (the player's field) and once by its main color (a playlist, album or
artist page, `mainColor`). The edge has to come out gray and the main color blue. It prints PASS or FAIL; the exit
status is the number of failures.
