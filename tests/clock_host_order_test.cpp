#include "../LSGCClockSafety.h"
#include "../LSGCClockScope.h"
#include <cassert>
#include <cmath>
#include <iostream>
#include <vector>
struct View { bool plain, hidden; double alpha; };
// Executable hierarchy fixture plus source-order checks in verify_clock_host_order.py.
// Uses the exact production identity/wrapper policy, not time-like text.
static int selectedHost(const char *const *names, unsigned count, const std::vector<View> &views) {
    if (!LSGCMainClockChain(names,count)) return -1;
    const View &w=views[1];
    return LSGCAllowSourceWrapper(true,w.plain,true,w.hidden,w.alpha) ? 2 : 0;
}
static bool visible(const std::vector<View> &v,int start) {
    for (unsigned i=start;i<v.size();i++)
        if (v[i].hidden || !std::isfinite(v[i].alpha) || v[i].alpha<0.01) return false;
    return true;
}
static bool accept(const char *const *names,unsigned n,const std::vector<View> &v) {
    int host=selectedHost(names,n,v);
    if (host<0) return false;
    // Source must itself remain valid; only exact direct wrapper alpha is exempt.
    if (host==2 && (v[0].hidden || v[0].alpha<0.01 || v[1].hidden)) return false;
    return visible(v,host);
}
int main() {
    const char *main[]={"_UIAnimatingLabel","UIView","CSProminentTimeView","CSProminentDisplayView","SBFLockScreenDateView"};
    std::vector<View> v={{false,false,1},{true,false,0},{false,false,1},{false,false,1},{false,false,1}};
    assert(!visible(v,0)); // The old generic label->window gate would reject.
    assert(selectedHost(main,5,v)==2);
    assert(accept(main,5,v)); // Must reach the mask/mount path, not early return.
    v[1].alpha=.005; assert(!accept(main,5,v));
    v[1].alpha=0; v[1].hidden=true; assert(!accept(main,5,v));
    v[1].hidden=false; v[1].plain=false; assert(!accept(main,5,v));
    v[1].plain=true;
    for (unsigned i : {0u,2u,3u,4u}) {
        v[i].hidden=true; assert(!accept(main,5,v)); v[i].hidden=false;
        v[i].alpha=.005; assert(!accept(main,5,v)); v[i].alpha=1;
    }
    const char *date[]={"_UIAnimatingLabel","UIView","CSProminentSubtitleDateView","CSProminentDisplayView","SBFLockScreenDateView"};
    const char *notification[]={"BSUIRelativeDateLabel","UIView","CSProminentTimeView","CSProminentDisplayView","SBFLockScreenDateView"};
    const char *charging[]={"UILabel","UIView","CSProminentTimeView","CSProminentDisplayView","SBFLockScreenDateView"};
    assert(!accept(date,5,v)); assert(!accept(notification,5,v)); assert(!accept(charging,5,v));
    assert(!accept(main,4,v));
    v[1].alpha=1; assert(selectedHost(main,5,v)==0 && accept(main,5,v));
    std::cout << "OK: alpha-zero main clock selects sibling before visibility; ordinary low alpha/hidden/other class/non-main rejected; native fallback unchanged\n";
}
