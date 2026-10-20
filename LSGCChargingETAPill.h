#import <UIKit/UIKit.h>

// Event-driven original single-line lock-screen capsule. Optional OwnETA updates
// text only; all IOKit sampling/math/cache work belongs to its background queue.
void LSGCChargingETAPillSetEnabled(BOOL enabled);
void LSGCChargingETAPillRefresh(void);
void LSGCChargingETAPillClear(void);
NSString *LSGCBatteryText(UIDeviceBatteryState state, float level);
NSInteger LSGCBatteryPercent(float level);
