#include "../LSGCImagePolicy.h"
#include "../LSGCClockScope.h"
#include <cassert>
#include <iostream>
#include <vector>
struct MaskLease {
    const void *native=nullptr,*owned=nullptr,*current=nullptr;
    void acquire(const void *blank) {native=current; owned=blank; current=owned;}
    void systemUpdate(const void *latest) {native=latest; current=latest;}
    void restore() {if(LSGCImageRestoreOwnedMask(current,owned)) current=native; owned=nullptr;}
};
int main() {
    const char *time[]={"UILabel","SBUILegibilityLabel","SBFLockScreenDateView","CSCoverSheetView"};
    const char *date[]={"UILabel","SBUILegibilityLabel","SBFLockScreenDateSubtitleDateView","SBFLockScreenDateView"};
    const char *lunar[]={"UILabel","SBUILegibilityLabel","SBFLockScreenAlternateDateLabel","SBFLockScreenDateSubtitleDateView","SBFLockScreenDateView"};
    const char *notification[]={"UILabel","SBUILegibilityLabel","NCNotificationSeamlessContentView","SBFLockScreenDateView"};
    const char *charging[]={"UILabel","SBFLockScreenDateView"};
    assert(LSGCImageRole(time,4)==1); assert(LSGCImageRole(date,4)==2); assert(LSGCImageRole(lunar,5)==2);
    assert(!LSGCImageRole(notification,4)); assert(!LSGCImageRole(charging,2)); assert(!LSGCImageRole(lunar,4));
    // Both physical trees from the iOS15 diagnostic: shadow is larger in each axis.
    assert(LSGCImageGlyphSize(190,108.5,190,108.5));
    assert(!LSGCImageGlyphSize(214,132.5,190,108.5));
    assert(LSGCImageGlyphSize(155.5,26.5,155.5,26.5));
    assert(!LSGCImageGlyphSize(179.5,50.5,155.5,26.5));
    assert(LSGCImageGlyphSize(107.5,18,107.5,18));
    assert(!LSGCImageGlyphSize(131.5,42,107.5,18));
    // Source UILabel hidden is intentionally absent from the policy. Glyph and
    // wrapper visibility, actual mount, ink and current signature authorize it.
    assert(LSGCImageCommitPolicy(true,true,false,true,true,true,true,true,true));
    assert(LSGCImageCommitPolicy(true,false,true,true,true,true,true,true,true));
    assert(!LSGCImageCommitPolicy(true,false,false,true,true,true,true,true,true));
    assert(!LSGCImageCommitPolicy(false,true,true,true,true,true,true,true,true));
    assert(!LSGCImageCommitPolicy(true,true,true,true,false,true,true,true,true));
    assert(!LSGCImageCommitPolicy(true,true,true,true,true,false,true,true,true));
    assert(!LSGCImageCommitPolicy(true,true,true,true,true,true,false,true,true));
    assert(!LSGCImageCommitPolicy(true,true,true,true,true,true,true,false,true));
    assert(!LSGCImageCommitPolicy(true,true,true,true,true,true,true,true,false));
    int original=1,newest=2,blank=3,external=4;
    MaskLease lease; lease.current=&original; lease.acquire(&blank); lease.restore();
    assert(lease.current==&original);
    lease.acquire(&blank); lease.systemUpdate(&newest); lease.restore(); assert(lease.current==&newest);
    lease.acquire(&blank); lease.current=&external; lease.restore(); assert(lease.current==&external);
    lease.acquire(&blank); lease.restore(); lease.restore(); assert(lease.current==&external);
    // New native contents never enter the lease; suppression changes only mask.
    std::vector<int> nativeFrames={1,2,3}; lease.acquire(&blank); nativeFrames.push_back(4);
    lease.restore(); assert(nativeFrames.back()==4);
    // Same helpers run in Apply: transformed host basis and real cache gates.
    auto basis=LSGCImageMappedBasis(20,-8,20,-6,17,-8,2,.5);
    assert(basis.a==0 && basis.b==4 && basis.c==-1.5 && basis.d==0);
    basis=LSGCImageMappedBasis(100,200,101,200.25,100.5,201,1,1);
    assert(basis.a==1 && basis.b==.25 && basis.c==.5 && basis.d==1);
    int rasterizations=0; bool ink=false,contents=false; int signature=0;
    auto render=[&](int next) {
        if (!LSGCImageCacheReusable(signature==next,ink,contents)) {
            ++rasterizations; signature=next; ink=contents=true;
        }
    };
    render(1); for (int layout=0;layout<100;layout++) render(1);
    assert(rasterizations==1); render(2); assert(rasterizations==2);
    // Native contents/font invalidation must invalidate even identical text.
    ink=false; render(2); assert(rasterizations==3);
    contents=false; render(2); assert(rasterizations==4);
    std::cout<<"image adapter executable policy: strict time/date/lunar trees, glyph/shadow, hidden-source, visibility, mounted commit, independent switches, latest-native rollback PASS\n";
}
