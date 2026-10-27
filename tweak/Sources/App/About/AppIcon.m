// Mod > App icon: the icon on the home screen, picked from the ones scripts/app-icons.sh put into the IPA
// (icons/*.icon, listed under CFBundleAlternateIcons as SGAppIcon<Name>). iOS keeps the choice itself, so
// UIKit is the source of truth for the current choice; a saved last selection is only a fallback if its
// alternate-icon name is unknown. iOS confirms each change in its own alert. The icons are Liquid Glass
// stacks only, which nothing before iOS 26 draws, so below 26 the row says so. The name under the icon is
// the signature's to set, not the app's.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "About.h"

static NSString *const SGAppIconSelectionKey = @"spotifyglass.appIcon.selection";

// In the order the list shows them: the file in icons/, and the name the list gives it. Spotify is the
// IPA's own icon, iOS's primary one.
static NSArray<NSString *> *iconFiles(void) {
    return @[@"Spotify", @"Glass", @"Green", @"White", @"Pink", @"Blue", @"Purple", @"Orange", @"Lime",
             @"SpotifyreOriginalFlame", @"SpotifyreOriginalFlat",
             @"SpotifyreAmberFlame", @"SpotifyreAmberFlat", @"SpotifyreBlueFlame", @"SpotifyreBlueFlat",
             @"SpotifyrePinkFlame", @"SpotifyrePinkFlat", @"SpotifyrePurpleFlame", @"SpotifyrePurpleFlat"];
}

static NSArray<NSString *> *iconTitles(void) {
    return @[@"Spotify", @"Liquid Glass", @"Green", @"White", @"Pink", @"Blue", @"Purple", @"Orange", @"Lime",
             @"Spotifyre Original · Flame", @"Spotifyre Original · Flat",
             @"Spotifyre Amber · Flame", @"Spotifyre Amber · Flat", @"Spotifyre Blue · Flame", @"Spotifyre Blue · Flat",
             @"Spotifyre Pink · Flame", @"Spotifyre Pink · Flat", @"Spotifyre Purple · Flame", @"Spotifyre Purple · Flat"];
}

static NSString *alternateName(NSString *file) {
    return [file isEqualToString:@"Spotify"] ? nil : [@"SGAppIcon" stringByAppendingString:file];
}

// The icons this build has: one built without Xcode 26 has none but Spotify's.
static NSArray<NSString *> *availableFiles(void) {
    NSDictionary *alternates = NSBundle.mainBundle.infoDictionary[@"CFBundleIcons"][@"CFBundleAlternateIcons"];
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    for (NSString *file in iconFiles())
        if (!alternateName(file) || alternates[alternateName(file)]) [files addObject:file];
    return files;
}

static NSString *currentFile(void) {
    NSArray<NSString *> *available = availableFiles();
    NSString *name = UIApplication.sharedApplication.alternateIconName;
    for (NSString *file in available)
        if ((!name && !alternateName(file)) || [alternateName(file) isEqualToString:name]) return file;
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:SGAppIconSelectionKey];
    if ([available containsObject:saved]) return saved;
    return @"Spotify";
}

static NSString *titleOf(NSString *file) {
    NSUInteger index = [iconFiles() indexOfObject:file];
    return index == NSNotFound ? file : iconTitles()[index];
}

// app-icons.sh draws each at 60 pt @3x with ictool.
static UIImage *preview(NSString *file) {
    NSString *path = [NSBundle.mainBundle pathForResource:file ofType:@"png" inDirectory:@"SGAppIconPreviews"];
    UIImage *image = path ? [UIImage imageWithContentsOfFile:path] : nil;
    return image ? [UIImage imageWithCGImage:image.CGImage scale:3 orientation:UIImageOrientationUp] : nil;
}

// The list stays up after a pick, so one icon after another can be tried; the tick follows what iOS
// reports once it has switched.
@interface SGAppIconPage : SGPage
@end

@implementation SGAppIconPage {
    NSArray<NSString *> *_files;
    UIView *_footer;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"App icon";
    _files = availableFiles();
    _footer = SGNote(@"iOS confirms each change in an alert of its own. The name under the icon is set when the app is signed: rename it in Feather, Sideloadly or whatever signs it.");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.tableFooterView = _footer;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _footer, 16, 24);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_files.count;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"appicon");
    NSString *file = _files[(NSUInteger)path.row];
    SGFillCell(cell, titleOf(file), nil, nil, nil);
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    UIListContentConfiguration *content = [(UIListContentConfiguration *)cell.contentConfiguration copy];
    content.image = preview(file);
    content.imageProperties.maximumSize = CGSizeMake(44, 44);
    content.imageProperties.reservedLayoutSize = CGSizeMake(44, 44);
    content.imageToTextPadding = 14;
    cell.contentConfiguration = content;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if ([file isEqualToString:currentFile()]) {
        UIImageView *tick = SGSymbolView(@"checkmark", 13, UIImageSymbolWeightSemibold, 16);
        tick.tintColor = SGGreen();
        cell.accessoryView = tick;
    }
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    NSString *file = _files[(NSUInteger)path.row];
    // Compare the value iOS actually stores. A stale icon name can make currentFile() fall back
    // to Spotify and used to block the tap needed to switch back to the primary icon.
    NSString *wantedName = alternateName(file);
    NSString *currentName = UIApplication.sharedApplication.alternateIconName;
    if ((wantedName == nil && currentName == nil) || [wantedName isEqualToString:currentName]) return;
    __weak UITableView *weakTable = table;
    [UIApplication.sharedApplication setAlternateIconName:alternateName(file) completionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SGLog(@"app icon: %@ -> %@", file, error ?: @"set");
            if (!error) [NSUserDefaults.standardUserDefaults setObject:file forKey:SGAppIconSelectionKey];
            [weakTable reloadData];
            if (!error) return;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"The icon did not change"
                                                                          message:error.localizedDescription
                                                                   preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [SGTopController() presentViewController:alert animated:YES completion:nil];
        });
    }];
}

@end

SGModRow *SGAppIconRow(void) {
    if (availableFiles().count < 2) return nil;
    if (@available(iOS 26.0, *)) {
        SGModRow *row = SGPageRow(@"App icon", ^UIViewController *{ return [SGAppIconPage new]; });
        row.value = ^NSString *{ return titleOf(currentFile()); };
        return row;
    }
    return SGStatRow(@"App icon", ^NSString *{ return @"Needs iOS 26"; });
}
