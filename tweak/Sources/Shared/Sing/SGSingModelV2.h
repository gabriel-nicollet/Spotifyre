// Sing's downloaded model API, separated from Sing's playback controller state so clients can
// import both without redeclaring SGSingState.
#import <Foundation/Foundation.h>

#define SGKeySingModel @"spotifyglass.sing.model"

typedef NS_ENUM(NSInteger, SGSingModelKind) {
    SGSingModelFull,
    SGSingModelLight,
};
SGSingModelKind SGSingChosenModel(void);
void SGSetSingChosenModel(SGSingModelKind kind);
NSString *SGSingModelSizeTextOf(SGSingModelKind kind);
long long SGSingOtherModelBytes(void);
void SGSingDeleteOtherModel(void);

typedef NS_ENUM(NSInteger, SGSingModelState) {
    SGSingModelMissing,
    SGSingModelDownloading,
    SGSingModelReady,
};
SGSingModelState SGSingModelCurrentState(void);
double SGSingModelProgress(void);
BOOL SGSingModelWaitingForNetwork(void);
void SGSingDownloadModelOverCellular(void);
BOOL SGSingModelOverCellular(void);
BOOL SGSingModelChecking(void);
long long SGSingModelPausedBytes(void);
NSString *SGSingModelError(void);
NSString *SGSingModelSizeText(void);
void SGSingDownloadModel(void);
void SGSingCancelModelDownload(void);
void SGSingDeleteModel(void);
NSURL *SGSingModelURL(void);
BOOL SGSingModelUpdateAvailable(void);
BOOL SGSingModelUpdateDownloading(void);
NSString *SGSingModelInUseSizeText(void);
void SGSingRemoveOldModel(void);
NSArray<NSString *> *SGSingComputeUnitNames(void);
BOOL SGSingOSSupported(void);
