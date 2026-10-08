#include "../LSGCClockSafety.h"
#include <cassert>
#include <cmath>
#include <iostream>
int main() {
    for (unsigned bits=0;bits<256;bits++) {
        LSGCClockReadiness r={bool(bits&1),bool(bits&2),bool(bits&4),bool(bits&8),bool(bits&16),bool(bits&32),bool(bits&64),0.32,bool(bits&128)};
        assert(LSGCCanReplaceClock(r)==(bits==255));
    }
    LSGCClockReadiness r={true,true,true,true,true,true,true,0,true};
    assert(!LSGCCanReplaceClock(r));
    r.opacity=NAN; assert(!LSGCCanReplaceClock(r));
    r.opacity=0.009; assert(!LSGCCanReplaceClock(r));
    r.opacity=0.32; assert(LSGCCanReplaceClock(r));
    r.hookInstalled=false; assert(!LSGCCanReplaceClock(r)); r.hookInstalled=true;
    // A successful commit followed by font/mask/host loss must fall back.
    r.fontReady=false; assert(!LSGCCanReplaceClock(r)); r.fontReady=true;
    r.maskHasInk=false; assert(!LSGCCanReplaceClock(r)); r.maskHasInk=true;
    r.attached=false; assert(!LSGCCanReplaceClock(r)); r.attached=true;
    r.current=false; assert(!LSGCCanReplaceClock(r));
    std::cout << "OK: 256 readiness combinations, transparent/NaN opacity, invalidation fallback\n";
}
