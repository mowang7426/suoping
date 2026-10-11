#pragma once
#include <cstdint>
// UIDeviceBatteryState public enum: Unknown=0, Unplugged=1, Charging=2, Full=3.
inline bool LSGCPillAllowed(bool enabled, bool pillEnabled, int state) {
    return enabled && pillEnabled && (state == 2 || state == 3);
}
inline bool LSGCPillNeedsText(bool newLabel, bool cacheEqual, bool actualEqual) {
    return newLabel || !cacheEqual || !actualEqual;
}
struct LSGCPillQueue {
    uint64_t generation = 0;
    bool pending = false;
    void clear() { ++generation; pending = false; }
    bool enqueue(uint64_t &ticket) {
        if (pending) return false;
        pending = true; ticket = generation; return true;
    }
    bool consume(uint64_t ticket) {
        if (ticket != generation || !pending) return false;
        pending = false; return true;
    }
};
