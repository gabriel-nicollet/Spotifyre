// Stands in for tweak/Sources/Core/SGCore.h in the download check: SGSingModel.m needs only SGLog, here printed
// to stderr so the run shows it.
#import <Foundation/Foundation.h>

#define SGLog(fmt, ...) fprintf(stderr, "[spotifyglass] %s\n", [NSString stringWithFormat:(fmt), ##__VA_ARGS__].UTF8String)
