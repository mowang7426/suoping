#pragma once
#include <cstring>
// Traditional candidates are structural, never font-size or broad lock-screen matches.
// Direct UILabel siblings are only diagnostic candidates: UIKit does not publish
// their role and charging/transition labels may share that parent.
static inline int LSGCLegacyClockKind(const char *const *n, unsigned count) {
    if (count>=3 && !std::strcmp(n[0],"UILabel") &&
        !std::strcmp(n[1],"SBUILegibilityLabel") &&
        !std::strcmp(n[2],"SBFLockScreenDateView")) return 1;
    if (count>=2 && (!std::strcmp(n[0],"UILabel") ||
        !std::strcmp(n[0],"SBUILegibilityLabel")) &&
        !std::strcmp(n[1],"SBFLockScreenDateView")) return 2;
    return 0;
}
struct LSGCLegacyReadiness {
    bool uniqueTimeSource, ownerVerified, textDrawHook, imageBranchAbsent;
};
static inline bool LSGCCanRenderLegacy(const LSGCLegacyReadiness &r) {
    return r.uniqueTimeSource && r.ownerVerified && r.textDrawHook && r.imageBranchAbsent;
}
