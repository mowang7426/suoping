#include "../LSGCClockLifecycle.h"
#include "../LSGCClockSafety.h"
#include <cassert>
#include <limits>
#include <iostream>

// A deterministic adapter for the same production transition/commit functions.
// No UIKit imitation by source matching: each event runs policy, builds or
// remounts, and then executes the glyph draw contract before the next event.
struct Clock {
    bool enabled=true, hooks=true, connected=true, sourceHidden=false;
    bool font=true, geometry=true, maskSuccess=true, mountSuccess=true;
    bool cached=false, committed=false, attached=false;
    int text=1, cachedText=0, failedText=0, host=1, attachedHost=0;
    int builds=0, hits=0, restores=0, native=0, suppressed=0;
    double modelAlpha=1, modelOpacity=1, presentationOpacity=1;
    bool commonHidden=false, commonOffscreen=false;
    void event() {
        bool valid=connected && !sourceHidden && !commonHidden && !commonOffscreen && host &&
            LSGCClockCommonOpacityValid(modelAlpha,modelOpacity,presentationOpacity);
        LSGCClockInput in={enabled,hooks,valid,font,geometry,cached,
                          cachedText==text,failedText==text};
        LSGCClockAction action=LSGCClockNext(in);
        if (action==LSGCClockBuild) {
            ++builds; cached=false; failedText=text;
            if (maskSuccess) { cached=true; cachedText=text; failedText=0; }
        } else if (action==LSGCClockReuse) ++hits;
        attached=action!=LSGCClockNative && cached && cachedText==text && mountSuccess;
        attachedHost=attached ? host : 0;
        LSGCClockReadiness ready={enabled,font,cached,attached,valid,geometry,
                                  cachedText==text,1,hooks};
        bool next=LSGCClockCommit(action,LSGCCanReplaceClock(ready));
        if (committed && !next) ++restores;
        committed=next;
        if (!committed) { attached=false; attachedHost=0; }
    }
    void draw() {
        event(); // production LabelDraw / override calls synchronous Schedule
        if (committed) ++suppressed; else ++native;
        assert(!committed || (attached && cached && font && enabled && hooks));
        assert(!committed || attachedHost==host);
    }
};
int main() {
    Clock c;
    // First uncached draw: build+attach+commit before glyph suppression.
    c.draw(); assert(c.builds==1 && c.native==0 && c.suppressed==1);
    // Power off: safety fallback detaches layers but preserves valid ink.
    c.commonHidden=true; c.commonOffscreen=true;
    c.modelAlpha=0; c.modelOpacity=0; c.presentationOpacity=0;
    c.event(); assert(!c.committed && c.cached && c.builds==1);
    c.commonHidden=false; c.commonOffscreen=false;
    c.modelAlpha=1; c.modelOpacity=1;
    const double wake[]={0,0.001,0.008,0.1,0.5,1};
    for (double a:wake) { c.presentationOpacity=a; c.draw(); }
    assert(c.native==0 && c.builds==1 && c.hits>=6 && c.restores==1);
    // Source hidden is NEVER made visible by using the sibling host.
    c.sourceHidden=true; c.draw(); assert(!c.committed && !c.attached && c.cached);
    c.sourceHidden=false; c.draw(); assert(c.committed && c.builds==1);
    // Detached window, reattach/new host: no stale old-host suppression.
    c.connected=false; c.draw(); assert(!c.committed && c.attachedHost==0);
    c.connected=true; c.host=2; c.draw(); assert(c.attachedHost==2 && c.builds==1);
    c.host=3; c.mountSuccess=false; c.draw(); assert(!c.committed && !c.attached);
    c.mountSuccess=true; c.draw(); assert(c.committed && c.attachedHost==3);
    // Font failure must restore native, without wasting a bitmap rebuild.
    c.font=false; int before=c.builds; c.draw(); c.draw();
    assert(!c.committed && c.builds==before);
    c.font=true; c.draw(); assert(c.committed && c.builds==before);
    // Disabled setting, invalid geometry, missing hooks: native-safe, warm ink.
    c.enabled=false; c.draw(); assert(!c.committed && c.cached);
    c.enabled=true; c.draw(); assert(c.committed && c.builds==before);
    c.geometry=false; c.draw(); assert(!c.committed);
    c.geometry=true; c.hooks=false; c.draw(); assert(!c.committed);
    c.hooks=true; c.draw(); assert(c.committed);
    // Text/font/size signature change cannot use old ink; mask failure bounded.
    ++c.text; c.maskSuccess=false; c.draw(); before=c.builds;
    for (int n=0;n<10;++n) c.draw();
    assert(!c.committed && !c.cached && c.builds==before);
    ++c.text; c.maskSuccess=true; c.draw(); assert(c.committed && c.builds==before+1);
    // Unlock / notification model clipping falls back; reentry reuses ink.
    before=c.builds;
    for (int n=0;n<20;++n) {
        c.commonOffscreen=n%2; c.commonHidden=n%3==0;
        c.presentationOpacity=n%3 ? 0.5 : 0;
        c.draw(); assert(c.committed==(!c.commonHidden && !c.commonOffscreen));
        assert(c.cached && (!c.committed || c.attachedHost==3));
    }
    assert(c.builds==before);
    c.modelAlpha=std::numeric_limits<double>::quiet_NaN(); c.draw();
    assert(!c.committed);
    Clock cold; cold.font=false; cold.draw(); assert(cold.native==1 && cold.builds==0);
    assert(!LSGCClockCommit(LSGCClockNative,true));
    assert(!LSGCClockCommit(LSGCClockReuse,false));
    std::cout << "PASS: first draw, wake warm cache, source hidden, host swap, font/mask failure, disabled, unlock/notification, atomic native fallback\n";
}
