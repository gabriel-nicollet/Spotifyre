// Loaded into Spotify only in the simulator (scripts/sim-build.sh), never into a build for the phone.
//
// MSHookMessageEx: the tweak calls Substrate's in one place (Redesigned/Player/PlayerFooter.x) and the
// simulator has no Substrate, so this stands in for it with the ObjC runtime.
//
// hw.machine: the simulator answers "arm64", the host's, where a phone answers "iPhone18,1". This answers
// the simulated device's model identifier instead, the way a phone would.
//
// FairPlay: the simulator throws on making an AVContentKeySession ("FairPlay Streaming is not supported on
// simulators"), and Spotify 9.1.90 makes one as the player opens and on an artist's video, so Spotify quit
// there. Here the session is nil instead, as a phone that refuses one.
//
// FLEXManager (SG_DRIVER=1 only): the tweak starts its tree server and phone driver only where FLEX is
// loaded, and asks for the class by name, nothing more. An empty class turns them on without FLEX.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>

__attribute__((visibility("default"))) void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *orig) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { if (orig) *orig = NULL; return; }
    // An inherited method is added to this class, so the superclass keeps its own.
    IMP old = method_getImplementation(m);
    if (!class_addMethod(cls, sel, imp, method_getTypeEncoding(m))) old = method_setImplementation(m, imp);
    if (orig) *orig = old;
}

static const char *Model(void) {
    const char *m = getenv("SIMULATOR_MODEL_IDENTIFIER");
    return m && *m ? m : "iPhone18,1";
}

static int PutModel(void *oldp, size_t *oldlenp) {
    size_t n = strlen(Model()) + 1;
    if (oldp) {
        if (*oldlenp < n) { errno = ENOMEM; return -1; }
        memcpy(oldp, Model(), n);
    }
    *oldlenp = n;
    return 0;
}

static int SimSysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name && oldlenp && !newp && strcmp(name, "hw.machine") == 0) return PutModel(oldp, oldlenp);
    return sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

static int SimSysctl(int *mib, u_int len, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (len == 2 && mib[0] == CTL_HW && mib[1] == HW_MACHINE && oldlenp && !newp) return PutModel(oldp, oldlenp);
    return sysctl(mib, len, oldp, oldlenp, newp, newlen);
}

static int SimUname(struct utsname *u) {
    int r = uname(u);
    if (r == 0) strlcpy(u->machine, Model(), sizeof u->machine);
    return r;
}

static IMP sg_keySessionInit;

static id KeySessionInit(id self, SEL _cmd, id keySystem, id directory, BOOL legacy) {
    @try {
        return ((id (*)(id, SEL, id, id, BOOL))sg_keySessionInit)(self, _cmd, keySystem, directory, legacy);
    } @catch (NSException *e) {
        return nil;
    }
}

__attribute__((constructor)) static void NoFairPlay(void) {
    Class session = objc_getClass("AVContentKeySession");
    Method init = session ? class_getInstanceMethod(session, sel_registerName("initWithKeySystem:storageDirectoryAtURL:legacyWebKitCompatibilityMode:")) : NULL;
    if (init) sg_keySessionInit = method_setImplementation(init, (IMP)KeySessionInit);
}

#if SG_DRIVER
@interface FLEXManager : NSObject
@end
@implementation FLEXManager
@end
#endif

#define INTERPOSE(replacement, original) \
    __attribute__((used)) static const struct { const void *r, *o; } interpose_##original \
    __attribute__((section("__DATA,__interpose"))) = { (const void *)replacement, (const void *)original }
INTERPOSE(SimSysctlbyname, sysctlbyname);
INTERPOSE(SimSysctl, sysctl);
INTERPOSE(SimUname, uname);
