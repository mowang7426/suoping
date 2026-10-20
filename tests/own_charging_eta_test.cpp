#include "../LSGCOwnChargingETACore.h"
#include <cassert>
#include <iostream>
#include <limits>
using namespace OwnETA;
static Input point(double t,double soc=50) {
    Input x; x.now=t; x.wall=1700000000+t; x.soc=soc;
    x.connected=x.charging=true; x.charger="wired20"; return x;
}
static void bucket(History &h,int p,double d) {
    for (int s=1;s<=3;s++) h[p].push_back({d,(uint64_t)s,1700000000});
}
int main() {
    History h; bucket(h,98,60); bucket(h,99,120);
    auto r=estimate(98.5,h,1700000010); assert(r.seconds==150 && !r.coarse && r.coverage==2);
    assert(estimate(99,h,1700000010).seconds==120);
    assert(!std::isfinite(estimate(100,h,1700000010).seconds));
    assert(!std::isfinite(estimate(98,History{},1700000010).seconds));
    History partial; bucket(partial,98,60);
    assert(estimate(98,partial,1700000010,30).seconds==90);
    assert(!std::isfinite(estimate(98,partial,1700000010).seconds));
    assert(!std::isfinite(estimate(99,h,1700000000+31*86400).seconds));
    assert(!std::isfinite(estimate(NAN,h,1700000010).seconds));
    Engine e; Input x=point(0); x.maximum=4000; x.capacity=2000; x.current=2000;
    assert(validCapacity(x)); assert(!std::isfinite(e.consume(x).seconds));
    x.now=30; x.wall+=30; x.capacity=2016.6666667; e.consume(x);
    x.now=60; x.wall+=30; x.capacity=2033.3333333; r=e.consume(x);
    assert(std::isfinite(r.seconds) && r.coarse);
    assert(std::abs(r.seconds-(4000-x.capacity)/2000*3600)<.01);
    Engine noCapacity;
    for(int i=0;i<5;i++) { auto v=point(i*30); v.current=2000; assert(!std::isfinite(noCapacity.consume(v).seconds)); }
    assert(!validCurrent(-2000)); assert(!validCurrent(0)); assert(!validCurrent(INFINITY));
    assert(!validCurrent((double)std::numeric_limits<uint64_t>::max()));
    assert(!validCurrent(4294965296.0)); assert(!validCurrent(-2147483648.0));
    x.maximum=100; assert(!validCapacity(x)); x.maximum=4000000; assert(!validCapacity(x));
    x.maximum=4000; x.capacity=2; assert(!validCapacity(x));
    Engine wrongScale;
    for(int i=0;i<3;i++) { auto v=point(i*30); v.maximum=4000; v.capacity=2000+i*.01; v.current=2000; assert(!std::isfinite(wrongScale.consume(v).seconds)); }
    Engine negative; x=point(0); x.current=-1;
    assert(negative.consume(x).reason=="paused_or_net_discharge");
    Engine learn;
    learn.consume(point(0,50)); learn.consume(point(30,51));
    assert(learn.histories["wired20"][50].empty()); // first half interval excluded
    learn.consume(point(60,51)); learn.consume(point(90,52));
    assert(learn.histories["wired20"][51].size()==1);
    assert(learn.histories["wired20"][51][0].seconds==60);
    learn.consume(point(120,55));
    assert(learn.histories["wired20"][52].empty() && learn.histories["wired20"][53].empty());
    learn.consume(point(150,56)); learn.consume(point(180,57));
    assert(learn.histories["wired20"][56].size()==1); // wait for a new single boundary
    auto pause=point(210,57); pause.charging=false; learn.consume(pause);
    learn.consume(point(240,57)); learn.consume(point(270,58));
    assert(learn.histories["wired20"][57].empty());
    learn.consume(point(400,59)); assert(learn.histories["wired20"][58].empty()); // long gap
    auto change=point(430,60); change.charger="wireless"; learn.consume(change);
    assert(learn.histories["wireless"][59].empty());
    learn.reset(); learn.consume(point(500,60)); learn.consume(point(530,61));
    assert(learn.histories["wired20"][60].empty()); // no restart anchor carried
    Engine tail; tail.consume(point(0,98)); tail.consume(point(30,99));
    auto full=point(60,100); full.full=true; full.charging=false;
    assert(tail.consume(full).reason=="full"); assert(tail.histories["wired20"][99].size()==1);
    // Own history is reusable across sessions without any fabricated capacity.
    Engine restored; restored.histories["wired20"]=h;
    r=restored.consume(point(0,99)); assert(r.seconds==120 && r.source=="own_history");
    auto unplug=point(30,99); unplug.connected=false;
    assert(restored.consume(unplug).reason=="disconnected");
    assert(!acceptGeneration(1,3,true,true)); assert(!acceptGeneration(3,3,true,false));
    assert(!acceptGeneration(3,3,false,true)); assert(acceptGeneration(3,3,true,true));
    Engine observedPaused; observedPaused.consume(point(0,98)); observedPaused.consume(point(30,99));
    auto paused=point(40,99); paused.charging=false; observedPaused.consume(paused);
    observedPaused.consume(full); assert(observedPaused.histories["wired20"][99].empty());
    std::cout << "PASS: OwnETA production-core units, fractional/high SOC, missing data, sign/overflow, physical scale, first interval, jumps, pause, gaps, restart, tail, cross-session history and generation/disconnect gates\n";
}
