#import <UIKit/UIKit.h>

// Event-driven lock-screen charging capsule. No ETA is invented when SpringBoard
// exposes only battery state/level (the public iOS API has no ETA field).
void LSGCChargingETAPillRefresh(void);
void LSGCChargingETAPillClear(void);
NSString *LSGCChargingETAText(BOOL charging, BOOL reliable, NSInteger minutes, BOOL full);
