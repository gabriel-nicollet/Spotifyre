#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "AppIcon.h"

// The names Info.plist declares, sorted, so the list reads the same each time.
static NSArray<NSString *> *iconNames(void) {
    NSDictionary *icons = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleIcons"];
    NSDictionary *alternates = [icons isKindOfClass:NSDictionary.class] ? icons[@"CFBundleAlternateIcons"] : nil;
    if (![alternates isKindOfClass:NSDictionary.class]) return @[];
    return [alternates.allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

static NSString *label(NSString *name) {
    return name ? [name stringByReplacingOccurrencesOfString:@"_" withString:@" "] : @"Default";
}

static void setIcon(NSString *icon) {
    [UIApplication.sharedApplication setAlternateIconName:icon completionHandler:^(NSError *error) {
        if (!error) return;   // iOS says so itself when it worked
        SGLog(@"app icon: %@ not set: %@", label(icon), error.localizedDescription);
        // A re-signed install, or a call while the app is not frontmost, can be refused; without
        // a word the row looks broken. The handler can run off the main thread.
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"The icon did not change"
                                                                           message:error.localizedDescription
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [SGTopController() presentViewController:alert animated:YES completion:nil];
        });
    }];
}

// A menu of Default and the icons, as the page's other choices are.
SGModRow *SGAppIconRow(void) {
    NSArray<NSString *> *names = iconNames();
    if (!names.count || !UIApplication.sharedApplication.supportsAlternateIcons) return nil;
    NSMutableArray<NSString *> *choices = [NSMutableArray arrayWithObject:label(nil)];
    for (NSString *name in names) [choices addObject:label(name)];
    return SGWithSymbol(SGMenuRow(@"App icon", choices, ^NSString *{ return label(UIApplication.sharedApplication.alternateIconName); },
                                  ^(NSInteger index) { setIcon(index > 0 ? names[(NSUInteger)index - 1] : nil); }), @"app.badge");
}
