#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SGSingModelNetwork) {
    SGSingModelOffline,
    SGSingModelUnmetered,
    SGSingModelMetered,
};

extern NSString *const SGSingModelDidChangeNotification;
int64_t SGSingModelSize(void);
int64_t SGSingModelReceived(void);
NSString *SGSingModelFailure(void);
NSString *SGSingModelPath(void);
NSString *SGSingModelBytesText(int64_t bytes);
NSString *SGSingModelSpaceProblem(void);
void SGSingModelCheckNetwork(void (^done)(SGSingModelNetwork network));
void SGSingModelDownload(BOOL metered);
void SGSingModelCancel(void);
void SGSingModelRemove(void);
BOOL SGSingModelHandlesSession(NSString *identifier, void (^completion)(void));
void SGSingModelReconnect(void);
