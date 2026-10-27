// Stands in for tweak/Sources/Core/SGLog.h in the Mac harness: the separator's and the loader's log lines go to stderr,
// timed from the start, so a run shows them beside the checks.
#import <Foundation/Foundation.h>

#define SGLog(fmt, ...) fprintf(stderr, "  log   %s\n", [NSString stringWithFormat:(fmt), ##__VA_ARGS__].UTF8String)
