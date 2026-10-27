// The scene every harness's window goes into. iOS 27 kills an app whose Info.plist declares a scene
// manifest without a scene delegate. The harness still makes its window in didFinishLaunching, and the
// window moves into the scene once the scene connects. Listed in a harness's build.sh with the scene
// manifest naming SGRHarnessScene.
#import <UIKit/UIKit.h>

@interface SGRHarnessScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGRHarnessScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UIWindow *window = [(id)UIApplication.sharedApplication.delegate window];
    window.windowScene = (UIWindowScene *)scene;
    self.window = window;
    [window makeKeyAndVisible];
}
@end
