// Tab bar harness: TabBar.x and NowPlayingBar.x run for real on a mock of the bottom of Spotify's main
// screen, laid out with the constraints 9.1.78 makes (see the README for the addresses), under Spotify's
// class names, with Spotify's message bar (Offline, Private Session) able to come in under the tab bar.
#import <UIKit/UIKit.h>
#import "Core/SGViewTree.h"

#pragma mark - Spotify's classes, by the names the hooks look for

@interface _TtC23NavigationUI_TabBarImpl10TabBarView : UIView
@end
@implementation _TtC23NavigationUI_TabBarImpl10TabBarView
@end

@interface _TtC23NavigationUI_TabBarImpl17TabBarCompactView : UIView
@end
@implementation _TtC23NavigationUI_TabBarImpl17TabBarCompactView
@end

@interface _TtC23NavigationUI_TabBarImpl21TabBarItemElementView : UIView
@end
@implementation _TtC23NavigationUI_TabBarImpl21TabBarItemElementView
@end

@interface _TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView : UIView
@end
@implementation _TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView
@end

@interface _TtC44LimitedExperienceIndicator_MessageBarRuntime29LimitedExperienceIndicatorBar : UIView
@end
@implementation _TtC44LimitedExperienceIndicator_MessageBarRuntime29LimitedExperienceIndicatorBar
@end

@interface _TtC22NowPlaying_BarPageImplP33_CCC0D2EEA6D4725EECD8965E8C38C86D20TouchPassthroughView : UIView
@end
@implementation _TtC22NowPlaying_BarPageImplP33_CCC0D2EEA6D4725EECD8965E8C38C86D20TouchPassthroughView
@end

// A Jam (`jam`): Spotify's strip, a SwiftUI hosting view of Jam_AttachmentsImpl.JamHatElement 44pt high,
// over the card, both in a view that is painted too, and the bar 44pt taller.
@interface _TtGC7SwiftUI14_UIHostingViewV19Jam_AttachmentsImpl13JamHatElement_ : UIView
@end
@implementation _TtGC7SwiftUI14_UIHostingViewV19Jam_AttachmentsImpl13JamHatElement_
@end

static BOOL sgJam;
static __weak UIView *sgJamStrip;

