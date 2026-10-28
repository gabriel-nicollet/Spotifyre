// The lyrics' look as stored, its presets and the preview's lines. The page is LyricsLookSettings.m.
#import "LyricsLook.h"

NSNotificationName const SGRLyricsLookDidChangeNotification = @"spotifyglass.redesign.lyricsLookDidChange";

// The sliders' ranges, which a stored look is held to as well.
static const SGRLyricsLook kLeast = {22, 12, 0, 0, 0, 0.1, 0}, kMost = {40, 40, 2, 2, 2, 0.7, 1};

static SGRLyricsLook presets[] = {
    {30, 24, 1, 1, 1, 0.3, 0},          // Apple Music: its 30 pt lines, 24 pt apart
    {36, 28, 1, 1, 1, 0.3, 0},          // Large
    {25, 16, 1, 1, 1, 0.3, 0},          // Compact
    {30, 24, 0, 0, 0, 0.3, 0},          // Calm: every line sharp, and nothing held glows or waves
    {32, 26, 1.4, 1.6, 1.8, 0.3, 0.35}, // Vivid
};

NSArray<NSString *> *SGRLyricsLookPresetNames(void) {
    return @[@"Apple Music", @"Large", @"Compact", @"Calm", @"Vivid"];
}

SGRLyricsLook SGRLyricsLookPreset(NSUInteger index) {
    return presets[MIN(index, sizeof(presets) / sizeof(*presets) - 1)];
}

static CGFloat held(CGFloat value, CGFloat least, CGFloat most) {
    return isfinite(value) ? MAX(least, MIN(most, value)) : least;
}

static CGFloat stored(NSDictionary *look, NSString *name, CGFloat fallback, CGFloat least, CGFloat most) {
    id value = look[name];
    return [value isKindOfClass:NSNumber.class] ? held([value doubleValue], least, most) : fallback;
}

SGRLyricsLook SGRLyricsLookNow(void) {
    SGRLyricsLook look = presets[0];
    NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:SGRKeyLyricsLook];
    if (!saved) {
        // Keep the reader's former Lyrics Style sliders when moving to the consolidated look page.
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSDictionary *legacy = @{
            @"size": @"spotifyglass.redesign.lyricsStyleFontSize",
            @"spacing": @"spotifyglass.redesign.lyricsStyleLineGap",
            @"blur": @"spotifyglass.redesign.lyricsStyleBlur",
            @"opacity": @"spotifyglass.redesign.lyricsStyleDim",
            @"bloom": @"spotifyglass.redesign.lyricsStyleBloom"
        };
        id value = [defaults objectForKey:legacy[@"size"]];
        if ([value isKindOfClass:NSNumber.class]) look.size = held([value doubleValue], kLeast.size, kMost.size);
        value = [defaults objectForKey:legacy[@"spacing"]];
        if ([value isKindOfClass:NSNumber.class]) look.spacing = held([value doubleValue], kLeast.spacing, kMost.spacing);
        value = [defaults objectForKey:legacy[@"blur"]];
        if ([value isKindOfClass:NSNumber.class]) look.blur = held([value doubleValue] / 6.0, kLeast.blur, kMost.blur);
        value = [defaults objectForKey:legacy[@"opacity"]];
        if ([value isKindOfClass:NSNumber.class]) look.opacity = held([value doubleValue], kLeast.opacity, kMost.opacity);
        value = [defaults objectForKey:legacy[@"bloom"]];
        if ([value isKindOfClass:NSNumber.class]) look.bloom = held([value doubleValue] / 100.0, kLeast.bloom, kMost.bloom);
        return look;
    }
    look.size = stored(saved, @"size", look.size, kLeast.size, kMost.size);
    look.spacing = stored(saved, @"spacing", look.spacing, kLeast.spacing, kMost.spacing);
    look.blur = stored(saved, @"blur", look.blur, kLeast.blur, kMost.blur);
    look.glow = stored(saved, @"glow", look.glow, kLeast.glow, kMost.glow);
    look.wave = stored(saved, @"wave", look.wave, kLeast.wave, kMost.wave);
    look.opacity = stored(saved, @"opacity", look.opacity, kLeast.opacity, kMost.opacity);
    look.bloom = stored(saved, @"bloom", look.bloom, kLeast.bloom, kMost.bloom);
    return look;
}

