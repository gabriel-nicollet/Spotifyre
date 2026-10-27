#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SGSingAlternateModel) {
    SGSingAlternateModelFull = 0,
    SGSingAlternateModelANE = 1,
    SGSingAlternateModelLight = 2,
};

extern NSString *const SGKeySingModelVariant;
BOOL SGSingAlternateModelInstalled(SGSingAlternateModel model);
BOOL SGSingAlternateModelDownloading(SGSingAlternateModel model);
double SGSingAlternateModelProgress(SGSingAlternateModel model);
int64_t SGSingAlternateModelSize(SGSingAlternateModel model);
NSString *SGSingAlternateModelSpaceProblem(SGSingAlternateModel model);
NSString *SGSingAlternateModelPath(SGSingAlternateModel model);
void SGSingAlternateModelDownload(SGSingAlternateModel model, BOOL metered);
void SGSingAlternateModelCancel(SGSingAlternateModel model);
void SGSingAlternateModelRemove(SGSingAlternateModel model);
void SGSingAlternateModelSelect(SGSingAlternateModel model);
NSString *SGSingEffectiveModelPath(NSString *fullModelPath);
BOOL SGSingAlternateModelsHandlesSession(NSString *identifier, void (^completion)(void));
void SGSingAlternateModelsReconnect(void);
