// Checks CleanLinks.x's hooks in the iOS simulator: what reaches a pasteboard by each of its setters, and what
// the share sheet's items answer, a provider's -item and an item source's answer included. Run by
// ../build-sim.sh with simctl spawn, no app around it; the exit status is the number of failures.
#import <UIKit/UIKit.h>

static int failures;

static void check(id got, NSString *wanted, NSString *what) {
    NSString *text = [got isKindOfClass:NSURL.class] ? [got absoluteString] : [got description];
    BOOL ok = [text isEqualToString:wanted];
    printf("%s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    if (!ok) printf("     got    %s\n     wanted %s\n", text.UTF8String, wanted.UTF8String);
    failures += !ok;
}

static NSString *const kDirty = @"https://open.spotify.com/track/a?si=1&utm_source=copy-link";
static NSString *const kClean = @"https://open.spotify.com/track/a";

// Overrides -item the way a provider does, Branch's among them.
@interface CheckProvider : UIActivityItemProvider
@end
@implementation CheckProvider
- (id)item {
    return [NSURL URLWithString:kDirty];
}
@end

@interface CheckSubProvider : CheckProvider
@end
@implementation CheckSubProvider
@end

@interface CheckSource : NSObject <UIActivityItemSource>
@end
@implementation CheckSource
- (id)activityViewControllerPlaceholderItem:(UIActivityViewController *)sheet {
    return @"";
}
- (id)activityViewController:(UIActivityViewController *)sheet itemForActivityType:(UIActivityType)type {
    return [@"Listen: " stringByAppendingString:kDirty];
}
@end

int main(void) {
    @autoreleasepool {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"spotifyglass.cleanSharedLinks"];
        UIPasteboard *board = [UIPasteboard pasteboardWithUniqueName];

        board.string = kDirty;
        check(board.string, kClean, @"setString:");
        board.URL = [NSURL URLWithString:kDirty];
        check(board.URL, kClean, @"setURL:");
        board.strings = @[kDirty, @"plain"];
        check([board.strings componentsJoinedByString:@" "], [kClean stringByAppendingString:@" plain"], @"setStrings:");
        [board setItems:@[@{@"public.utf8-plain-text": kDirty}] options:@{}];
        check(board.string, kClean, @"setItems:options: with a string");
        board.items = @[@{@"public.url": [NSURL URLWithString:kDirty]}];
        check(board.URL, kClean, @"setItems: with a URL");
        [board setData:[kDirty dataUsingEncoding:NSUTF8StringEncoding] forPasteboardType:@"public.utf8-plain-text"];
        check(board.string, kClean, @"setData:forPasteboardType: as text");
        NSData *image = [@"https://open.spotify.com/x?si=1" dataUsingEncoding:NSUTF8StringEncoding];
        [board setData:image forPasteboardType:@"public.png"];
        check([[NSString alloc] initWithData:[board dataForPasteboardType:@"public.png"] encoding:NSUTF8StringEncoding],
              @"https://open.spotify.com/x?si=1", @"setData:forPasteboardType: under an image type is left alone");
        board.string = @"https://example.com/?si=1";
        check(board.string, @"https://example.com/?si=1", @"another host is left alone");

        CheckProvider *provider = [[CheckProvider alloc] initWithPlaceholderItem:@""];
        CheckSubProvider *subProvider = [[CheckSubProvider alloc] initWithPlaceholderItem:@""];
        CheckSource *source = [CheckSource new];
        UIActivityViewController *sheet = [[UIActivityViewController alloc]
            initWithActivityItems:@[kDirty, [NSURL URLWithString:kDirty], provider, subProvider, source] applicationActivities:nil];
        NSArray *items = [sheet valueForKey:@"activityItems"];
        check(items.count > 1 ? items[0] : nil, kClean, @"a share sheet string");
        check(items.count > 1 ? items[1] : nil, kClean, @"a share sheet URL");
        check(provider.item, kClean, @"a provider's -item");
        check(subProvider.item, kClean, @"a provider's subclass's -item");
        check([source activityViewController:sheet itemForActivityType:UIActivityTypeCopyToPasteboard],
              [@"Listen: " stringByAppendingString:kClean], @"an item source's answer");

        [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"spotifyglass.cleanSharedLinks"];
        board.string = kDirty;
        check(board.string, kDirty, @"switched off: setString: as it came");
        check(provider.item, kDirty, @"switched off: a provider's -item as it came");
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"spotifyglass.cleanSharedLinks"];
        [UIPasteboard removePasteboardWithName:board.name];
    }
    printf("%d failed\n", failures);
    return failures;
}
