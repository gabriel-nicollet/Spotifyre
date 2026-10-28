#import <Foundation/Foundation.h>

// How many times the stand-in was asked since the count was last reset.
extern NSInteger SGHarnessPosts;
// The action of the last post.
extern NSString *SGHarnessLastAction;
// Registers the stand-in, which leaves the first `waitPosts` posts unanswered and never answers previous.
void SGHarnessObserve(NSInteger waitPosts);