@interface _TtC18NowPlaying_BarImpl27NowPlayingBarViewController : UIViewController
@end
@implementation _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)loadView {
    self.view = [UIView new];
    UIColor *album = [UIColor colorWithRed:0x18 / 255.0 green:0x14 / 255.0 blue:0x1C / 255.0 alpha:1];
    UIView *host = self.view;
    if (sgJam) {
        host = [[UIView alloc] initWithFrame:self.view.bounds];
        host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        host.backgroundColor = album;
        [self.view addSubview:host];
    }
    // The card, 386x56 at {8,0} with the album color, the artwork, two lines and the progress line
    // (trees/clean/home/01.txt, SPTNowPlayingBar).
    UIView *card = [UIView new];
    card.accessibilityIdentifier = @"SPTNowPlayingBar";
    card.backgroundColor = album;
    card.layer.cornerRadius = 8;
    card.clipsToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:card];
    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [card.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
        sgJam ? [card.heightAnchor constraintEqualToConstant:56] : [card.topAnchor constraintEqualToAnchor:host.topAnchor],
    ]];
    if (sgJam) {
        UIView *strip = [_TtGC7SwiftUI14_UIHostingViewV19Jam_AttachmentsImpl13JamHatElement_ new];
        strip.backgroundColor = [UIColor colorWithRed:0.1 green:0.45 blue:0.3 alpha:1];
        strip.translatesAutoresizingMaskIntoConstraints = NO;
        [host addSubview:strip];
        UILabel *label = [UILabel new];
        label.text = @"Jam by Alex";
        label.font = [UIFont boldSystemFontOfSize:13];
        label.textColor = UIColor.whiteColor;
        label.frame = CGRectMake(16, 12, 200, 20);
        [strip addSubview:label];
        UIButton *more = [UIButton systemButtonWithImage:[UIImage systemImageNamed:@"ellipsis"] target:nil action:nil];
        more.tintColor = UIColor.whiteColor;
        more.translatesAutoresizingMaskIntoConstraints = NO;
        [strip addSubview:more];
        [NSLayoutConstraint activateConstraints:@[
            [strip.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
            [strip.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
            [strip.bottomAnchor constraintEqualToAnchor:card.topAnchor],
            [strip.heightAnchor constraintEqualToConstant:44],
            [more.trailingAnchor constraintEqualToAnchor:strip.trailingAnchor constant:-8],
            [more.centerYAnchor constraintEqualToAnchor:strip.centerYAnchor],
        ]];
        sgJamStrip = strip;
    }
    UIView *art = [[UIView alloc] initWithFrame:CGRectMake(8, 8, 40, 40)];
    art.layer.cornerRadius = 4;
    art.clipsToBounds = YES;
    UIImageView *image = [[UIImageView alloc] initWithFrame:art.bounds];
    image.backgroundColor = [UIColor colorWithRed:0.85 green:0.35 blue:0.55 alpha:1];
    [art addSubview:image];
    [card addSubview:art];
    UILabel *title = [UILabel new], *artist = [UILabel new];
    title.text = @"Stay High";
    title.font = [UIFont boldSystemFontOfSize:13];
    title.textColor = UIColor.whiteColor;
    artist.text = @"Juice WRLD";
    artist.font = [UIFont systemFontOfSize:13];
    artist.textColor = [UIColor colorWithWhite:0.7 alpha:1];
    UIStackView *lines = [[UIStackView alloc] initWithArrangedSubviews:@[title, artist]];
    lines.axis = UILayoutConstraintAxisVertical;
    lines.frame = CGRectMake(56, 8, 200, 40);
    [card addSubview:lines];
    UIButton *play = [UIButton systemButtonWithImage:[UIImage systemImageNamed:@"play.fill"] target:nil action:nil];
    play.tintColor = UIColor.whiteColor;
    play.frame = CGRectMake(330, 12, 32, 32);
    play.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [card addSubview:play];
    UIView *progress = [[UIView alloc] initWithFrame:CGRectMake(8, 54, 370, 2)];
    progress.backgroundColor = UIColor.whiteColor;
    [card addSubview:progress];
}
@end

@interface _TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController : UIViewController
@end
@implementation _TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    UIViewController *bar = [_TtC18NowPlaying_BarImpl27NowPlayingBarViewController new];
    [self addChildViewController:bar];
    bar.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar.view];
    [NSLayoutConstraint activateConstraints:@[
        [bar.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [bar.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [bar.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [bar.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    [bar didMoveToParentViewController:self];
}
@end

// A page on the tab's stack: a list, inset the way Spotify's pages are, by the safe area it inherits.
@interface SGHarnessPage : UITableViewController
@end
@implementation SGHarnessPage
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = UIColor.blackColor;
    self.tableView.rowHeight = 48;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"row"];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 30; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:path];
    cell.backgroundColor = path.row == 29 ? [UIColor colorWithRed:0.1 green:0.3 blue:0.6 alpha:1] : UIColor.blackColor;
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.textLabel.text = path.row == 29 ? @"Last row of the list" : [NSString stringWithFormat:@"Row %ld", (long)path.row + 1];
    return cell;
}
@end

// NavigationUI_TabBarImpl.TabBarContainerImpl in a compact width, as its viewDidLoad (0x1008409a8) and
// its size class pass (0x106fabb7c) lay it out: a guide from 49 pt above the safe area's bottom to the
// view's bottom, a stack as tall as the guide on the view's bottom, the tab bar as tall as the stack.
// The page gets 49 pt more safe area on top of what the container has (0x10707bde4).
@interface _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl : UIViewController
@property (nonatomic, strong) UILayoutGuide *compactGuide;
@property (nonatomic, strong) UIView *bar;
@end
@implementation _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl
- (UILayoutGuide *)compactTabBarHeightLayoutGuide { return self.compactGuide; }
- (UIView *)tabBarView { return self.bar; }
- (void)setSelectedViewController:(UIViewController *)controller {}

// A tap on a mock item does what Spotify's does to the bar: its label goes white and the others gray.
+ (void)tapped:(UITapGestureRecognizer *)tap {
    for (UIView *item in tap.view.superview.subviews) {
        for (UIView *sub in item.subviews) {
            if ([sub isKindOfClass:UILabel.class]) ((UILabel *)sub).textColor = item == tap.view ? UIColor.whiteColor : [UIColor colorWithWhite:0xB3 / 255.0 alpha:1];
        }
    }
    for (UIView *v = tap.view; v; v = v.superview) [v setNeedsLayout];
}

static UIView *item(Class cls, NSString *title, NSString *symbol, BOOL active) {
    UIView *item = [cls new];
    [item addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl.class action:@selector(tapped:)]];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    icon.tintColor = UIColor.whiteColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.frame = CGRectMake(0, 5.67, 24, 24);
    icon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    UILabel *label = [UILabel new];
    label.text = title;
    label.font = [UIFont systemFontOfSize:10];
    label.textColor = active ? UIColor.whiteColor : [UIColor colorWithWhite:0xB3 / 255.0 alpha:1];
    label.textAlignment = NSTextAlignmentCenter;
    label.frame = CGRectMake(0, 35, 100, 14);
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [item addSubview:icon];
    [item addSubview:label];
    return item;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *view = self.view;
    self.compactGuide = [UILayoutGuide new];
    [view addLayoutGuide:self.compactGuide];

    SGHarnessPage *page = [SGHarnessPage new];
    [self addChildViewController:page];
    page.view.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:page.view];
    [page didMoveToParentViewController:self];
    page.additionalSafeAreaInsets = UIEdgeInsetsMake(0, 0, 49, 0);

    UIView *stack = [UIView new];
    stack.accessibilityIdentifier = @"TabBarContainer.stackView";
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:stack];
    self.bar = [_TtC23NavigationUI_TabBarImpl10TabBarView new];
    self.bar.accessibilityIdentifier = @"elements-tabs-view-identifier";
    self.bar.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addSubview:self.bar];
    UIView *compact = [_TtC23NavigationUI_TabBarImpl17TabBarCompactView new];
    compact.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bar addSubview:compact];
    // `five` adds a fifth tab, `long` gives two tabs long names, as tabs of the user's own can have.
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    BOOL longNames = [args containsObject:@"long"];
    NSMutableArray<UIView *> *tabs = [NSMutableArray arrayWithArray:@[
        item(_TtC23NavigationUI_TabBarImpl21TabBarItemElementView.class, @"Home", @"house.fill", YES),
        item(_TtC23NavigationUI_TabBarImpl21TabBarItemElementView.class, @"Search", @"magnifyingglass", NO),
        item(_TtC23NavigationUI_TabBarImpl21TabBarItemElementView.class, longNames ? @"Your Library and Downloads" : @"Your Library", @"books.vertical", NO),
        item(_TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView.class, @"Create", @"plus", NO),
    ]];
    if ([args containsObject:@"five"]) {
        [tabs addObject:item(_TtC23NavigationUI_TabBarImpl21TabBarItemElementView.class, longNames ? @"Discover Weekly" : @"Liked Songs", @"heart", NO)];
    }
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:tabs];
    row.distribution = UIStackViewDistributionFillEqually;
    row.accessibilityIdentifier = @"tabs-container-view-identifier";
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [compact addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [page.view.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [page.view.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [page.view.topAnchor constraintEqualToAnchor:view.topAnchor],
        [page.view.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [self.compactGuide.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.bottomAnchor constant:-49],
        [self.compactGuide.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [stack.heightAnchor constraintEqualToAnchor:self.compactGuide.heightAnchor],
        [self.bar.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor],
        [self.bar.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor],
        [self.bar.bottomAnchor constraintEqualToAnchor:stack.bottomAnchor],
        [self.bar.heightAnchor constraintEqualToAnchor:stack.heightAnchor],
        [compact.leadingAnchor constraintEqualToAnchor:self.bar.leadingAnchor],
        [compact.trailingAnchor constraintEqualToAnchor:self.bar.trailingAnchor],
        [compact.topAnchor constraintEqualToAnchor:self.bar.topAnchor],
        [compact.bottomAnchor constraintEqualToAnchor:self.bar.bottomAnchor],
        [row.leadingAnchor constraintEqualToAnchor:compact.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:compact.trailingAnchor],
        [row.topAnchor constraintEqualToAnchor:compact.topAnchor],
        [row.heightAnchor constraintEqualToConstant:49],
    ]];
}
@end

#pragma mark - the chrome

// ClientChrome_ChromeContainerKit.ClientChromeViewController in a compact width: the primary content
// (the tab bar container) above the bottom attachment, which is Spotify's message bar, and the
// floating chrome (the now playing bar's page) standing on MainUIContainer's bottom anchor, the top of
// the tab bar container's compact height guide (0x100ae0178).
@interface SGHarnessChrome : UIViewController
@property (nonatomic, strong) _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl *tabs;
@property (nonatomic, strong) UIView *banner;
@property (nonatomic, strong) NSLayoutConstraint *bannerHeight;
@property (nonatomic, strong) UIView *npb;
@property (nonatomic, strong) NSLayoutConstraint *npbHeight;
@end

@implementation SGHarnessChrome

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *view = self.view;
    view.backgroundColor = UIColor.blackColor;

    self.tabs = [_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl new];
    [self addChildViewController:self.tabs];
    UIView *primary = self.tabs.view;
    primary.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:primary];
    [self.tabs didMoveToParentViewController:self];

    // LimitedExperienceIndicatorBar: its height is its message plus the safe area it pads its label by
    // (barHeightConstraint, backgroundContainerBottomPaddingConstraint, lastSafeAreaBottomInset).
    self.banner = [_TtC44LimitedExperienceIndicator_MessageBarRuntime29LimitedExperienceIndicatorBar new];
    self.banner.accessibilityIdentifier = @"LimitedExperienceIndicatorBar";
    self.banner.backgroundColor = UIColor.blackColor;
    self.banner.clipsToBounds = YES;
    self.banner.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:self.banner];
    UILabel *message = [UILabel new];
    message.text = @"Private Session";
    message.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    message.textColor = UIColor.whiteColor;
    message.translatesAutoresizingMaskIntoConstraints = NO;
    [self.banner addSubview:message];
    self.bannerHeight = [self.banner.heightAnchor constraintEqualToConstant:0];

    UIView *npb = [_TtC22NowPlaying_BarPageImplP33_CCC0D2EEA6D4725EECD8965E8C38C86D20TouchPassthroughView new];
    npb.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:npb];
    self.npb = npb;
    UIViewController *content = [_TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController new];
    [self addChildViewController:content];
    content.view.translatesAutoresizingMaskIntoConstraints = NO;
    [npb addSubview:content.view];
    [content didMoveToParentViewController:self];

    [NSLayoutConstraint activateConstraints:@[
        [primary.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [primary.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [primary.topAnchor constraintEqualToAnchor:view.topAnchor],
        [primary.bottomAnchor constraintEqualToAnchor:self.banner.topAnchor],
        [self.banner.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [self.banner.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [self.banner.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        self.bannerHeight,
        [message.centerXAnchor constraintEqualToAnchor:self.banner.centerXAnchor],
        [message.bottomAnchor constraintEqualToAnchor:self.banner.safeAreaLayoutGuide.bottomAnchor constant:-4],
        [npb.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [npb.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [npb.bottomAnchor constraintEqualToAnchor:self.tabs.compactTabBarHeightLayoutGuide.topAnchor],
        self.npbHeight = [npb.heightAnchor constraintEqualToConstant:sgJam ? 108 : 64],
        // CompactNowPlayingViewController: the content 8 pt above its own bottom (0x105345190).
        [content.view.leadingAnchor constraintEqualToAnchor:npb.leadingAnchor],
        [content.view.trailingAnchor constraintEqualToAnchor:npb.trailingAnchor],
        [content.view.topAnchor constraintEqualToAnchor:npb.topAnchor],
        [content.view.bottomAnchor constraintEqualToAnchor:npb.bottomAnchor constant:-8],
    ]];

    // The now playing bar's share of the pages' inset, which Spotify adds on its own path; here a
    // stand-in on the page, so the list's end shows where Spotify thinks the bars begin.
    UIViewController *page = self.tabs.childViewControllers.firstObject;
    UIEdgeInsets inset = page.additionalSafeAreaInsets;
    inset.bottom += 64;
    page.additionalSafeAreaInsets = inset;
}

- (CGFloat)bannerTarget {
    return 22 + self.view.safeAreaInsets.bottom;
}

- (void)setBanner:(BOOL)shown animated:(BOOL)animated {
    self.bannerHeight.constant = shown ? [self bannerTarget] : 0;
    if (!animated) {
        [self.view layoutIfNeeded];
        return;
    }
    [UIView animateWithDuration:0.35 animations:^{ [self.view layoutIfNeeded]; }];
}

@end

#pragma mark - what the harness measures

extern CGRect SGRNowPlayingCardFrameIn(UIView *host, CGFloat *radius);
extern void SGRSetTabBarMinimized(BOOL minimized, BOOL animated);
extern BOOL SGRTabBarMinimized(void);
// touch.m: a finger's touches, through UIKit's own recognizers.
extern void SGHarnessTap(UIWindow *window, CGPoint point);
extern void SGHarnessDrag(UIWindow *window, CGPoint from, CGPoint to, NSTimeInterval seconds);

static UIView *platterIn(UIView *root) {
    // UIKit._UITabBarItemPlatterView on iOS 27; BarTransition.x looks for the same suffix.
    if ([NSStringFromClass(root.class) hasSuffix:@"PlatterView"]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = platterIn(sub);
        if (found) return found;
    }
    return nil;
}

static UITabBar *systemBarIn(UIView *root) {
    if ([root isKindOfClass:UITabBar.class]) return (UITabBar *)root;
    for (UIView *sub in root.subviews) {
        UITabBar *found = systemBarIn(sub);
        if (found) return found;
    }
    return nil;
}

static NSArray<UITabBar *> *systemBarsIn(UIView *root) {
    NSMutableArray<UITabBar *> *bars = [NSMutableArray array];
    if ([root isKindOfClass:UITabBar.class]) [bars addObject:(UITabBar *)root];
    else for (UIView *sub in root.subviews) [bars addObjectsFromArray:systemBarsIn(sub)];
    return bars;
}

extern __weak UIView *sgHarnessLitTab;

// The item of the stock row named `title`.
static UIView *stockItem(SGHarnessChrome *chrome, NSString *title) {
    for (UIView *item in SGRowIn(chrome.tabs.bar).arrangedSubviews) {
        for (UIView *sub in item.subviews) {
            if ([sub isKindOfClass:UILabel.class] && [((UILabel *)sub).text isEqualToString:title]) return item;
        }
    }
    return nil;
}

// A tab picked on whichever system bar shows it, the calls a finger ends in.
static void pick(SGHarnessChrome *chrome, NSString *title) {
    for (UITabBar *bar in systemBarsIn(chrome.tabs.bar)) {
        for (UITabBarItem *item in bar.items) {
            if (![item.title isEqualToString:title]) continue;
            bar.selectedItem = item;
            [bar.delegate tabBar:bar didSelectItem:item];
        }
    }
}

static void reportSelection(SGHarnessChrome *chrome, NSString *moment) {
    NSMutableString *out = [NSMutableString stringWithFormat:@"[harness] %@ selection", moment];
    for (UITabBar *bar in systemBarsIn(chrome.tabs.bar)) {
        [out appendFormat:@" | bar%@ %@: %@", bar.hidden ? @" (hidden)" : @"", [bar.items valueForKey:@"title"], bar.selectedItem.title ?: @"none"];
    }
    NSLog(@"%@", [out stringByReplacingOccurrencesOfString:@"\n" withString:@" "]);
}

static void report(SGHarnessChrome *chrome, NSString *moment) {
    UIWindow *window = chrome.view.window;
    UIView *stock = chrome.tabs.bar;
    UITabBar *system = systemBarIn(stock);
    UIView *platter = platterIn(system);
    CGRect stockFrame = [stock convertRect:stock.bounds toView:window];
    CGRect systemFrame = system ? [system convertRect:system.bounds toView:window] : CGRectNull;
    CGRect platterFrame = platter ? [platter convertRect:platter.bounds toView:window] : CGRectNull;
    CGRect card = SGRNowPlayingCardFrameIn(window, NULL);
    CGRect banner = [chrome.banner convertRect:chrome.banner.bounds toView:window];
    UITableView *list = (UITableView *)chrome.tabs.childViewControllers.firstObject.view;
    CGFloat listEnd = CGRectGetMaxY([list convertRect:list.bounds toView:window]) - list.adjustedContentInset.bottom;
    NSLog(@"[harness] %@ screen %.0fx%.0f safe-bottom %.0f | banner %@ | stock bar %@ | system bar %@ | platter %@ | card %@ | "
          @"gap card-to-platter %.1f | container extra inset %.0f | list ends at %.0f (card top %.0f)",
          moment, window.bounds.size.width, window.bounds.size.height, window.safeAreaInsets.bottom,
          NSStringFromCGRect(banner), NSStringFromCGRect(stockFrame), NSStringFromCGRect(systemFrame), NSStringFromCGRect(platterFrame),
          NSStringFromCGRect(card), CGRectGetMinY(platterFrame) - CGRectGetMaxY(card), chrome.tabs.additionalSafeAreaInsets.bottom,
          listEnd, CGRectGetMinY(card));
    // The glass panes of the now playing bar, the card's and in a Jam the strip's, and the strip itself.
    UIView *container = chrome.npb.subviews.firstObject;
    for (UIView *sub in container.subviews) {
        if (![sub isKindOfClass:UIVisualEffectView.class]) continue;
        NSLog(@"[harness] %@ bar pane %@ %@", moment, NSStringFromCGRect([sub convertRect:sub.bounds toView:window]),
              ((UIVisualEffectView *)sub).effect ? @"shown" : @"no effect");
    }
    UIView *strip = sgJamStrip;
    if (strip.window) NSLog(@"[harness] %@ strip %@", moment, NSStringFromCGRect([strip convertRect:strip.bounds toView:window]));
    // Every glass platter on the bar: with `split`, the main bar's and the split bar's.
    NSMutableString *platters = [NSMutableString stringWithFormat:@"[harness] %@ platters", moment];
    NSMutableArray<UIView *> *found = [NSMutableArray array];
    NSMutableArray<UIView *> *walk = [NSMutableArray arrayWithObject:stock];
    while (walk.count) {
        UIView *v = walk.firstObject;
        [walk removeObjectAtIndex:0];
        if ([NSStringFromClass(v.class) hasSuffix:@"PlatterView"]) [found addObject:v];
        else [walk addObjectsFromArray:v.subviews];
    }
    for (UIView *v in found) [platters appendFormat:@" %@ %@", NSStringFromClass(v.class), NSStringFromCGRect([v convertRect:v.bounds toView:window])];
    NSLog(@"%@", platters);
    // What a finger at the card's middle lands on, and the fade under the bars.
    if (!CGRectIsNull(card)) {
        UIView *hit = [window hitTest:CGPointMake(CGRectGetMidX(card), CGRectGetMidY(card)) withEvent:nil];
        NSLog(@"[harness] %@ touch at the card's middle lands on %@, in the now playing bar: %d", moment, NSStringFromClass(hit.class), [hit isDescendantOfView:chrome.npb]);
    }
    for (UIView *v in stock.subviews) {
        if ([NSStringFromClass(v.class) isEqualToString:@"SGRBarFade"]) NSLog(@"[harness] %@ fade %@", moment, NSStringFromCGRect([v convertRect:v.bounds toView:window]));
    }
}

// Every title the glass bars show, and whether UIKit cut it short: the width its text needs at the
// smallest size the label may shrink to, against the width it was given.
static void reportNames(SGHarnessChrome *chrome, NSString *moment) {
    NSMutableString *out = [NSMutableString stringWithFormat:@"[harness] %@ names", moment];
    NSUInteger cut = 0;
    for (UITabBar *bar in systemBarsIn(chrome.tabs.bar)) {
        if (bar.hidden) continue;
        [out appendFormat:@" | bar %.0f wide:", bar.bounds.size.width];
        NSMutableArray<UIView *> *walk = [NSMutableArray arrayWithObject:bar];
        while (walk.count) {
            UIView *v = walk.firstObject;
            [walk removeObjectAtIndex:0];
            [walk addObjectsFromArray:v.subviews];
            if (![v isKindOfClass:UILabel.class] || !v.window) continue;
            BOOL shown = YES;
            for (UIView *up = v; up && up != bar; up = up.superview) shown &= !up.hidden && up.alpha > 0.01;
            if (!shown) continue;
            UILabel *label = (UILabel *)v;
            if (!label.text.length) continue;
            CGFloat need = [label.text sizeWithAttributes:@{NSFontAttributeName: label.font}].width;
            CGFloat scale = label.adjustsFontSizeToFitWidth && label.minimumScaleFactor > 0 ? label.minimumScaleFactor : 1;
            BOOL isCut = need * scale > label.bounds.size.width + 1;
            cut += isCut;
            if ([NSProcessInfo.processInfo.arguments containsObject:@"tree"]) {
                NSMutableString *chain = [NSMutableString string];
                for (UIView *up = label; up && up != bar; up = up.superview) [chain appendFormat:@" < %@%@", NSStringFromClass(up.class), NSStringFromCGRect(up.frame)];
                NSLog(@"[harness] %@ label%@", moment, chain);
            }
            [out appendFormat:@" \"%@\" %.0f/%.0f@%.1fpt%@", label.text, label.bounds.size.width, ceil(need), label.font.pointSize, isCut ? @" CUT" : @""];
        }
    }
    [out appendFormat:@" | %lu cut", (unsigned long)cut];
    NSLog(@"%@", out);
}

// Whether the bar and the card agree: minimized, the platter is the 62 pt circle 21 pt in and the card is in
// its row; expanded, the platter is the whole bar's and the card stands above it. With what the screen shows
// (the presentation layers) and how many animations are still on the bar, its items and the card.
static void check(SGHarnessChrome *chrome, NSString *moment) {
    UIWindow *window = chrome.view.window;
    UITabBar *bar = systemBarIn(chrome.tabs.bar);
    UIView *platter = platterIn(bar);
    CGRect circle = [platter convertRect:platter.bounds toView:window];
    CGRect card = SGRNowPlayingCardFrameIn(window, NULL);
    BOOL minimized = SGRTabBarMinimized();
    BOOL leads = fabs(circle.size.width - 62) < 1 && fabs(circle.origin.x - 21) < 1;
    BOOL docked = CGRectGetMinY(card) > CGRectGetMinY(circle) - 1;
    UIView *moved = chrome.npb.subviews.firstObject;
    CALayer *shown = platter.layer.presentationLayer, *shownCard = moved.layer.presentationLayer;
    CGRect shownCircle = shown ? [shown convertRect:shown.bounds toLayer:window.layer] : CGRectNull;
    __block NSUInteger running = 0;
    SGForEachView(bar, ^(UIView *v) { running += v.layer.animationKeys.count; });
    SGForEachView(moved, ^(UIView *v) { running += v.layer.animationKeys.count; });
    BOOL inStep = minimized == leads && minimized == docked;
    NSLog(@"[harness] %@ check: %@ | circle %@ (shown %@) | card %@ (shown moved %.0f) | %lu animations | %@", moment,
          minimized ? @"minimized" : @"expanded", NSStringFromCGRect(circle), NSStringFromCGRect(shownCircle), NSStringFromCGRect(card),
          shownCard ? shownCard.transform.m42 : 0, (unsigned long)running, inStep ? @"IN STEP" : @"OUT OF STEP");
}

// The list from its top, `drag` points up (a scroll down) or down (a scroll back up), let go moving.
static void fling(SGHarnessChrome *chrome, CGFloat drag) {
    UIWindow *window = chrome.view.window;
    CGFloat from = drag > 0 ? 600 : 300;
    SGHarnessDrag(window, CGPointMake(200, from), CGPointMake(200, from - drag), 0.12);
}

// What the screen shows of a view: its presentation layer's frame in the window's.
static CGRect shownFrame(UIView *view, UIWindow *window) {
    if (!view.window) return CGRectNull;
    CALayer *layer = view.layer.presentationLayer ?: view.layer, *top = window.layer.presentationLayer ?: window.layer;
    return [layer convertRect:layer.bounds toLayer:top];
}

static UIView *firstOf(UIView *root, BOOL (^match)(UIView *)) {
    if (match(root)) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = firstOf(sub, match);
        if (found) return found;
    }
    return nil;
}

// `motion`: the presentation frames of what moves, sampled every frame across a stretch: the main bar's platter, its
// leading glyph, the split bar's platter and the card's glass. Each stretch logs the largest change from one frame to
// the next (x, y, width or height), when it was, and how many times the view under watch was a new one. A spring
// moves these some 20 pt a frame at most; more is a reversal snapping to the old target, or a view made anew
// somewhere else.
static NSString *const kWatched[4] = {@"platter", @"glyph", @"split platter", @"card"};

@interface SGHarnessSampler : NSObject {
@public
    CGRect last[4];
    CGFloat worst[4];
    NSTimeInterval worstAt[4];
    NSUInteger replaced[4];
}
@property (nonatomic, weak) SGHarnessChrome *chrome;
@property (nonatomic, copy) NSString *moment;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) NSTimeInterval start, lastTick;
@property (nonatomic) NSUInteger frames;
@property (nonatomic, strong) NSMutableArray *views;
@end

@implementation SGHarnessSampler

- (NSArray *)watched {
    NSArray<UITabBar *> *bars = systemBarsIn(self.chrome.tabs.bar);
    UITabBar *main = bars.firstObject, *apart = bars.count > 1 && !bars[1].hidden ? bars[1] : nil;
    UIWindow *window = self.chrome.view.window;
    __block UIView *glyph = nil;
    __block CGFloat leftmost = CGFLOAT_MAX;
    SGForEachView(main, ^(UIView *v) {
        if (![v isKindOfClass:UIImageView.class] || !((UIImageView *)v).image || v.bounds.size.width < 10 || v.bounds.size.width > 40) return;
        for (UIView *up = v; up && up != main; up = up.superview) if (up.hidden || up.alpha < 0.01) return;
        CGFloat x = CGRectGetMinX(shownFrame(v, window));
        if (x < leftmost) { leftmost = x; glyph = v; }
    });
    UIView *card = firstOf(self.chrome.npb.subviews.firstObject, ^BOOL(UIView *v) {
        return [v isKindOfClass:UIVisualEffectView.class] && ((UIVisualEffectView *)v).effect && v.bounds.size.height > 40;
    });
    return @[platterIn(main) ?: NSNull.null, glyph ?: NSNull.null, (apart ? platterIn(apart) : nil) ?: NSNull.null, card ?: NSNull.null];
}

- (void)begin:(NSString *)moment {
    self.moment = moment;
    for (int i = 0; i < 4; i++) { last[i] = CGRectNull; worst[i] = 0; replaced[i] = 0; }
    self.views = [NSMutableArray arrayWithArray:@[NSNull.null, NSNull.null, NSNull.null, NSNull.null]];
    self.frames = 0;
    self.lastTick = 0;
    self.start = CACurrentMediaTime();
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    self.link.preferredFrameRateRange = CAFrameRateRangeMake(60, 60, 60);
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)tick {
    NSArray *now = [self watched];
    UIWindow *window = self.chrome.view.window;
    self.frames++;
    // A frame the simulator skipped counts as that many: the step is per 1/60 s.
    NSTimeInterval time = CACurrentMediaTime();
    CGFloat elapsed = self.lastTick > 0 ? MAX(1, round((time - self.lastTick) * 60)) : 1;
    self.lastTick = time;
    NSMutableString *line = [NSMutableString stringWithFormat:@"[harness] %@ %.3f", self.moment, time - self.start];
    for (int i = 0; i < 4; i++) {
        UIView *v = now[i] == NSNull.null ? nil : now[i];
        CGRect frame = v ? shownFrame(v, window) : CGRectNull;
        if (v && self.views[i] != NSNull.null && self.views[i] != v) replaced[i]++;
        self.views[i] = v ?: NSNull.null;
        if (!CGRectIsNull(frame) && !CGRectIsNull(last[i])) {
            CGFloat step = MAX(MAX(fabs(frame.origin.x - last[i].origin.x), fabs(frame.origin.y - last[i].origin.y)),
                               MAX(fabs(frame.size.width - last[i].size.width), fabs(frame.size.height - last[i].size.height))) / elapsed;
            if (step > worst[i]) { worst[i] = step; worstAt[i] = time - self.start; }
        }
        last[i] = frame;
        if (!CGRectIsNull(frame)) [line appendFormat:@" | %@ x %.1f y %.1f w %.1f", kWatched[i], frame.origin.x, frame.origin.y, frame.size.width];
    }
    // `timeline` logs every sample.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"timeline"]) NSLog(@"%@", line);
}

- (void)end {
    [self.link invalidate];
    NSMutableString *out = [NSMutableString stringWithFormat:@"[harness] %@ motion over %lu frames:", self.moment, (unsigned long)self.frames];
    for (int i = 0; i < 4; i++) {
        if (CGRectIsNull(last[i]) && !worst[i]) continue;
        [out appendFormat:@" | %@ largest step %.1f pt at %.2f s, made anew %lu times", kWatched[i], worst[i], worstAt[i], (unsigned long)replaced[i]];
    }
    NSLog(@"%@", out);
}
@end

#pragma mark - the app

// Before every %ctor, so the redesign's gate reads on.
__attribute__((constructor(101))) static void sgr_harnessDefaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign"];
}

@interface SGHarnessApp : UIResponder <UIApplicationDelegate>
@end
@implementation SGHarnessApp
@end

@interface SGHarnessScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGHarnessScene

static void after(double seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    SGHarnessChrome *chrome = [SGHarnessChrome new];
    self.window.rootViewController = chrome;
    [self.window makeKeyAndVisible];

    // What happens, from the launch argument: `none` no message bar, `shown` one sliding in at 1.5 s,
    // `away` one there from the start sliding away at 1.5 s, `cycle` in at 1.5 s and out at 4.5 s.
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    NSString *mode = args.count > 1 ? args[1] : @"none";
    // `jam`: in a Jam from the start, and out of it at 3.5 s.
    if ([mode isEqualToString:@"jam"]) {
        after(3.5, ^{
            [sgJamStrip removeFromSuperview];
            chrome.npbHeight.constant = 64;
            [chrome.view layoutIfNeeded];
        });
        after(4.5, ^{ report(chrome, @"left the jam"); });
    }
    if ([mode isEqualToString:@"away"]) [chrome setBanner:YES animated:NO];
    // `mini`: the bar minimized at 1 s and logged at 2.5 s, expanded again at 3.5 s and logged at 5 s.
    if ([mode isEqualToString:@"mini"]) {
        after(1.0, ^{ SGRSetTabBarMinimized(YES, YES); });
        after(3.5, ^{ SGRSetTabBarMinimized(NO, YES); });
        after(5.0, ^{ report(chrome, @"expanded again"); });
    }
    // `tap`: the bar minimized at 1 s, then what a finger on the leading circle lands on, and that tap played.
    if ([mode isEqualToString:@"tap"]) {
        after(1.0, ^{ SGRSetTabBarMinimized(YES, YES); });
        after(2.5, ^{
            report(chrome, @"minimized");
            UITabBar *bar = systemBarIn(chrome.tabs.bar);
            UIView *platter = platterIn(bar);
            UIWindow *window = chrome.view.window;
            CGRect circle = [platter convertRect:platter.bounds toView:window];
            UIView *hit = [window hitTest:CGPointMake(CGRectGetMidX(circle), CGRectGetMidY(circle)) withEvent:nil];
            NSLog(@"[harness] touch on the leading circle %@ lands on %@, on the glass bar: %d", NSStringFromCGRect(circle),
                  NSStringFromClass(hit.class), [hit isDescendantOfView:bar]);
            for (UIView *v = hit; v && v != window; v = v.superview) {
                for (UIGestureRecognizer *r in v.gestureRecognizers) NSLog(@"[harness]   recognizer %@ on %@", NSStringFromClass(r.class), NSStringFromClass(v.class));
                if ([v isKindOfClass:UIControl.class]) NSLog(@"[harness]   control %@", NSStringFromClass(v.class));
            }
            // With `split`, the trailing circle keeps its own touches too.
            for (UITabBar *other in systemBarsIn(chrome.tabs.bar)) {
                UIView *otherPlatter = other == bar || other.hidden ? nil : platterIn(other);
                if (!otherPlatter) continue;
                CGRect trailing = [otherPlatter convertRect:otherPlatter.bounds toView:window];
                UIView *otherHit = [window hitTest:CGPointMake(CGRectGetMidX(trailing), CGRectGetMidY(trailing)) withEvent:nil];
                NSLog(@"[harness] touch on the trailing circle %@ lands on %@, on its glass bar: %d", NSStringFromCGRect(trailing),
                      NSStringFromClass(otherHit.class), [otherHit isDescendantOfView:other]);
            }
            SGHarnessTap(window, CGPointMake(CGRectGetMidX(circle), CGRectGetMidY(circle)));
        });
        after(3.5, ^{ report(chrome, @"after the tap"); });
        after(3.6, ^{ reportSelection(chrome, @"after the tap"); });
        // It stays expanded until the list is scrolled down again.
        after(5.0, ^{ report(chrome, @"a while after the tap"); });
    }
    // `turns`: real flings on the list, from its top: one down that minimizes the bar, one back up that turns it
    // half way, then down again half way through that, and a finger stopping the list as the bar minimizes.
    // Every check at rest should be IN STEP with no animations left.
    if ([mode isEqualToString:@"turns"]) {
        UITableView *list = (UITableView *)chrome.tabs.childViewControllers.firstObject.view;
        after(0.7, ^{ [list setContentOffset:CGPointMake(0, -list.adjustedContentInset.top) animated:NO]; });
        after(1.0, ^{ fling(chrome, 250); });
        after(1.3, ^{ check(chrome, @"minimizing"); });
        after(2.4, ^{ check(chrome, @"minimized"); });
        // Room both ways again after the report at 2.5 takes the list to its end.
        after(2.7, ^{ [list setContentOffset:CGPointMake(0, 300) animated:NO]; });
        after(3.0, ^{ fling(chrome, -150); });
        after(3.25, ^{ fling(chrome, 250); });
        after(5.0, ^{ check(chrome, @"after turning back half way"); });
        after(5.5, ^{ fling(chrome, -150); });
        after(5.75, ^{ SGHarnessTap(chrome.view.window, CGPointMake(200, 400)); });
        after(7.0, ^{ check(chrome, @"after a finger stopped the list"); });
        after(7.5, ^{ fling(chrome, 250); });
        after(7.65, ^{ fling(chrome, -150); });
        after(7.8, ^{ fling(chrome, 250); });
        after(7.95, ^{ fling(chrome, -150); });
        after(9.5, ^{ check(chrome, @"after four quick turns"); });
    }
    // `motion`: a minimize and an expand, each turned back 0.15 s in, and four turns 0.1 s apart, sampled every
    // frame (SGHarnessSampler). No largest step should be much over a spring's, nothing should be made anew while it
    // moves, names should be whole mid-expand, and every check IN STEP.
    if ([mode isEqualToString:@"motion"]) {
        static SGHarnessSampler *sampler;
        sampler = [SGHarnessSampler new];
        sampler.chrome = chrome;
        // Each stretch lasts 1 s and the next starts 0.3 s after it; turns are timed from the stretch's start,
        // since dispatch_after may run a block up to a tenth of its delay late, which at 3 s swallowed a turn
        // 0.15 s after another. The first turn of each goes the other way from where the bar is.
        NSArray *stretches = @[
            @[@"minimize", @[@0]],
            @[@"expand", @[@0]],
            @[@"minimize turned back", @[@0, @0.15]],
            @[@"minimize again", @[@0]],
            @[@"expand turned back", @[@0, @0.15]],
            @[@"four quick turns", @[@0, @0.1, @0.2, @0.3]],
        ];
        static void (^run)(NSUInteger);
        run = ^(NSUInteger index) {
            if (index >= stretches.count) {
                reportNames(chrome, @"after the turns");
                return;
            }
            NSString *moment = stretches[index][0];
            NSArray<NSNumber *> *turns = stretches[index][1];
            BOOL first = !SGRTabBarMinimized();
            [sampler begin:moment];
            for (NSUInteger i = 0; i < turns.count; i++) {
                BOOL minimize = i % 2 == 0 ? first : !first;
                after(turns[i].doubleValue, ^{ SGRSetTabBarMinimized(minimize, YES); });
            }
            after(0.15, ^{
                if (!first) reportNames(chrome, [moment stringByAppendingString:@", 0.15 s in"]);
            });
            after(1.0, ^{
                [sampler end];
                check(chrome, moment);
                reportNames(chrome, [moment stringByAppendingString:@", at rest"]);
                after(0.3, ^{ run(index + 1); });
            });
        };
        after(1.0, ^{ run(0); });
    }
    // `nested`: the bar minimized from inside someone else's animation: a property animator scrubbed by hand and
    // left paused a third of the way, as a header that follows the scroll keeps one (at 1 s), and a plain
    // animation block (at 4 s, expanding). Each check at rest should be IN STEP with no animations left.
    if ([mode isEqualToString:@"nested"]) {
        static UIViewPropertyAnimator *scrub;
        after(1.0, ^{
            UIView *page = chrome.tabs.childViewControllers.firstObject.view;
            scrub = [[UIViewPropertyAnimator alloc] initWithDuration:1 curve:UIViewAnimationCurveLinear animations:^{
                page.alpha = 0.9;
                SGRSetTabBarMinimized(YES, YES);
            }];
            scrub.fractionComplete = 0.33;
        });
        after(2.4, ^{ check(chrome, @"minimized in a paused animator"); });
        after(4.0, ^{
            [UIView animateWithDuration:3 animations:^{ SGRSetTabBarMinimized(NO, YES); }];
        });
        after(4.4, ^{ check(chrome, @"expanding in a slow animation block"); });
        after(5.6, ^{ check(chrome, @"expanded in a slow animation block"); });
    }
    // `names`: the titles at rest, after a minimize and expand, after scrolls that turn the bar back before
    // it settles, and mid-expand; `split`, `five` and `long` change the bar. Every report should say 0 cut.
    if ([mode isEqualToString:@"names"]) {
        after(1.0, ^{ reportNames(chrome, @"at rest"); });
        after(1.2, ^{ SGRSetTabBarMinimized(YES, YES); });
        after(2.4, ^{
            SGRSetTabBarMinimized(NO, YES);
            reportNames(chrome, @"expanding");
        });
        after(2.55, ^{ reportNames(chrome, @"mid-expand"); });
        after(4.0, ^{ reportNames(chrome, @"expanded"); });
        after(4.2, ^{ SGRSetTabBarMinimized(YES, YES); });
        after(4.3, ^{ SGRSetTabBarMinimized(NO, YES); });
        after(4.4, ^{ SGRSetTabBarMinimized(YES, YES); });
        after(4.5, ^{ SGRSetTabBarMinimized(NO, YES); });
        after(6.0, ^{ reportNames(chrome, @"after quick turns"); });
        after(6.2, ^{ SGRSetTabBarMinimized(YES, NO); });
        after(6.4, ^{ SGRSetTabBarMinimized(NO, NO); });
        after(7.0, ^{ reportNames(chrome, @"after a cut"); });
        after(7.2, ^{
            [chrome.tabs.bar setNeedsLayout];
            [chrome.tabs.bar layoutIfNeeded];
        });
        after(7.5, ^{ reportNames(chrome, @"after Spotify lays out"); });
    }
    // `lit`: Library stands in for a tab of the mod's own whose page is up at 2 s, while Spotify still paints
    // Home white: the glass bar selects Library. Home picked at 3.5 s takes the light back.
    if ([mode isEqualToString:@"lit"]) {
        after(2.0, ^{
            sgHarnessLitTab = stockItem(chrome, @"Your Library");
            [chrome.tabs.bar setNeedsLayout];
            [chrome.tabs.bar layoutIfNeeded];
        });
        after(2.5, ^{ reportSelection(chrome, @"with Library lit"); });
        after(3.5, ^{ pick(chrome, @"Home"); });
        after(4.5, ^{ reportSelection(chrome, @"after Home"); });
    }
    // `pick`: Search picked at 2 s and Home at 4 s, which bar selects what logged after each.
    if ([mode isEqualToString:@"pick"]) {
        after(2.0, ^{ pick(chrome, @"Search"); });
        after(3.0, ^{ reportSelection(chrome, @"after Search"); });
        after(4.0, ^{ pick(chrome, @"Home"); });
        after(5.0, ^{ reportSelection(chrome, @"after Home"); });
    }
    after(0.5, ^{
        UITableView *list = (UITableView *)chrome.tabs.childViewControllers.firstObject.view;
        [list scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:29 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        report(chrome, @"start");
    });
    if ([mode isEqualToString:@"shown"] || [mode isEqualToString:@"cycle"]) after(1.5, ^{ [chrome setBanner:YES animated:YES]; });
    if ([mode isEqualToString:@"away"]) after(1.5, ^{ [chrome setBanner:NO animated:YES]; });
    if ([mode isEqualToString:@"cycle"]) after(4.5, ^{ [chrome setBanner:NO animated:YES]; });
    // Half way through the slide, what the screen shows (the presentation layers).
    if ([mode isEqualToString:@"shown"] || [mode isEqualToString:@"away"] || [mode isEqualToString:@"cycle"]) after(1.5 + 0.17, ^{
        CALayer *stock = chrome.tabs.bar.layer.presentationLayer, *npb = chrome.npb.layer.presentationLayer, *banner = chrome.banner.layer.presentationLayer;
        NSLog(@"[harness] mid-slide presented: banner top %.1f, tab bar top %.1f, now playing bar bottom %.1f",
              [banner convertPoint:CGPointZero toLayer:self.window.layer.presentationLayer].y,
              [stock convertPoint:CGPointZero toLayer:self.window.layer.presentationLayer].y,
              [npb convertPoint:CGPointMake(0, npb.bounds.size.height) toLayer:self.window.layer.presentationLayer].y);
    });
    after(2.5, ^{
        UITableView *list = (UITableView *)chrome.tabs.childViewControllers.firstObject.view;
        [list scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:29 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        report(chrome, mode);
    });
}

@end

int main(int argc, char *argv[]) {
    sgJam = argc > 1 && strcmp(argv[1], "jam") == 0;
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGHarnessApp.class)); }
}
