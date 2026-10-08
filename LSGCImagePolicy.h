#pragma once
#include <cstring>
#include <cmath>
// Exact UIKit roles, shared by the runtime adapter and executable regressions.
static inline int LSGCImageRole(const char *const *n, unsigned count) {
    if (count<3 || std::strcmp(n[0],"UILabel") || std::strcmp(n[1],"SBUILegibilityLabel")) return 0;
    if (!std::strcmp(n[2],"SBFLockScreenDateView")) return 1;
    unsigned owner=2;
    if (!std::strcmp(n[owner],"SBFLockScreenAlternateDateLabel")) owner++;
    return count>owner+1 && !std::strcmp(n[owner],"SBFLockScreenDateSubtitleDateView") &&
        !std::strcmp(n[owner+1],"SBFLockScreenDateView") ? 2 : 0;
}
static inline bool LSGCImageGlyphSize(double w,double h,double sourceW,double sourceH) {
    return std::isfinite(w) && std::isfinite(h) && w>0 && h>0 &&
        std::fabs(w-sourceW)<=.5 && std::fabs(h-sourceH)<=.5;
}
static inline bool LSGCImageRestoreOwnedMask(const void *current,const void *owned) {
    return owned && current==owned;
}
static inline bool LSGCImageCommitPolicy(bool enabled,bool isClock,bool dateEnabled,
    bool sourceText,bool glyphVisible,bool wrapperVisible,bool attached,bool ink,bool signatureCurrent) {
    return enabled && (isClock || dateEnabled) && sourceText && glyphVisible && wrapperVisible && attached && ink && signatureCurrent;
}
// UIKit convertPoint supplies the host-local basis; multiply user geometry only
// here so host/window ancestor transforms are not applied a second time.
struct LSGCImageBasis { double a,b,c,d; };
static inline LSGCImageBasis LSGCImageMappedBasis(double ox,double oy,double xx,double xy,
    double yx,double yy,double sx,double sy) {
    LSGCImageBasis result={};
    result.a=(xx-ox)*sx; result.b=(xy-oy)*sx;
    result.c=(yx-ox)*sy; result.d=(yy-oy)*sy;
    return result;
}
static inline bool LSGCImageCacheReusable(bool signatureCurrent,bool ink,bool contents) {
    return signatureCurrent && ink && contents;
}

