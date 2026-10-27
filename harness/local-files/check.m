// Checks LocalFiles.m as the tweak compiles it: a URI read back into names, an edit laid over them, the
// lyrics key an edit gives (a new one for a rename only), and a stored cover's address and its way back.
// Runs in its own defaults domain and Application Support, so nothing of the Mac's is touched. Exits
// non-zero on the first wrong answer.
#import <UIKit/UIKit.h>
#import "Shared/LocalFiles/LocalFiles.h"

#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #cond); exit(1); } } while (0)

static UIImage *square(void) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(4, 4)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.redColor setFill];
        UIRectFill(CGRectMake(0, 0, 4, 4));
    }];
}

int main(void) {
    @autoreleasepool {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyLocalFileEdits];
        NSString *uri = @"spotify:local:Daft+Punk:Discovery:One+More+Time%3A+Remix:320";

        // The URI's own names, form decoded, and the bare URI as the key.
        NSDictionary *tags = SGLocalFileTags(uri);
        CHECK([tags[@"title"] isEqualToString:@"One More Time: Remix"] && [tags[@"artist"] isEqualToString:@"Daft Punk"]);
        CHECK([tags[@"seconds"] integerValue] == 320);
        CHECK([SGLocalFileLyricsKey(uri) isEqualToString:uri]);
        CHECK(!SGLocalFileLyricsKey(@"spotify:track:4uLU6hMCjMI75M1A2tKUQC"));

        // A cover alone keeps the key: no rename, so the lyrics stay where they are.
        SGLocalFileSaveEdit(uri, @{@"title": @"One More Time: Remix", @"artist": @"", @"album": @"Discovery"}, square(), YES);
        NSDictionary *edit = SGLocalFileEditFor(uri);
        CHECK(edit[@"cover"] && !edit[@"number"] && !edit[@"title"]);
        CHECK([SGLocalFileLyricsKey(uri) isEqualToString:uri]);
        NSString *cover = SGLocalFileCoverPath(edit);
        CHECK([NSFileManager.defaultManager fileExistsAtPath:cover]);
        CHECK([SGLocalFileCoverInURL(SGLocalFileCoverURL(cover)) isEqualToString:cover]);
        CHECK(![SGLocalFileCoverURL(cover) containsString:@"/"]);
        CHECK(!SGLocalFileCoverInURL(@"spotify:localfileimage:%2Fetc%2Fpasswd"));

        // A rename gives a new key, and the names reach the sources through it.
        SGLocalFileSaveEdit(uri, @{@"title": @"One More Time", @"artist": @"Daft Punk"}, nil, YES);
        edit = SGLocalFileEditFor(uri);
        NSString *renamed = SGLocalFileLyricsKey(uri);
        CHECK(edit[@"number"] && edit[@"cover"] && [renamed hasPrefix:[uri stringByAppendingString:@"#"]]);
        CHECK([SGLocalFileInfo(renamed)[@"title"] isEqualToString:@"One More Time"]);
        CHECK([SGLocalFileInfo(renamed)[@"seconds"] integerValue] == 320);

        // The same names saved again, or a new cover with them, keep that key.
        [NSThread sleepForTimeInterval:0.01];
        SGLocalFileSaveEdit(uri, @{@"title": @"One More Time ", @"artist": @"Daft Punk"}, nil, YES);
        CHECK([SGLocalFileLyricsKey(uri) isEqualToString:renamed]);
        SGLocalFileSaveEdit(uri, @{@"title": @"One More Time"}, square(), YES);
        CHECK([SGLocalFileLyricsKey(uri) isEqualToString:renamed]);
        CHECK(![NSFileManager.defaultManager fileExistsAtPath:cover]);   // the replaced cover is gone
        cover = SGLocalFileCoverPath(SGLocalFileEditFor(uri));

        // Another rename, another key.
        [NSThread sleepForTimeInterval:0.01];
        SGLocalFileSaveEdit(uri, @{@"title": @"One More Time (Live)"}, nil, YES);
        NSString *again = SGLocalFileLyricsKey(uri);
        CHECK(![again isEqualToString:renamed] && [again hasPrefix:uri]);

        // Back to the file's own names with the cover kept: the bare URI again.
        SGLocalFileSaveEdit(uri, @{@"title": @"One More Time: Remix"}, nil, YES);
        CHECK([SGLocalFileLyricsKey(uri) isEqualToString:uri] && SGLocalFileEditFor(uri)[@"cover"]);

        // Nothing left over: the edit and its cover go.
        SGLocalFileSaveEdit(uri, @{}, nil, NO);
        CHECK(!SGLocalFileEditFor(uri) && ![NSFileManager.defaultManager fileExistsAtPath:cover]);
        CHECK(!SGLocalFileInfo(@"spotify:local:too:few:parts"));
        printf("local files: all checks passed\n");
    }
    return 0;
}
