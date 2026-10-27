// The home screen icon, picked from the alternate icons the IPA carries: Vitrine's, which
// scripts/pipeline.sh adds from icons/, and any other mod's. iOS keeps the choice, so the row
// reads it back from iOS rather than from the settings.
#import <UIKit/UIKit.h>

@class SGModRow;

// The Appearance card's row, or nil when the IPA carries no alternate icon.
SGModRow *SGAppIconRow(void);
