// A mock of Spotify's album page under its own class names and accessibility identifiers, built from
// trees/clean/album/03.txt, so Redesigned/Album can be laid out and looked at on the Mac.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>
#import "../download-mock.h"

#pragma mark - Spotify's classes, by name

@interface _TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView : UIView @end
@implementation _TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView @end

@interface _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView : UIView @end
@implementation _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView @end

@interface _TtCO19LegacyUI_ECMCoreKit5Views10HeaderView : UIView @end
@implementation _TtCO19LegacyUI_ECMCoreKit5Views10HeaderView @end

@interface _TtC28EncoreConsumerMobile_BaseKit20HeaderNavigationBar : UIView @end
@implementation _TtC28EncoreConsumerMobile_BaseKit20HeaderNavigationBar @end

// Spotify's draws a CAGradientLayer; whether it is the view's own layer is what the device log settles.
@interface _TtC19LegacyUI_ECMCoreKit12GradientView : UIView @end
@implementation _TtC19LegacyUI_ECMCoreKit12GradientView
+ (Class)layerClass { return CAGradientLayer.class; }
@end

@interface _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView : UIView @end
@implementation _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView @end

@interface _TtC12Element_List18CollectionViewCell : UICollectionViewCell @end
@implementation _TtC12Element_List18CollectionViewCell @end

// The element the cell's content is, which is the only thing that says what a cell holds.
@interface MockRetrievalListStructuredDataView : UIView @end
@implementation MockRetrievalListStructuredDataView @end

@interface MockAlbum_PageImpl20FooterStructuredDataView : UIView @end
@implementation MockAlbum_PageImpl20FooterStructuredDataView @end

@interface MockCondensedButton : UIControl @end
@implementation MockCondensedButton @end

@interface MockEncoreButton : UIControl @end
@implementation MockEncoreButton @end

#pragma mark - building the tree

static UIView *box(UIView *parent, Class cls, CGRect frame, NSString *identifier) {
    UIView *view = [[cls alloc] initWithFrame:frame];
    view.accessibilityIdentifier = identifier;
    [parent addSubview:view];
    return view;
}

static UILabel *label(UIView *parent, CGRect frame, NSString *text, CGFloat size, UIColor *color, NSString *identifier) {
    UIView *encore = box(parent, UIView.class, frame, identifier);
    UILabel *inner = [[UILabel alloc] initWithFrame:encore.bounds];
    inner.text = text;
    inner.font = [UIFont systemFontOfSize:size];
    inner.textColor = color;
    inner.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    inner.accessibilityIdentifier = [identifier stringByAppendingString:@"-internal"];
    [encore addSubview:inner];
    return inner;
}

static UIView *byIdentifier(UIView *root, NSString *identifier) {
    if ([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = byIdentifier(sub, identifier);
        if (found) return found;
    }
    return nil;
}

static UIImage *artwork(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(300, 300)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat components[] = {0.16, 0.34, 0.62, 1, 0.07, 0.10, 0.22, 1};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, NULL, 2);
        CGContextDrawLinearGradient(c, gradient, CGPointZero, CGPointMake(300, 300), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        [[UIColor colorWithWhite:1 alpha:0.30] setFill];
        for (int i = 0; i < 4; i++) {
            [[UIBezierPath bezierPathWithRect:CGRectMake(24 + i * 62, 60 + (i % 2) * 90, 48, 150)] fill];
        }
        // A scanned sleeve: the scanner's pale border along the bottom, which is all the Kit's palette reads.
        [[UIColor colorWithWhite:0.82 alpha:1] setFill];
        UIRectFill(CGRectMake(0, 282, 300, 18));
    }];
}

static UIImage *playGlyph(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(48, 48)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(19, 15)];
        [path addLineToPoint:CGPointMake(33, 24)];
        [path addLineToPoint:CGPointMake(19, 33)];
        [path closePath];
        [UIColor.blackColor setFill];
        [path fill];
    }];
}

// One of the round buttons of the header's action row: the element view Spotify's stack arranges, the
// button inside it at the same size, and a glyph in the button.
static UIView *actionButton(UIView *row, CGRect frame, NSString *identifier, NSString *symbol, NSString *a11y) {
    UIView *element = box(row, UIView.class, frame, nil);
    // Drawn by Lottie, its state in its identifier and in the Encore object behind it (issue #65).
    if ([identifier hasPrefix:@"DownloadButton.Granular."]) {
        mockDownloadButton(element);
        return element;
    }
    if ([identifier isEqualToString:@"Components.UI.AddToButton"]) {
        mockAddToButton(element);
        return element;
    }
    UIView *button = box(element, MockEncoreButton.class, element.bounds, identifier);
    button.accessibilityLabel = a11y;
    UIImageView *glyph = [[UIImageView alloc] initWithFrame:CGRectInset(button.bounds, 12, 12)];
    glyph.image = [UIImage systemImageNamed:symbol];
    glyph.tintColor = UIColor.whiteColor;
    [button addSubview:glyph];
    return element;
}

