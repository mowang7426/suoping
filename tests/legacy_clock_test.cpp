#include "../LSGCLegacyClock.h"
#include "../LSGCClockSafety.h"
#include <cassert>
#include <iostream>
int main() {
    const char *legacy[]={"UILabel","SBUILegibilityLabel","SBFLockScreenDateView","UIView"};
    assert(LSGCLegacyClockKind(legacy,4)==1);
    const char *direct[]={"UILabel","SBFLockScreenDateView","UIView"};
    assert(LSGCLegacyClockKind(direct,3)==2); // Candidate, never proof of primary role.
    const char *wrapper[]={"SBUILegibilityLabel","SBFLockScreenDateView"};
    assert(LSGCLegacyClockKind(wrapper,2)==2);
    const char *date[]={"UILabel","SBUILegibilityLabel","SBFLockScreenDateSubtitleDateView","SBFLockScreenDateView"};
    const char *lunar[]={"UILabel","SBUILegibilityLabel","SBFLockScreenAlternateDateLabel","SBFLockScreenDateSubtitleDateView","SBFLockScreenDateView"};
    const char *notification[]={"UILabel","SBUILegibilityLabel","NCNotificationView","SBFLockScreenDateView"};
    const char *charging[]={"UILabel","CSChargingView","SBFLockScreenDateView"};
    const char *fake[]={"UILabel","FakeLegibilityLabel","SBFLockScreenDateView"};
    assert(!LSGCLegacyClockKind(date,4)); assert(!LSGCLegacyClockKind(lunar,5));
    assert(!LSGCLegacyClockKind(notification,4)); assert(!LSGCLegacyClockKind(charging,3));
    assert(!LSGCLegacyClockKind(fake,3)); assert(!LSGCLegacyClockKind(legacy,2));
    for (unsigned bits=0;bits<16;bits++) {
        LSGCLegacyReadiness r={bool(bits&1),bool(bits&2),bool(bits&4),bool(bits&8)};
        assert(LSGCCanRenderLegacy(r)==(bits==15));
    }
    // Both families share disabled/font/mask/visibility/attachment/current fallback.
    for (unsigned bits=0;bits<256;bits++) {
        LSGCClockReadiness r={bool(bits&1),bool(bits&2),bool(bits&4),bool(bits&8),bool(bits&16),bool(bits&32),bool(bits&64),1,bool(bits&128)};
        assert(LSGCCanReplaceClock(r)==(bits==255));
    }
    const char *prominent[]={"_UIAnimatingLabel","CSProminentTimeView","UIView","CSProminentDisplayView","SBFLockScreenDateView"};
    assert(LSGCMainClockChain(prominent,5)); assert(!LSGCLegacyClockKind(prominent,5));
    assert(LSGCClockWrapperIndex(prominent,5)==2);
    std::cout << "OK: both hierarchy families, exact legacy candidates, date/lunar/notification/charging exclusion, image/ambiguous/unhooked fallback, disabled/failure matrices; prominent wrapper unchanged\n";
}
