#include "../LSGCClockRender.h"
#include "../LSGCClockSafety.h"
#include <cassert>
#include <iostream>
int main() {
    for (double w : {30.,140.,400.}) for (double h : {30.,100.,240.})
    for (double weight : {0.,.8,4.}) for (double edge : {0.,.5,1.5,6.}) {
        auto c=LSGCFullClockCanvas(100,40,w,h,weight,edge);
        double left=(c.width-w)/2,top=(c.height-h)/2;
        assert(c.width>=100 && c.height>=40);
        assert(left>=weight+edge+2 && top>=weight+edge+2);
        // Executable coverage model: outline expands rectangular ink; the
        // extra AA margin must leave every bitmap border pixel transparent.
        unsigned fill=0,ring=0,border=0;
        for (int y=0;y<int(c.height);y++) for (int x=0;x<int(c.width);x++) {
            auto coverage=[&](double outset) {
                double l=c.width/2-w/2-outset,r=c.width/2+w/2+outset;
                double t=c.height/2-h/2-outset,b=c.height/2+h/2+outset;
                return std::fmax(0,std::fmin(x+1.,r)-std::fmax(double(x),l))*
                       std::fmax(0,std::fmin(y+1.,b)-std::fmax(double(y),t));
            };
            double core=coverage(weight),outer=coverage(weight+edge);
            fill+=core>0; ring+=outer-core>1e-8;
            if (outer>0 && (!x || !y || x+1==int(c.width) || y+1==int(c.height))) border++;
        }
        assert(fill>0 && border==0);
        if (edge>=.5) assert(ring>0);
    }
    assert(LSGCClockFillOpacity(.32)==.85);
    assert(LSGCClockFillOpacity(1)==1);
    assert(LSGCClockFillOpacity(0)==0);
    LSGCClockReadiness r={true,true,true,true,true,true,true,LSGCClockFillOpacity(1),true};
    assert(LSGCCanReplaceClock(r));
    r.opacity=LSGCClockFillOpacity(0); assert(!LSGCCanReplaceClock(r));
    r.opacity=1; r.attached=false; assert(!LSGCCanReplaceClock(r));
    r.attached=true; r.maskHasInk=false; assert(!LSGCCanReplaceClock(r));
    std::cout << "OK: 108 full canvases, solid fill, nonzero outline, transparent bitmap borders, fallback\n";
}
