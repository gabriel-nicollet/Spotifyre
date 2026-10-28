#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Appearance.h"

// The preset is read off the color stored, so the hooks keep the one key they read and a color set before
// presets existed stays in effect: Apple Music's red reads as Apple Music, any other color as Custom, none
// as Spotify. The custom color is put aside while a preset is in place, so Custom brings it back.
static NSArray<NSString *> *presets(void) {
    return @[@"Spotify", @"Apple Music", @"Custom"];
}

static NSInteger preset(void) {
    NSInteger rgb = SGInt(SGKeyAccent, -1);
    if (rgb < 0 || rgb > 0xFFFFFF) return 0;
    return rgb == SGAppleMusicRed ? 1 : 2;
}

static void choosePreset(NSInteger index) {
    if (preset() == 2) SGSetInt(SGKeyAccentCustom, SGInt(SGKeyAccent, -1));
    NSInteger custom = SGInt(SGKeyAccentCustom, SGSpotifyGreen);
    if (custom < 0 || custom > 0xFFFFFF) custom = SGSpotifyGreen;
    SGSetInt(SGKeyAccent, index == 0 ? -1 : index == 1 ? SGAppleMusicRed : custom);
}

// The native look's rows of the Appearance page (App/Pages.m): the preset from a menu, then the color in
// effect, which opens the picker; a color stored from there is Custom.
NSArray<SGModRow *> *SGNativeAppearanceRows(void) {
    SGModRow *menu = SGMenuRow(@"Accent color preset", presets(), ^NSString *{ return presets()[(NSUInteger)preset()]; },
                               ^(NSInteger index) { choosePreset(index); });
    SGModRow *colour = SGStatActionRow(@"Accent color", nil, ^NSString *{ return [NSString stringWithFormat:@"#%06lX", (long)SGAccentRGB()]; }, ^{
        SGPickColor(@"Accent color", SGAccentRGB(), ^(NSInteger rgb) {
            SGSetInt(SGKeyAccent, rgb);
            SGSetInt(SGKeyAccentCustom, rgb);
        });
    });
    colour.swatch = ^UIColor *{ return SGColorRGB(SGAccentRGB()); };
    return @[
        SGWithSymbol(SGOptionRow(@"AMOLED background", nil, SGKeyAmoled), @"moon"),
        SGWithSymbol(menu, @"paintpalette"),
        SGWithSymbol(colour, @"eyedropper"),
    ];
}
