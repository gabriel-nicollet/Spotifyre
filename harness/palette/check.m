// The field color a page takes from its cover: the main color, not the bottom edge. A blue cover with a
// pale scanner border along its foot, which read by the edge turned the album page gray (device, 2026-09-18).
#import <UIKit/UIKit.h>
#import "Redesigned/Kit/SGRPalette.h"

// SGRTokens.m's accent comes from SGRAccent.x, which this does not compile.
UIColor *SGRAccentColor(void) { return UIColor.greenColor; }

static UIImage *cover(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(300, 300)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor colorWithRed:0.1 green:0.3 blue:0.9 alpha:1] setFill];
        UIRectFill(CGRectMake(0, 0, 300, 300));
        [[UIColor colorWithWhite:0.85 alpha:1] setFill];
        UIRectFill(CGRectMake(0, 255, 300, 45));
    }];
}

int main(void) {
    @autoreleasepool {
        __block int done = 0, fails = 0;
        for (int main = 0; main < 2; main++) {
            SGRPaletteRequest request = {CGSizeZero, NO, YES, NO, main};
            [SGRPalette paletteForImage:cover() request:request completion:^(SGRPalette *palette) {
                CGFloat r, g, b, a;
                [palette.fieldColor getRed:&r green:&g blue:&b alpha:&a];
                BOOL blue = b > r + 0.05 && b > g;
                printf("%s: field %.3f %.3f %.3f, %s\n", main ? "main color" : "bottom edge", r, g, b, blue ? "blue" : "gray");
                if (blue != (BOOL)main) fails++;
                done++;
            }];
        }
        while (done < 2) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        printf(fails ? "FAIL\n" : "PASS\n");
        return fails;
    }
}