#pragma mark - the metadata row's cells

@interface SGRMetaSource : NSObject <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, copy) NSArray<NSString *> *items;
@end

@implementation SGRMetaSource

- (NSInteger)collectionView:(UICollectionView *)view numberOfItemsInSection:(NSInteger)section {
    return self.items.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)view cellForItemAtIndexPath:(NSIndexPath *)path {
    UICollectionViewCell *cell = [view dequeueReusableCellWithReuseIdentifier:@"meta" forIndexPath:path];
    for (UIView *old in cell.contentView.subviews) [old removeFromSuperview];
    label(cell.contentView, cell.contentView.bounds, self.items[path.item], 11,
          [UIColor colorWithWhite:0.70 alpha:1], @"Encore.Label");
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)view layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)path {
    CGSize text = [self.items[path.item] sizeWithAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:11]}];
    return CGSizeMake(ceil(text.width), 15.33);
}

@end

// What the redesign's row shows on Play's right: the label of the Kit's last round button, the trailing one.
static UIControl *trailingButton(UIView *root) {
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ([NSStringFromClass(v.class) isEqualToString:@"SGRHeaderInfo"]) {
            UIControl *trailing = nil;
            for (UIView *sub in v.subviews) {
                if ([NSStringFromClass(sub.class) isEqualToString:@"SGRMirrorButton"]) trailing = (UIControl *)sub;
            }
            return trailing;
        }
        [stack addObjectsFromArray:v.subviews];
    }
    return nil;
}

// The trailing button's label and the symbol it draws.
static NSString *trailingState(UIView *root) {
    UIControl *trailing = trailingButton(root);
    UIImageView *glyph = nil;
    for (UIView *sub in trailing.subviews) {
        if ([sub isKindOfClass:UIImageView.class] && !sub.hidden) glyph = (UIImageView *)sub;
    }
    return [NSString stringWithFormat:@"\"%@\" %@ tint %@", trailing.accessibilityLabel, glyph.image, glyph.tintColor];
}

static NSString *trailingLabel(UIView *root) {
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ([NSStringFromClass(v.class) isEqualToString:@"SGRHeaderInfo"]) {
            UIView *trailing = nil;
            for (UIView *sub in v.subviews) {
                if ([NSStringFromClass(sub.class) isEqualToString:@"SGRMirrorButton"]) trailing = sub;
            }
            return trailing && !trailing.hidden ? trailing.accessibilityLabel : @"nothing";
        }
        [stack addObjectsFromArray:v.subviews];
    }
    return @"no header";
}

#pragma mark - the page

@interface SGRHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) SGRMetaSource *meta;
@end

