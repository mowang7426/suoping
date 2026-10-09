#pragma once
#include <cmath>
// Only presentation fade on a shared ancestor may be zero during wake.
// Model visibility remains a safety gate; detached ink can still stay cached.
static inline bool LSGCClockCommonOpacityValid(double alpha, double model, double shown) {
    return std::isfinite(alpha) && std::isfinite(model) && std::isfinite(shown) &&
           alpha >= 0.01 && model >= 0.01;
}
// Shared production/test transition policy. Source and host model visibility,
// clipping, window identity and geometry are validated before this policy.
enum LSGCClockAction { LSGCClockNative, LSGCClockBuild, LSGCClockReuse };
struct LSGCClockInput {
    bool enabled, hooks, sourceAndHostValid, fontReady, geometryValid;
    bool cachedInk, signatureMatches, failedCurrentBuild;
};
static inline LSGCClockAction LSGCClockNext(const LSGCClockInput &i) {
    if (!i.enabled || !i.hooks || !i.sourceAndHostValid || !i.fontReady || !i.geometryValid || i.failedCurrentBuild)
        return LSGCClockNative;
    return i.cachedInk && i.signatureMatches ? LSGCClockReuse : LSGCClockBuild;
}
// Never suppress solely because a cached bitmap exists. Actual mount, style,
// outline and structural readiness must succeed in the same transaction.
static inline bool LSGCClockCommit(LSGCClockAction action, bool mountedAndReady) {
    return action != LSGCClockNative && mountedAndReady;
}