// The lock-screen cover uses the same size as the reader. Weight is not a look setting, so keep it semibold.
CGFloat SGRLyricsStyleFontSize(void) {
    return SGRLyricsLookNow().size;
}

CGFloat SGRLyricsStyleFontWeight(void) {
    return UIFontWeightSemibold;
}

void SGRSetLyricsLook(SGRLyricsLook look, id changer) {
    [NSUserDefaults.standardUserDefaults setObject:@{
        @"size": @(held(look.size, kLeast.size, kMost.size)),
        @"spacing": @(held(look.spacing, kLeast.spacing, kMost.spacing)),
        @"blur": @(held(look.blur, kLeast.blur, kMost.blur)),
        @"glow": @(held(look.glow, kLeast.glow, kMost.glow)),
        @"wave": @(held(look.wave, kLeast.wave, kMost.wave)),
        @"opacity": @(held(look.opacity, kLeast.opacity, kMost.opacity)),
        @"bloom": @(held(look.bloom, kLeast.bloom, kMost.bloom)),
    } forKey:SGRKeyLyricsLook];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsLookDidChangeNotification object:changer];
}

// Equal to the slider's step, so a look slid back onto a preset's values reads as that preset again.
static BOOL same(CGFloat a, CGFloat b) {
    return fabs(a - b) < 0.01;
}

NSInteger SGRLyricsLookPresetIndex(SGRLyricsLook look) {
    for (NSUInteger i = 0; i < sizeof(presets) / sizeof(*presets); i++) {
        SGRLyricsLook preset = presets[i];
        if (same(look.size, preset.size) && same(look.spacing, preset.spacing) && same(look.blur, preset.blur)
            && same(look.glow, preset.glow) && same(look.wave, preset.wave)
            && same(look.opacity, preset.opacity) && same(look.bloom, preset.bloom)) return (NSInteger)i;
    }
    return -1;
}

#pragma mark - the preview's song

// Each word as [text, start, end] in ms; a line runs from its first word's start to its last word's end.
static SGKaraokeLine *sampleLine(NSArray<NSArray *> *timed) {
    NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
    for (NSArray *piece in timed) {
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = piece[0];
        word.start = [piece[1] integerValue];
        word.end = [piece[2] integerValue];
        [words addObject:word];
    }
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = words;
    line.start = words.firstObject.start;
    line.end = words.lastObject.end;
    line.timing = SGKaraokeTimingWords;
    return line;
}

// Words of the mod's own. The second line holds its last word for three seconds, so the glow and the wave
// show on every round.
NSArray<SGKaraokeLine *> *SGRLyricsSampleLines(void) {
    static NSArray<SGKaraokeLine *> *lines;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        lines = @[
            sampleLine(@[@[@"Light", @600, @1000], @[@"comes", @1000, @1400], @[@"over", @1400, @1800], @[@"the", @1800, @2000], @[@"water", @2000, @2900]]),
            sampleLine(@[@[@"hold", @3100, @3500], @[@"on", @3500, @3800], @[@"to", @3800, @4000], @[@"the", @4000, @4200], @[@"night", @4200, @7200]]),
            sampleLine(@[@[@"we", @7500, @7800], @[@"sing", @7800, @8300], @[@"it", @8300, @8500], @[@"louder", @8500, @9500]]),
            sampleLine(@[@[@"all", @9800, @10100], @[@"the", @10100, @10300], @[@"way", @10300, @10700], @[@"home", @10700, @12000]]),
        ];
    });
    return lines;
}

NSInteger SGRLyricsSampleLength(void) {
    return 13500;   // a pause after the last line, then the first again
}
