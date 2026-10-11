#include "../LSGCChargingPillPolicy.h"
#include <cassert>
#include <string>
struct Capsule {
    LSGCPillQueue queue;
    bool enabled=true, on=true, visible=true, mounted=false;
    int state=2;
    std::string cache, label;
    void clear() { queue.clear(); mounted=false; label.clear(); cache.clear(); }
    bool allowed() { return LSGCPillAllowed(enabled,on,state) && visible; }
    bool event(uint64_t &ticket) {
        if (!allowed()) { clear(); return false; }
        return queue.enqueue(ticket);
    }
    void run(uint64_t ticket) {
        if (!queue.consume(ticket)) return;
        if (!allowed()) { clear(); return; }
        std::string text="正在充电";
        if (LSGCPillNeedsText(!mounted,cache==text,label==text)) label=text;
        cache=text; mounted=true;
        assert(!label.empty());
    }
};
int main() {
    for (int start : {2,3}) for (int end : {0,1}) {
        Capsule p; uint64_t t=0; p.state=start;
        assert(p.event(t)); p.run(t); assert(p.mounted);
        p.state=end; assert(!p.event(t)); assert(!p.mounted && p.label.empty());
    }
    Capsule p; uint64_t old=0, fresh=0;
    assert(p.event(old)); assert(!p.event(fresh)); // duplicate event coalesced
    p.state=1; p.event(fresh); p.state=2; assert(p.event(fresh));
    p.run(old); assert(!p.mounted); p.run(fresh); assert(p.mounted);
    p.clear(); assert(p.event(old)); p.state=0; p.run(old); assert(!p.mounted); // execution reread
    p.state=2; assert(p.event(fresh)); p.run(fresh); assert(p.mounted);
    p.mounted=false; p.label.clear(); // weak view expired, cached text identical
    assert(p.event(fresh)); p.run(fresh); assert(!p.label.empty());
    p.label.clear(); assert(p.event(fresh)); p.run(fresh); assert(!p.label.empty());
    for (int gate=0; gate<3; ++gate) {
        Capsule q; uint64_t t=0; assert(q.event(t)); q.run(t);
        if(gate==0) q.enabled=false;
        if(gate==1) q.on=false;
        if(gate==2) q.visible=false;
        assert(!q.event(t)); assert(!q.mounted); q.run(t); assert(!q.mounted);
    }
    assert(!LSGCPillAllowed(false,true,2)); assert(!LSGCPillAllowed(true,false,3));
}
