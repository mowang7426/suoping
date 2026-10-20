#import <UIKit/UIKit.h>
#import "LSGCJikanETAAdapter.h"

// Event-driven capsule. Jikan is optional, read-only, and always falls back.
void LSGCChargingETAPillRefresh(void);
void LSGCChargingETAPillClear(void);
NSString *LSGCBatteryText(UIDeviceBatteryState state, float level);
NSString *LSGCChargingText(UIDeviceBatteryState state, float level, LSGCJikanETASnapshot *snapshot);
NSInteger LSGCBatteryPercent(float level);