@implementation SGRHarnessDelegate {
    UIView *_titleBlock, *_titleStack, *_actionRow, *_metaCells;
    NSMutableArray<UIView *> *_actionItems;
    NSMutableArray<NSValue *> *_actionFrames;
    NSMutableArray<_TtC12Element_List18CollectionViewCell *> *_footerCells;
    UIView *_listView;
    CGFloat _tracksBottom;
    UIView *_baseCard, *_greyCard;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    CGFloat W = self.window.bounds.size.width, H = self.window.bounds.size.height;

    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
    self.window.rootViewController = root;

    UIView *page = box(root.view, _TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView.class,
                       CGRectMake(0, 0, W, H), @"CreativeWorkPlatform.CreativeWorkTemplateView");

    // Spotify's color wash behind the header, the height of the header at rest.
    UIView *wash = box(page, _TtCO19LegacyUI_ECMCoreKit5Views10HeaderView.class, CGRectMake(0, 0, W, 486.67), nil);
    UIView *gradient = box(wash, _TtC19LegacyUI_ECMCoreKit12GradientView.class, wash.bounds, nil);
    // The color Spotify read off the whole cover, down to its base surface.
    ((CAGradientLayer *)gradient.layer).colors = @[(id)[UIColor colorWithRed:0.29 green:0.22 blue:0.62 alpha:1].CGColor,
                                                   (id)[UIColor colorWithRed:0.07 green:0.07 blue:0.07 alpha:1].CGColor];

    // the tab, the scroll and the stack the header and the list sit in
    UIView *tab = box(page, UIView.class, CGRectMake(0, 0, W, H), @"CreativeWorkPlatform.Tab");
    UIScrollView *scroll = (UIScrollView *)box(tab, UIScrollView.class, CGRectMake(0, 0, W, H), @"PCFFTabLayoutViewController.containerScrollView");
    // Spotify's starts its content at the very top of the page, under the status bar.
    scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    UIStackView *stack = (UIStackView *)box(scroll, UIStackView.class, CGRectMake(0, 0, W, 2200), nil);

    UIView *headerElement = box(stack, UIView.class, CGRectMake(0, 0, W, 486.67), @"CreativeWorkPlatform.Header");
    UIView *header = box(headerElement, UIView.class, headerElement.bounds, @"CreativeWorkPlatform.Components.UI.CreativeWorkHeader");
    UIView *inset = box(header, UIView.class, CGRectMake(0, 78, W, 400.67), nil);
    UIStackView *outer = (UIStackView *)box(inset, UIStackView.class, inset.bounds, nil);

    UIView *topGroup = box(outer, UIView.class, CGRectMake(0, 0, W, 321.33), nil);
    UIStackView *groupStack = (UIStackView *)box(topGroup, UIStackView.class, topGroup.bounds, nil);

    UIView *artRow = box(groupStack, UIView.class, CGRectMake(0, 0, W, 248), nil);
    UIView *coverElement = box(artRow, UIView.class, CGRectMake(round((W - 248) / 2), 0, 248, 248), nil);
    UIView *cover = box(coverElement, UIView.class, coverElement.bounds, @"CreativeWorkPlatform.Components.UI.ArtWorkElement.WithCoverArt");
    UIImageView *coverPicture = [[UIImageView alloc] initWithFrame:cover.bounds];
    coverPicture.image = artwork();
    coverPicture.contentMode = UIViewContentModeScaleAspectFill;
    coverPicture.clipsToBounds = YES;
    coverPicture.accessibilityIdentifier = @"Encore.ImageView";
    [cover addSubview:coverPicture];
    box(groupStack, UIView.class, CGRectMake(0, 256, 0, 0), nil);

    _titleBlock = box(groupStack, UIView.class, CGRectMake(0, 264, 215.33, 57.33), nil);
    _titleStack = box(_titleBlock, UIStackView.class, CGRectMake(16, 0, 183.33, 57.33), nil);
    label(_titleStack, CGRectZero, @"", 17, UIColor.whiteColor, @"CreativeWorkPlatform.Components.UI.PreTitleRow");
    label(_titleStack, CGRectMake(0, 0, 183.33, 25.33), @"Hurry Up Tomorrow", 21, UIColor.whiteColor,
          @"CreativeWorkPlatform.Components.UI.TitleRow");
    UIView *parentElement = box(_titleStack, UIView.class, CGRectMake(0, 33.33, 96, 24), nil);
    UIView *parentRow = box(parentElement, MockEncoreButton.class, parentElement.bounds, @"CreativeWorkPlatform.Components.UI.ParentRow");
    parentRow.accessibilityLabel = @"The Weeknd";
    UIImageView *avatar = (UIImageView *)box(parentRow, UIImageView.class, CGRectMake(0, 0, 24, 24), @"Encore.ImageView");
    avatar.backgroundColor = [UIColor colorWithWhite:0.8 alpha:1];
    avatar.layer.cornerRadius = 12;
    // The artist's picture lands at 1.5 s, after the header has laid out; at 2.2 s the log says where the
    // redesign drew it.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        avatar.image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(48, 48)] imageWithActions:^(UIGraphicsImageRendererContext *c) {
            [UIColor.orangeColor setFill];
            UIRectFill(CGRectMake(0, 0, 48, 48));
        }];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *info = nil;
        for (UIView *v = avatar; v && !info; v = v.superview) {
            for (UIView *sub in v.subviews) {
                if ([NSStringFromClass(sub.class) isEqualToString:@"SGRHeaderInfo"]) info = sub;
            }
        }
        UIView *picture = nil, *name = nil;
        for (UIView *sub in info.subviews) {
            if ([sub isKindOfClass:UIImageView.class] && !sub.hidden && ((UIImageView *)sub).image) picture = sub;
            if ([sub isKindOfClass:UILabel.class] && [((UILabel *)sub).text isEqualToString:@"The Weeknd"]) name = sub;
        }
        NSLog(@"[harness] artist picture: %@, name at %@", picture ? NSStringFromCGRect(picture.frame) : @"none",
              NSStringFromCGRect(name.frame));
    });
    label(parentRow, CGRectMake(32, 4.33, 72, 15.33), @"The Weeknd", 11, UIColor.whiteColor, @"Encore.Label");

    UIView *bottomGroup = box(outer, UIView.class, CGRectMake(0, 329.33, W, 71.33), nil);
    UIStackView *bottomStack = (UIStackView *)box(bottomGroup, UIStackView.class, bottomGroup.bounds, nil);

    UIView *metaWrap = box(bottomStack, UIView.class, CGRectMake(0, 0, W, 15.33), nil);
    UIStackView *metaStack = (UIStackView *)box(metaWrap, UIStackView.class, CGRectMake(16, 0, W - 32, 15.33), nil);
    UIView *metaElement = box(metaStack, UIView.class, metaStack.bounds, nil);
    UIView *metadata = box(metaElement, UIView.class, metaElement.bounds, @"Components.UI.MetadataRow");
    UICollectionViewFlowLayout *flow = [UICollectionViewFlowLayout new];
    flow.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    flow.minimumInteritemSpacing = 4;
    UICollectionView *cells = [[UICollectionView alloc] initWithFrame:metadata.bounds collectionViewLayout:flow];
    cells.backgroundColor = UIColor.clearColor;
    [cells registerClass:UICollectionViewCell.class forCellWithReuseIdentifier:@"meta"];
    self.meta = [SGRMetaSource new];
    self.meta.items = @[@"Album", @"•", @"31. 1. 2025"];
    cells.dataSource = self.meta;
    cells.delegate = self.meta;
    [metadata addSubview:cells];
    _metaCells = cells;

    _actionRow = box(bottomStack, UIStackView.class, CGRectMake(0, 23.33, 206, 48), nil);
    _actionItems = [NSMutableArray array];
    _actionFrames = [NSMutableArray array];
    NSArray *actions = @[@[@"Components.UI.WatchFeedEntityExplorerButton", @"play.rectangle", @"Explore", @0, @4, @62, @40],
                         @[@"Components.UI.AddToButton", @"plus", @"Add", @62, @0, @48, @48],
                         @[@"DownloadButton.Granular.None", @"arrow.down.circle", @"Download", @110, @0, @48, @48],
                         @[@"Components.UI.ContextMenuButton-3OxfaVgvTxUTy7276t7SPU", @"ellipsis", @"More options", @158, @0, @48, @48]];
    // `late` on the launch line: add is not in the row yet, the way an album opened for the first time has it.
    BOOL late = [NSProcessInfo.processInfo.arguments containsObject:@"late"];
    // `download`: an album without add (the row's download is what Play's right shows then), playing the
    // download button's states (download-mock.h).
    BOOL downloads = [NSProcessInfo.processInfo.arguments containsObject:@"download"];
    for (NSArray *action in actions) {
        if ((late || downloads) && [action[0] isEqualToString:@"Components.UI.AddToButton"]) continue;
        CGRect frame = CGRectMake([action[3] doubleValue], [action[4] doubleValue], [action[5] doubleValue], [action[6] doubleValue]);
        [_actionItems addObject:actionButton(_actionRow, frame, action[0], action[1], action[2])];
        [_actionFrames addObject:[NSValue valueWithCGRect:frame]];
    }

    // the track list under the header
    _listView = box(stack, _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView.class,
                    CGRectMake(0, 486.67, W, 700), nil);
    _listView.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
    UIView *collection = box(_listView, UIView.class, _listView.bounds, nil);
    collection.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];

    // The third column: E for a row with Spotify's explicit badge, a label-backed view beside the artist line.
    // The artists the redesign drops are the ones that only repeat the header's The Weeknd; Justice named with
    // no "feat." and Playboi Carti with no mention at all keep theirs.
    NSArray<NSArray<NSString *> *> *tracks = @[@[@"Wake Me Up (feat. Justice)", @"The Weeknd, Justice", @"E"],
                                               @[@"Cry For Me", @"The Weeknd", @""],
                                               @[@"I Can't Fucking Sing", @"The Weeknd", @"E"],
                                               @[@"São Paulo (feat. Anitta)", @"The Weeknd, Anitta", @"E"],
                                               @[@"Until We're Skin & Bones", @"The Weeknd", @""],
                                               @[@"Timeless Justice", @"The Weeknd, Justice", @""],
                                               @[@"Timeless", @"The Weeknd, Playboi Carti", @"E"],
                                               @[@"A Title Long Enough To Run Under The Badge And Beyond", @"The Weeknd", @"E"],
                                               @[@"Baptized In Fear", @"The Weeknd", @""]];
    CGFloat y = 8;
    NSMutableArray<UICollectionViewCell *> *trackCells = [NSMutableArray array];
    for (NSArray<NSString *> *track in tracks) {
        UICollectionViewCell *cell = [[_TtC12Element_List18CollectionViewCell alloc] initWithFrame:CGRectMake(0, y, W, 56)];
        cell.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
        [collection addSubview:cell];
        UIView *content = box(cell.contentView, MockRetrievalListStructuredDataView.class, cell.contentView.bounds, nil);
        UIView *row = box(content, UIView.class, content.bounds, @"Components.UI.RetrievalRowElementUI");
        row.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
        label(row, CGRectMake(16, 8, W - 90, 18), track[0], 13, UIColor.whiteColor, @"EncoreConsumerMobile.View.Granular.Title");
        CGFloat artistX = 16;
        if (track[2].length) {
            UIView *badge = box(row, UIView.class, CGRectMake(16, 31, 13, 13), @"Components.UI.ExplicitIcon");
            badge.backgroundColor = [UIColor colorWithWhite:0.7 alpha:1];
            badge.layer.cornerRadius = 2;
            UILabel *e = [[UILabel alloc] initWithFrame:badge.bounds];
            e.text = @"E";
            e.font = [UIFont boldSystemFontOfSize:9];
            e.textAlignment = NSTextAlignmentCenter;
            e.textColor = UIColor.blackColor;
            [badge addSubview:e];
            artistX = 33;
        }
        label(row, CGRectMake(artistX, 30, W - 74 - artistX, 15.33), track[1], 11, UIColor.whiteColor, @"EncoreConsumerMobile.View.Granular.Subtitle");
        actionButton(row, CGRectMake(W - 64, 4, 48, 48), @"Components.UI.ContextMenuButton-5673WA8EEUSPx1ir26lhGW", @"ellipsis", @"More options");
        [trackCells addObject:cell];
        y += 56;
    }
    _tracksBottom = y;

    // What each row shows once the header has given its artist: the line's alpha, how far the title moved, and
    // where the badge is drawn against the end of the title's text. Then the first row is prepared for reuse and
    // has to come back as Spotify drew it, and laid out again has to be dropped again.
    NSString *(^rowState)(UICollectionViewCell *) = ^NSString *(UICollectionViewCell *cell) {
        [cell layoutIfNeeded];
        UIView *subtitle = byIdentifier(cell, @"EncoreConsumerMobile.View.Granular.Subtitle");
        UIView *badge = byIdentifier(cell, @"Components.UI.ExplicitIcon");
        UILabel *title = (UILabel *)byIdentifier(cell, @"EncoreConsumerMobile.View.Granular.Title-internal");
        UIImageView *drawn = nil;
        for (UIView *v in subtitle.superview.subviews) {
            if ([v isKindOfClass:UIImageView.class]) drawn = (UIImageView *)v;
        }
        NSString *line = subtitle.alpha == 0 ? @"hidden" : @"shown";
        NSString *badgeState = !badge ? @"" : (drawn ? [NSString stringWithFormat:@", badge drawn %.0fpt after the text (original a=%.0f, a11y %d)",
            CGRectGetMinX([drawn.superview convertRect:drawn.frame toView:title]) -
                [title textRectForBounds:title.bounds limitedToNumberOfLines:1].size.width, badge.alpha, drawn.isAccessibilityElement] : @", badge where it was");
        return [NSString stringWithFormat:@"\"%@\": line %@, title moved %.1fpt, title width %.0f%@", title.text, line,
                title.transform.ty, title.bounds.size.width, badgeState];
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (UICollectionViewCell *cell in trackCells) NSLog(@"[harness] row %@", rowState(cell));
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [trackCells[0] prepareForReuse];
        NSLog(@"[harness] reused, before its pass: needs layout %d", trackCells[0].layer.needsLayout);
        UIView *row = trackCells[0].contentView.subviews.firstObject.subviews.firstObject;
        __block CGFloat subtitleAlpha = -1, badgeAlpha = -1;
        __block NSUInteger drawnCount = 0;
        for (UIView *v in row.subviews) {
            if ([v.accessibilityIdentifier isEqualToString:@"EncoreConsumerMobile.View.Granular.Subtitle"]) subtitleAlpha = v.alpha;
            if ([v.accessibilityIdentifier isEqualToString:@"Components.UI.ExplicitIcon"]) badgeAlpha = v.alpha;
            if ([v isKindOfClass:UIImageView.class]) drawnCount++;
        }
        NSLog(@"[harness] reused, restored: line a=%.0f, badge a=%.0f, drawn badges %lu", subtitleAlpha, badgeAlpha,
              (unsigned long)drawnCount);
        NSLog(@"[harness] reused, laid out again: row %@", rowState(trackCells[0]));
    });

    // and under it the footer Spotify sends: the album's own line, the copyright, and the sections the
    // redesign drops -- each with the 16pt spacer Spotify puts between them. Fans also like stands for a
    // section no switch names. They sit in a real collection view, which is what AlbumSections.x keeps what
    // it has read of them on.
    _footerCells = [NSMutableArray array];
    UICollectionView *footerList = [[UICollectionView alloc] initWithFrame:collection.bounds
                                                      collectionViewLayout:[UICollectionViewFlowLayout new]];
    footerList.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    footerList.backgroundColor = UIColor.clearColor;
    footerList.userInteractionEnabled = NO;
    [collection addSubview:footerList];
    NSArray *footer = @[@[@"", @16], @[@"Album.ConsumptionExperience", @15.33], @[@"", @16],
                        @[@"heading:More by The Weeknd", @52.67], @[@"cards", @194.33], @[@"", @16],
                        @[@"heading:Related Music Videos", @52.67], @[@"cards", @235.67], @[@"", @16],
                        @[@"heading:Merch", @52.67], @[@"cards", @197], @[@"", @16],
                        @[@"heading:You might also like", @52.67], @[@"cards", @193.33], @[@"", @16],
                        @[@"heading:Fans also like", @52.67], @[@"cards", @190], @[@"", @16],
                        @[@"Album.Copyright", @60.67]];
    for (NSArray *item in footer) {
        NSString *kind = item[0];
        CGFloat height = [item[1] doubleValue];
        _TtC12Element_List18CollectionViewCell *cell =
            [[_TtC12Element_List18CollectionViewCell alloc] initWithFrame:CGRectMake(0, 0, W, height)];
        [footerList addSubview:cell];
        UIView *content = box(cell.contentView, MockAlbum_PageImpl20FooterStructuredDataView.class, cell.contentView.bounds, nil);
        if ([kind isEqualToString:@"Album.ConsumptionExperience"]) {
            UIView *line = box(content, UIView.class, content.bounds, kind);
            label(line, CGRectMake(16, 0, W - 32, height), @"22 songs • 1hr 24min", 11, UIColor.whiteColor, @"Encore.Label");
        } else if ([kind isEqualToString:@"Album.Copyright"]) {
            UIView *line = box(content, UIView.class, content.bounds, kind);
            UILabel *text = label(line, CGRectMake(16, 0, W - 32, height),
                                  @"© 2025 The Weeknd XO Music ULC, marketed by Republic Records.\n℗ 2025 The Weeknd XO Music ULC, marketed by Republic Records.",
                                  11, UIColor.whiteColor, @"Encore.Label");
            text.numberOfLines = 0;
        } else if ([kind hasPrefix:@"heading:"]) {
            UIView *heading = box(content, UIView.class, content.bounds, @"Components.UI.SectionHeadingHome");
            label(heading, CGRectMake(16, 16, W - 32, 20.67), [kind substringFromIndex:8], 17, UIColor.whiteColor, @"Encore.Label");
        } else if ([kind isEqualToString:@"cards"]) {
            for (int i = 0; i < 3; i++) {
                UIView *card = box(content, UIView.class, CGRectMake(16 + i * 161, 0, 153, height), @"Components.UI.ContentCardAlbum");
                card.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
                card.layer.cornerRadius = 4;
                // A card's caption backing as the device paints it: the base surface, on its layer.
                if (i == 0) card.layer.backgroundColor = [UIColor colorWithRed:0x12 / 255.0 green:0x12 / 255.0 blue:0x12 / 255.0 alpha:1].CGColor;
                if (i == 0 && !_baseCard) _baseCard = card;
                if (i == 1 && !_greyCard) _greyCard = card;
            }
        }
        [_footerCells addObject:cell];
    }

    // An episode page is this same template with cells of its own (device, trees/continuous/1.txt
    // 2026-09-20), and every one of them paints the black the AMOLED made of Spotify's base surface over
    // the field. Put under the tracks, clear of the footer the redesign drops: what is proved here is the
    // paint, not the layout. A card inside one of them is a cell of its own and keeps its own black.
    NSArray *episode = @[@[@"Episode Transcript", @50], @[@"", @24], @[@"", @4.67]];
    CGFloat episodeY = _tracksBottom + 140;
    NSMutableArray<UIView *> *episodePaints = [NSMutableArray array];
    for (NSArray *item in episode) {
        CGFloat height = [item[1] doubleValue];
        UICollectionViewCell *cell = [[_TtC12Element_List18CollectionViewCell alloc]
                                      initWithFrame:CGRectMake(0, episodeY, W, height)];
        [collection addSubview:cell];
        UIView *content = box(cell.contentView, UIView.class, cell.contentView.bounds, nil);
        UIView *paint = box(content, UIView.class, content.bounds, nil);
        paint.backgroundColor = UIColor.blackColor;
        if ([item[0] length]) label(paint, CGRectMake(16, 16, W - 48, 18), item[0], 13, UIColor.whiteColor, @"Encore.Label");
        [episodePaints addObject:paint];
        episodeY += height;
    }
    UICollectionViewCell *carousel = [[_TtC12Element_List18CollectionViewCell alloc]
                                      initWithFrame:CGRectMake(0, episodeY, W, 80)];
    [collection addSubview:carousel];
    UICollectionViewCell *card = [[_TtC12Element_List18CollectionViewCell alloc] initWithFrame:CGRectMake(16, 0, 153, 80)];
    card.backgroundColor = UIColor.blackColor;
    [carousel.contentView addSubview:card];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"[harness] the episode page's paint: %@ %@ %@, and the card inside a cell %@",
              episodePaints[0].backgroundColor ?: @"clear", episodePaints[1].backgroundColor ?: @"clear",
              episodePaints[2].backgroundColor ?: @"clear", card.backgroundColor ?: @"clear");
        // The base-surface album card cleared, the one painted gray left alone.
        NSLog(@"[harness] album cards: base surface a=%.0f, gray a=%.2f",
              CGColorGetAlpha(self->_baseCard.layer.backgroundColor), CGColorGetAlpha(self->_greyCard.layer.backgroundColor));
    });

    // the sticky navigation bar, its gradient hidden until the page scrolls
    UIView *navBar = box(page, _TtC28EncoreConsumerMobile_BaseKit20HeaderNavigationBar.class, CGRectMake(0, 0, W, 118), @"CreativeWorkPlatform.HeaderNavigationBar");
    UIView *navGradient = box(navBar, _TtC19LegacyUI_ECMCoreKit12GradientView.class, navBar.bounds, nil);
    ((CAGradientLayer *)navGradient.layer).colors = @[(id)[UIColor colorWithWhite:0.02 alpha:1].CGColor,
                                                      (id)[UIColor colorWithWhite:0.02 alpha:1].CGColor];
    navGradient.hidden = YES;
    // Scrolled, Spotify shows it by -setHidden:, which is what took a conceal() back.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        navGradient.hidden = NO;
        NSLog(@"[harness] Spotify showed the navigation bar's gradient; mask %@", navGradient.layer.mask ? @"on" : @"off");
    });

    // the two controls Spotify floats over the page, outside the scroll
    UIView *shuffleElement = box(page, UIView.class, CGRectMake(282, 62, 48, 48), nil);
    UIView *shuffle = box(shuffleElement, MockEncoreButton.class, shuffleElement.bounds, @"Components.UI.ShuffleButton");
    shuffle.accessibilityLabel = @"Shuffle tracks";
    mockShuffleGlyph(shuffle);

    UIView *playElement = box(page, UIView.class, CGRectMake(338, 94, 48, 48), nil);
    UIView *playButton = box(playElement, _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView.class, playElement.bounds, @"header-play-button");
    UIControl *condensed = (UIControl *)box(playButton, MockCondensedButton.class, playButton.bounds, nil);
    condensed.accessibilityLabel = @"Play";
    UIImageView *disc = [[UIImageView alloc] initWithFrame:condensed.bounds];
    disc.image = playGlyph();
    disc.backgroundColor = [UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:1];
    disc.layer.cornerRadius = 24;
    disc.clipsToBounds = YES;
    [condensed addSubview:disc];

    [self.window makeKeyAndVisible];
    if (downloads) downloadScript();

    // `addto`: saved from elsewhere at 3 s (the ⋯ sheet, nothing laid out), then Play's right tapped at 7 s.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"addto"]) {
        UIView *rootView = root.view;
        for (NSNumber *when in @[@2, @6.5, @8.5]) {
            at(when.doubleValue, ^{ NSLog(@"[harness] add-to at %@s: %@", when, trailingState(rootView)); });
        }
        at(3, ^{ setAddTo(1); NSLog(@"[harness] add-to: saved from elsewhere"); });
        at(7, ^{ [trailingButton(rootView) sendActionsForControlEvents:UIControlEventTouchUpInside]; });
    }

    // `motion`: Apple Music's animated cover, HARNESS_CANVAS_FILE (any mp4), handed to the hero at 2 s as the
    // catalog would hand it. The clip stays transparent until its first frame is decoded and then fades in;
    // it plays in a window and stops out of one.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"motion"]) {
        UIView *rootView = root.view;
        __block UIView *hero = nil;
        at(2, ^{
            NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:rootView];
            while (queue.count && !hero) {
                UIView *v = queue.firstObject;
                [queue removeObjectAtIndex:0];
                if ([NSStringFromClass(v.class) isEqualToString:@"SGRAlbumHero"]) hero = v;
                [queue addObjectsFromArray:v.subviews];
            }
            const char *path = getenv("HARNESS_CANVAS_FILE");
            NSLog(@"[harness] motion: hero %@, clip %s", hero ? @"found" : @"missing", path ?: "not given");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            if (hero && path) [hero performSelector:NSSelectorFromString(@"showMotion:") withObject:[NSURL fileURLWithPath:@(path)]];
#pragma clang diagnostic pop
            AVPlayerLayer *clip = [hero valueForKey:@"_motion"];
            NSLog(@"[harness] motion: added, ready %d, opacity %.0f, fading %@", clip.readyForDisplay, clip.opacity,
                  [clip animationForKey:@"fade"] ? @"yes" : @"no");
        });
        for (NSNumber *when in @[@2.5, @4]) {
            at(when.doubleValue, ^{
                AVPlayerLayer *clip = [hero valueForKey:@"_motion"];
                NSLog(@"[harness] motion at %@s: ready %d, opacity %.0f, rate %.0f", when, clip.readyForDisplay, clip.opacity, clip.player.rate);
            });
        }
        at(4.5, ^{
            UIView *parent = hero.superview;
            NSUInteger index = [parent.subviews indexOfObject:hero];
            [hero removeFromSuperview];
            AVPlayerLayer *clip = [hero valueForKey:@"_motion"];
            NSLog(@"[harness] motion out of the window: rate %.0f", clip.player.rate);
            [parent insertSubview:hero atIndex:index];
            NSLog(@"[harness] motion back in it: rate %.0f", clip.player.rate);
        });
    }

    // In `late`, add arrives at 2.5 s, after every pass of the header's and the metadata's re-reads: an arranged
    // subview of the row, which lays out the row and nothing above it.
    if (late) {
        UIStackView *row = (UIStackView *)_actionRow;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [row insertArrangedSubview:actionButton(row, CGRectMake(62, 0, 48, 48), @"Components.UI.AddToButton", @"plus", @"Add")
                               atIndex:0];
            NSLog(@"[harness] late: add arrived in the row");
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[harness] late: Play's right shows \"%@\"", trailingLabel(root.view));
        });
    }

    // The list is measured the way the page's collection measures it: every cell is asked how tall it wants
    // to be, which is where AlbumSections.x answers 0 for what the redesign drops, and the answers are
    // stacked. Done a beat after launch, so the header has laid out at least once first.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self measureFooter:W];
        NSLog(@"[harness] hero %@, title stack %@, action row %@",
              NSStringFromCGRect([cover.window convertRect:cover.bounds fromView:cover]),
              NSStringFromCGRect(self->_titleStack.frame), NSStringFromCGRect(self->_actionRow.frame));

        // The ⋯ the redesign pins over the page, outside the scroll, and the artist line under the title,
        // which opens whoever made the album (issues #57 and #56).
        UIView *pinned = nil;
        for (UIView *sub in page.subviews) {
            if ([NSStringFromClass(sub.class) isEqualToString:@"SGRMirrorButton"]) pinned = sub;
        }
        NSLog(@"[harness] pinned more: %@ on the page, hidden=%d",
              pinned ? NSStringFromCGRect(pinned.frame) : @"MISSING", pinned.hidden);
        __block UIView *info = nil, *artist = nil;
        void (^__block walk)(UIView *) = ^(UIView *v) {
            if ([NSStringFromClass(v.class) isEqualToString:@"SGRHeaderInfo"]) info = v;
            for (UIView *sub in v.subviews) walk(sub);
        };
        walk(root.view);
        for (UIView *sub in info.subviews) {
            if ([sub isKindOfClass:UILabel.class] && [((UILabel *)sub).text isEqualToString:@"The Weeknd"]) artist = sub;
        }
        UIView *onName = [info hitTest:CGPointMake(CGRectGetMidX(info.bounds), CGRectGetMidY(artist.frame)) withEvent:nil];
        UIView *beside = [info hitTest:CGPointMake(24, CGRectGetMidY(artist.frame)) withEvent:nil];
        NSLog(@"[harness] artist line: on the name %@, beside it %@", onName ? NSStringFromClass(onName.class) : @"through",
              beside ? NSStringFromClass(beside.class) : @"through");
    });

    // Spotify lays the header out again after the redesign has moved things: the title block, its stack and
    // the action row go back where its own layout puts them, and the redesign has to take them again from
    // its own watch on each.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_titleBlock.frame = CGRectMake(0, 264, 215.33, 57.33);
        self->_titleStack.frame = CGRectMake(16, 0, 183.33, 57.33);
        self->_actionRow.frame = CGRectMake(0, 23.33, 206, 48);
        for (NSUInteger i = 0; i < self->_actionItems.count; i++) {
            self->_actionItems[i].frame = self->_actionFrames[i].CGRectValue;
        }
        [groupStack setNeedsLayout];
        [groupStack layoutIfNeeded];
        [bottomStack setNeedsLayout];
        [bottomStack layoutIfNeeded];
        NSLog(@"[harness] Spotify's own frames put back; the redesign answered with title stack %@, action row %@",
              NSStringFromCGRect(self->_titleStack.frame), NSStringFromCGRect(self->_actionRow.frame));
    });
    return YES;
}

