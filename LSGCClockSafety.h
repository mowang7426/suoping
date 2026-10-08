#pragma once
#include "LSGCClockScope.h"
// Portable commit gate shared by UIKit and executable regression tests.
struct LSGCClockReadiness {
    bool enabled, fontReady, maskHasInk, attached, visible, onScreen, current;
    double opacity;
    bool hookInstalled;
};
static inline bool LSGCCanReplaceClock(const LSGCClockReadiness &r) {
    return r.hookInstalled && r.enabled && r.fontReady && r.maskHasInk && r.attached &&
           r.visible && r.onScreen && r.current && r.opacity >= 0.01;
}

// Exception is scoped to one verified source wrapper, never a faded ancestor.
static inline bool LSGCAllowSourceWrapper(bool mainClock, bool directPlainView,
                                        bool timeAbove, bool hidden, double alpha) {
    return mainClock && directPlainView && timeAbove && !hidden && alpha == 0.0;
}

// Candidate is the direct parent of CSProminentTimeView in the real hierarchy,
// not necessarily label.superview. Legacy direct-label wrappers remain supported.
static inline int LSGCClockWrapperIndex(const char *const *names, unsigned count) {
    if (!LSGCMainClockChain(names,count)) return -1;
    for (unsigned i=1; i+2<count; ++i)
        if (!std::strcmp(names[i],"CSProminentTimeView") &&
            !std::strcmp(names[i+1],"UIView")) return int(i+1);
    return count>2 && !std::strcmp(names[1],"UIView") ? 1 : -1;
}
