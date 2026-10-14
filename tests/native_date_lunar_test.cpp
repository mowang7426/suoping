#include "../LSGCNativeDateLunarPolicy.h"
#include <cassert>
using namespace LSGCNativeDateLunar;
static Input base(const char *text) { return {text,{"SBUILegibilityLabel","SBFLockScreenDateSubtitleDateView","SBFLockScreenDateView"},true,true,0}; }
int main() {
  Input date=base("2026年10月14日"); assert(identify(date));
  Input lunar=base("农历九月初十"); assert(identify(lunar));
  Input off=base("12:34"); assert(!identify(off));
  Input notification=base("昨天"); notification.chain.insert(notification.chain.begin(),"BSUIRelativeDateLabel"); assert(!identify(notification));
  Input main=base("2026年10月14日"); main.chain={"CSProminentTimeView","SBFLockScreenDateView"}; assert(!identify(main));
  Input pill=date; pill.tag=7001; assert(!identify(pill));
  Input charging=date; charging.text="正在充电"; assert(!identify(charging));
  Input nonleaf=date; nonleaf.leaf=false; assert(!identify(nonleaf));
  Input detached=date; detached.attached=false; assert(!identify(detached));
  return 0;
}
