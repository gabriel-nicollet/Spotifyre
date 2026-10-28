#import "SGLog.h"
#import <os/lock.h>

#if SG_DRIVER
// The last lines, for the phone driver. They come from any thread, so a lock, never the main queue.
static const NSUInteger kRemembered = 2000;
static os_unfair_lock sg_logLock = OS_UNFAIR_LOCK_INIT;
static NSMutableArray<NSDictionary *> *sg_logLines;
static uint64_t sg_logSeq;

void SGLogRemember(NSString *line) {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    os_unfair_lock_lock(&sg_logLock);
    if (!sg_logLines) sg_logLines = [NSMutableArray array];
    [sg_logLines addObject:@{@"seq" : @(++sg_logSeq), @"t" : @(now), @"text" : line ?: @""}];
    if (sg_logLines.count > kRemembered) [sg_logLines removeObjectAtIndex:0];
    os_unfair_lock_unlock(&sg_logLock);
}

NSArray<NSDictionary *> *SGLogRecent(uint64_t after) {
    os_unfair_lock_lock(&sg_logLock);
    NSIndexSet *newer = [sg_logLines indexesOfObjectsPassingTest:^BOOL(NSDictionary *entry, NSUInteger i, BOOL *stop) {
        return [entry[@"seq"] unsignedLongLongValue] > after;
    }];
    NSArray<NSDictionary *> *lines = [sg_logLines objectsAtIndexes:newer] ?: @[];
    os_unfair_lock_unlock(&sg_logLock);
    return lines;
}

uint64_t SGLogLastSeq(void) {
    os_unfair_lock_lock(&sg_logLock);
    uint64_t seq = sg_logSeq;
    os_unfair_lock_unlock(&sg_logLock);
    return seq;
}
#endif

// The unified log cuts a message at about 1 KB, so long dumps go out as numbered parts.
void SGLogLong(NSString *tag, NSString *text) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (current.length && [current lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + [line lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 900) {
            [parts addObject:[current copy]];
            [current setString:@""];
        }
        [current appendFormat:@"%@\n", line];
    }
    if (current.length) [parts addObject:current];
    [parts enumerateObjectsUsingBlock:^(NSString *part, NSUInteger i, BOOL *stop) {
        SGLog(@"%@ %lu/%lu\n%@", tag, (unsigned long)i + 1, (unsigned long)parts.count, part);
    }];
}

void SGRequireClasses(NSArray<NSString *> *names) {
    for (NSString *name in names) {
        if (!NSClassFromString(name)) SGLog(@"class %@ not found, its hooks are inactive", name);
    }
}