// Every footer cell asked for its height the way the collection's self-sizing asks, then stacked under the
// tracks with whatever each answered.
- (void)measureFooter:(CGFloat)width {
    CGFloat y = _tracksBottom;
    for (_TtC12Element_List18CollectionViewCell *cell in _footerCells) {
        CGFloat natural = cell.bounds.size.height;
        NSIndexPath *path = [NSIndexPath indexPathForItem:[_footerCells indexOfObject:cell] inSection:0];
        UICollectionViewLayoutAttributes *attributes = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:path];
        attributes.frame = CGRectMake(0, y, width, natural);
        UICollectionViewLayoutAttributes *answer = [cell preferredLayoutAttributesFittingAttributes:attributes];
        cell.frame = CGRectMake(0, y, width, answer.size.height);
        [cell layoutIfNeeded];
        y += answer.size.height;
    }
    _listView.frame = CGRectMake(0, 486.67, width, y + 24);
    _listView.subviews.firstObject.frame = _listView.bounds;
    UIScrollView *scroll = (UIScrollView *)_listView.superview.superview;
    if ([scroll isKindOfClass:UIScrollView.class]) scroll.contentSize = CGSizeMake(width, CGRectGetMaxY(_listView.frame));
    NSLog(@"[harness] the footer measured %.0fpt under the tracks", y - _tracksBottom);
}

@end

// Before every %ctor, so the redesign's gate reads on.
__attribute__((constructor(101))) static void sgr_harnessDefaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign"];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGRHarnessDelegate.class));
    }
}
