#include "../LSGCNativeDateLunarPolicy.h"
#include <cassert>
using namespace LSGCNativeDateLunar;
static Input base(const char *text) { return {text,{"SBUILegibilityLabel","SBFLockScreenDateSubtitleDateView","SBFLockScreenDateView"},true,true,0}; }
static Input ios17() { return {"农历九月初十",{"_UIAnimatingLabel","CSProminentSubtitleDateView","CSProminentDisplayView","SBFLockScreenDateView"},true,true,0}; }
int main() {
  Input date=base("2026年10月14日"); assert(identify(date));
  Input lunar=base("农历九月初十"); assert(identify(lunar));
  auto real=ios17(); assert(identify(real));
  for (const char *text : {"12:34", "85%", "电量85％", "正在充电", "充电至明日", "3分钟前", "昨天", ""}) {
    auto reused=real; reused.text=text; assert(!identify(reused));
  }
  auto wrong=real; wrong.chain[1]="CSProminentTimeView"; assert(!identify(wrong));
  wrong=real; wrong.chain.erase(wrong.chain.begin()+1); assert(!identify(wrong));
  wrong=real; wrong.chain[2]="UnverifiedContainer"; assert(!identify(wrong));
  wrong=real; wrong.chain[0]="UIImageView"; assert(!identify(wrong)); // no image-backed claim
  wrong=real; wrong.chain[3]="OtherDateView"; assert(!identify(wrong));
  for (auto input : {date,real}) {
    auto x=input; x.chain.insert(x.chain.begin(),"BSUIRelativeDateLabel"); assert(!identify(x));
    x=input; x.chain.insert(x.chain.begin(),"CSProminentTimeView"); assert(!identify(x));
    x=input; x.tag=7001; assert(!identify(x));
    x=input; x.leaf=false; assert(!identify(x));
    x=input; x.attached=false; assert(!identify(x));
  }
  // This is the very same draw/transition policy invoked by production hooks.
  assert(!suppress(true,false,false,true)); // default OFF
  assert(!suppress(false,true,false,true)); // enabled safety link
  assert(!suppress(true,true,true,true)); // SnapshotText bypass
  assert(suppress(true,true,false,identify(real)));
  bool known=false, state=false; unsigned redraws=0, clears=0;
  auto event=[&](bool next) {
    auto change=transition(known,state,next);
    if(change.invalidate) { ++redraws; ++clears; }
    known=true; state=change.suppressed;
  };
  event(false); assert(redraws==0);
  event(true); event(true); event(true); assert(state && redraws==1 && clears==1);
  event(false); event(false); assert(!state && redraws==2 && clears==2);
  event(true); real.text="12:34"; event(suppress(true,true,false,identify(real)));
  assert(!state && redraws==4); // text reuse restores native
  event(true); event(suppress(false,true,false,true)); assert(!state && redraws==6);
  assert(transition(false,false,true).invalidate); // discovered already enabled
  // Every registered date is purged regardless of current ancestry or hide state.
  for (bool enabled : {false,true}) for (bool gradient : {false,true}) {
    assert(purgeDateOverlay(true,enabled,gradient)==(!enabled || !gradient));
    assert(!purgeDateOverlay(false,enabled,gradient)); // no clock purge
    for (bool hide : {false,true}) {
      assert(suppress(enabled,hide,false,true)==(enabled && hide));
    }
  }
  return 0;
}
