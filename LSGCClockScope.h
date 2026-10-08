#pragma once
#include <cstring>
// Exact hierarchy contract, shared by UIKit discovery and portable tests.
// Text resembling a time is deliberately NOT an identity signal.
static inline bool LSGCMainClockChain(const char *const *names, unsigned count) {
    if (!count || std::strcmp(names[0], "_UIAnimatingLabel")) return false;
    unsigned stage=0;
    for (unsigned i=1; i<count; ++i) {
        const char *n=names[i];
        if (!std::strcmp(n,"CSProminentSubtitleDateView") ||
            !std::strcmp(n,"BSUIRelativeDateLabel")) return false;
        if (stage==0 && !std::strcmp(n,"CSProminentTimeView")) stage=1;
        else if (stage==1 && !std::strcmp(n,"CSProminentDisplayView")) stage=2;
        else if (stage==2 && !std::strcmp(n,"SBFLockScreenDateView")) stage=3;
    }
    return stage==3;
}
