#include "../LSGCClockSafety.h"
#include <cassert>
#include <cmath>
#include <iostream>
#include <vector>
struct View { bool plain=false, hidden=false; double alpha=1, opacity=1, presentation=1; bool clippedOut=false, mask=false, affine=true, validRect=true; };
static int selectedHost(const char *const *names,unsigned n,const std::vector<View> &v) {
    int w=LSGCClockWrapperIndex(names,n);
    return w>=0 && LSGCAllowSourceWrapper(true,v[w].plain,true,v[w].hidden,v[w].alpha) ? w+1 : -1;
}
static bool accept(const char *const *names,unsigned n,const std::vector<View> &v) {
    int h=selectedHost(names,n,v); if(h<0 || !v[h].validRect) return false;
    double opacity=1;
    for(unsigned i=0;i<v.size();i++) {
        const View &a=v[i];
        if(a.hidden || !a.affine) return false;
        if(int(i)!=h-1 && (!std::isfinite(a.alpha) || a.alpha<.01 ||
            !std::isfinite(a.opacity) || a.opacity<.01 || !std::isfinite(a.presentation) || a.presentation<.01)) return false;
        if(int(i)>=h) {
            if(a.clippedOut || a.mask) return false;
            opacity*=std::fmin(a.opacity,a.presentation);
        }
    }
    return opacity>=.01;
}
int main() {
    // Exact supplied 2.0.4 device chain. The old test incorrectly put UIView
    // immediately above the label, concealing this production regression.
    const char *real[]={"_UIAnimatingLabel","CSProminentTimeView","UIView","BSUIVibrancyEffectView","CSProminentDisplayView","SBFLockScreenDateView","UIWindow"};
    std::vector<View> v(7); v[2].plain=true; v[2].alpha=v[2].opacity=v[2].presentation=0;
    assert(!LSGCAllowSourceWrapper(true,v[1].plain,true,v[1].hidden,v[1].alpha)); // old selector loses
    assert(LSGCClockWrapperIndex(real,7)==2 && selectedHost(real,7,v)==3);
    assert(accept(real,7,v));
    for(unsigned i=0;i<v.size();i++) {
        auto saved=v[i];
        v[i].hidden=true; assert(!accept(real,7,v)); v[i]=saved;
        if(i!=2) {
            v[i].alpha=.005; assert(!accept(real,7,v)); v[i]=saved;
            v[i].opacity=.005; assert(!accept(real,7,v)); v[i]=saved;
            v[i].presentation=NAN; assert(!accept(real,7,v)); v[i]=saved;
        }
        v[i].affine=false; assert(!accept(real,7,v)); v[i]=saved;
        if(i>=3) {
            v[i].clippedOut=true; assert(!accept(real,7,v)); v[i]=saved;
            v[i].mask=true; assert(!accept(real,7,v)); v[i]=saved;
        }
    }
    v[3].validRect=false; assert(!accept(real,7,v)); v[3].validRect=true;
    v[2].alpha=.005; assert(selectedHost(real,7,v)==-1); v[2].alpha=0;
    v[2].plain=false; assert(selectedHost(real,7,v)==-1); v[2].plain=true;
    v[3].opacity=.05; v[4].opacity=.05; assert(!accept(real,7,v)); v[3].opacity=v[4].opacity=1;
    const char *direct[]={"_UIAnimatingLabel","UIView","CSProminentTimeView","CSProminentDisplayView","SBFLockScreenDateView"};
    std::vector<View> d(5); d[1].plain=true; d[1].alpha=0;
    assert(selectedHost(direct,5,d)==2 && accept(direct,5,d));
    d[1].alpha=1; assert(selectedHost(direct,5,d)==-1); // native glyph only, no custom native host
    const char *date[]={"_UIAnimatingLabel","CSProminentSubtitleDateView","UIView","CSProminentDisplayView","SBFLockScreenDateView"};
    const char *notification[]={"BSUIRelativeDateLabel","CSProminentTimeView","UIView","CSProminentDisplayView","SBFLockScreenDateView"};
    const char *charge[]={"UILabel","CSProminentTimeView","UIView","CSProminentDisplayView","SBFLockScreenDateView"};
    assert(LSGCClockWrapperIndex(date,5)==-1 && LSGCClockWrapperIndex(notification,5)==-1 && LSGCClockWrapperIndex(charge,5)==-1);
    assert(LSGCClockWrapperIndex(real,5)==-1);
    std::cout<<"OK: exact 2.0.4 real chain -> wrapper index 2 -> BSUIVibrancyEffectView sibling index 3; source-only exemption; opacity/hidden/clip/mask/3D/rect rejection; no custom native-label fallback\n";
}
