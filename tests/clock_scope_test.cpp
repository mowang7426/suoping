#include "../LSGCClockScope.h"
#include <cassert>
#include <iostream>
int main() {
    const char *main[]={"_UIAnimatingLabel","CSProminentTimeView","UIView","BSUIVibrancyEffectView","CSProminentDisplayView","SBFLockScreenDateView","CSCoverSheetView"};
    assert(LSGCMainClockChain(main,7));
    assert(!LSGCMainClockChain(main,0));
    assert(!LSGCMainClockChain(main,5));
    const char *date[]={"_UIAnimatingLabel","CSProminentSubtitleDateView","CSProminentDisplayView","SBFLockScreenDateView"};
    assert(!LSGCMainClockChain(date,4));
    const char *notification[]={"BSUIRelativeDateLabel","CSCombinedListView","CSCoverSheetView"};
    assert(!LSGCMainClockChain(notification,3));
    const char *charging[]={"UILabel","CSProminentTimeView","CSProminentDisplayView","SBFLockScreenDateView"};
    assert(!LSGCMainClockChain(charging,4));
    const char *fake[]={"_UIAnimatingLabel","FakeProminentTimeView","CSProminentDisplayView","SBFLockScreenDateView"};
    assert(!LSGCMainClockChain(fake,4));
    const char *wrongOrder[]={"_UIAnimatingLabel","CSProminentDisplayView","CSProminentTimeView","SBFLockScreenDateView"};
    assert(!LSGCMainClockChain(wrongOrder,4));
    const char *mixed[]={"_UIAnimatingLabel","CSProminentTimeView","CSProminentSubtitleDateView","CSProminentDisplayView","SBFLockScreenDateView"};
    assert(!LSGCMainClockChain(mixed,5));
    std::cout << "OK: exact native clock chain; notifications, charging, subtitle, missing/root/order/substring rejected\n";
}
