#import <UIKit/UIKit.h>

// Event-driven lock-screen charging capsule. Uses only public UIDevice battery
// state/level; no ETA, timer, display link, polling, or percentage estimation.
void LSGCChargingETAPillRefresh(void);
void LSGCChargingETAPillClear(void);
NSString *LSGCBatteryText(UIDeviceBatteryState state, float level);
NSInteger LSGCBatteryPercent(float level);
