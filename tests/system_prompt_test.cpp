#include "../LSGCPromptPolicy.h"
#include <cassert>
#include <iostream>
using namespace LSGCPrompt;
struct LabelFixture {
    Input input{"目前电量 80%",{"UILabel","UIView","CSProminentDisplayView","SBFLockScreenDateView","UIView","CSCoverSheetView"}};
    State state;
    bool enabled=true,hide=false,hidden=false;
    double alpha=1;
    unsigned redraws=0;
    void event() { if(state.update(identify(input),enabled,hide)) ++redraws; }
    bool glyph(bool rendering=false) const { return rendering || !(enabled && hide && identify(input).kind!=Kind::none); }
};
int main() {
    LabelFixture l; l.event(); assert(l.glyph() && l.redraws==0);
    l.hide=true; l.event(); assert(!l.glyph() && l.redraws==1 && l.state.suppressions==1);
    for(int i=0;i<1000;++i) { l.event(); }
    assert(l.redraws==1);
    assert(l.glyph(true)); // SnapshotText bypass, not a suppression/update loop.
    l.alpha=.35; l.hidden=true; l.event(); l.hide=false; l.event();
    assert(l.glyph() && l.alpha==.35 && l.hidden && l.state.restores==1);
    l.hide=true; l.event(); l.input.text="农历九月初十 星期六"; l.event();
    assert(l.glyph() && !l.state.suppressed && l.state.restores==2);
    l.input.text="目前电量 80%"; l.event(); l.enabled=false; l.event(); assert(l.glyph() && !l.state.suppressed);
    l.enabled=true; l.event(); l.input.attached=false; l.event(); assert(l.glyph());
    l.input.attached=true; l.event(); assert(!l.glyph());
    for(const char *text:{"目前电量 0%","当前电量： 100％","目 前 電 量 ８０%"}) {
        l.input.text=text; l.event();
        if(l.input.text.find("８")!=std::string::npos) assert(l.glyph()); else assert(!l.glyph());
    }
    for(const char *text:{"目前電量 80%","當前電量 42%","正在充电 81%","充電中：80%","Current battery level: 80%","Charging 80%","80% Charged","目前电量\xc2\xa0 80\xe2\x80\xaf%"}) { l.input.text=text; l.event(); assert(!l.glyph()); }
    for(const char *text:{"目前电量 101%","目前电量 -1%","目前电量 80% 更多","收到消息：目前电量 80%","Charging","今天电量很多","2026年10月10日","九月初十","12:34","80%","目前电量 1.5%"}) { l.input.text=text; l.event(); assert(l.glyph()); }
    l.input.text="目前电量 80%";
    l.input.owned=true; l.event(); assert(l.glyph()); l.input.owned=false;
    for(const char *excluded:{"LSGCOverlayView","CSProminentTimeView","NCNotificationSeamlessContentView","CSCombinedListView"}) {
        l.input.chain.insert(l.input.chain.begin()+1,excluded); l.event(); assert(l.glyph());
        l.input.chain.erase(l.input.chain.begin()+1); l.event(); assert(!l.glyph());
    }
    auto saved=l.input.chain; l.input.chain={"UILabel","UIView","AppWindow"}; l.event(); assert(l.glyph());
    l.input.chain={"UILabel","UIView","CSCoverSheetView"}; l.event(); assert(l.glyph());
    l.input.chain=saved; l.input.leaf=false; l.event(); assert(l.glyph());
    l.input.leaf=true; l.input.chain={"UILabel","CSTeachableMomentsContainerView","CSCoverSheetView"};
    l.input.text="向上滑动以解锁"; l.event(); assert(!l.glyph());
    l.input.text="swipe up to open"; l.event(); assert(!l.glyph());
    l.input.text="通知：向上滑动以解锁"; l.event(); assert(l.glyph());
    std::cout<<"PASS production prompt identity, UILabel ancestor scope, full phrases/percent, lifecycle/reuse, unchanged-event idempotence, enabled/default-off, system alpha/hidden ownership, snapshot bypass\n";
}
