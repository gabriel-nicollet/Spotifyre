// The saved composition of the redesign's bar, as NSUserDefaults property lists, apart from the native look's.
#import "Navbar.h"
#import "Shared/Navigation/Links.h"

NSString *const SGRNavbarID = @"id";
NSString *const SGRNavbarTitle = @"title";
NSString *const SGRNavbarURI = @"uri";
NSString *const SGRNavbarIcon = @"icon";
NSString *const SGRNavbarIconSet = @"iconSet";
NSString *const SGRNavbarHidden = @"hidden";

static NSString *const kNavbarLayout = @"spotifyglass.redesign.navbar.layout";
static NSString *const kNavbarStock = @"spotifyglass.redesign.navbar.stock";
static NSString *const kNavbarSplit = @"spotifyglass.redesign.navbar.split";

// Only property list types go in, so a corrupt read cannot be anything but an array of dictionaries.
static NSArray *listOfKind(NSString *key, Class kind) {
    NSArray *list = [NSUserDefaults.standardUserDefaults arrayForKey:key];
    for (id item in list) if (![item isKindOfClass:kind]) return @[];
    return list ?: @[];
}

NSArray<NSDictionary *> *SGRNavbarLayout(void) {
    return listOfKind(kNavbarLayout, NSDictionary.class);
}

void SGRSetNavbarLayout(NSArray<NSDictionary *> *layout) {
    [NSUserDefaults.standardUserDefaults setObject:layout ?: @[] forKey:kNavbarLayout];
}

NSArray<NSString *> *SGRNavbarSplit(void) {
    return listOfKind(kNavbarSplit, NSString.class);
}

void SGRSetNavbarSplit(NSArray<NSString *> *split) {
    [NSUserDefaults.standardUserDefaults setObject:split ?: @[] forKey:kNavbarSplit];
}

NSArray<NSString *> *SGRNavbarStock(void) {
    return listOfKind(kNavbarStock, NSString.class);
}

void SGRSetNavbarStock(NSArray<NSString *> *stock) {
    [NSUserDefaults.standardUserDefaults setObject:stock ?: @[] forKey:kNavbarStock];
}

NSURL *SGRNavbarTabURL(NSString *uri) {
    NSURL *url = SGSpotifyURIFromText(uri);
    if ([url.absoluteString isEqualToString:@"spotify:collection:playlists"]) return [NSURL URLWithString:@"spotify:playlists"];
    return url;
}
