// Sing's mic button (Redesigned/Lyrics/SGRSingButton.m) on a field like the player's lyrics, in the state the
// launch line asks for (sing-stubs.m), its slider opened with -panel 1, for screenshots in the simulator.
//
//     ./build.sh && xcrun simctl install <udid> build/SingButtonHarness.app
//     xcrun simctl launch <udid> com.vojta.singbuttonharness -state 7 -panel 1 -level 0.4
//     xcrun simctl launch <udid> com.vojta.singbuttonharness -state 2 -progress 0.4 -waiting 1
//     xcrun simctl io <udid> screenshot shot.png
#import <UIKit/UIKit.h>
#import "Redesigned/Lyrics/SGRSingButton.h"

UIColor *SGRAccentColor(void) { return nil; }

UIViewController *SGTopController(void) {
    UIWindowScene *scene = (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject;
    UIViewController *top = scene.windows.firstObject.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

@interface SGHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGHarnessDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = [UIColor colorWithRed:0.16 green:0.1 blue:0.22 alpha:1];
    CGSize size = UIScreen.mainScreen.bounds.size;
    UILabel *line = [[UILabel alloc] initWithFrame:CGRectMake(24, size.height * 0.3, size.width - 48, 80)];
    line.text = @"And the voice should come out clean";
    line.numberOfLines = 2;
    line.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    line.textColor = UIColor.whiteColor;
    [root.view addSubview:line];
    SGRSingButton *button = [[SGRSingButton alloc] initWithFrame:CGRectMake(size.width - 24 - 44, size.height - 44 - 12 - 120, 44, 44)];
    [root.view addSubview:button];
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"panel"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
            [button performSelector:@selector(showPanel)];
        });
    }
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGHarnessDelegate.class));
    }
}
