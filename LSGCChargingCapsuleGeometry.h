#pragma once
#include <cmath>
struct LSGCCapsuleGeometry {
    double width=0, height=0, topX=62, textWidth=0;
    bool valid=false;
};
inline LSGCCapsuleGeometry LSGCCapsuleLayout(double gap,double buttonHeight) {
    LSGCCapsuleGeometry g;
    if (!std::isfinite(gap) || !std::isfinite(buttonHeight) || gap<176 || buttonHeight<48) return g;
    g.width=std::fmin(220.0,gap-12); g.height=std::fmin(56.0,buttonHeight);
    g.textWidth=g.width-g.topX-8; g.valid=g.textWidth>=94;
    return g;
}
