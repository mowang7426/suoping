#pragma once
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
