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
