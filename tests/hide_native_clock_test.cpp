#include <cassert>
#include "../LSGCHideNativeClock.h"
int main() {
  LSGCHideNativeClockPolicy p;
  p.sourceCreated(true,false); assert(!p.suppression && p.nativeDraw && p.redrawRequests==0);
  p.configure(true,true); assert(p.suppression && !p.nativeDraw && p.redrawRequests==1);
  p.configure(true,true); assert(p.redrawRequests==1); // duplicate event no loop
  p.sourceCreated(true,true); assert(!p.suppression); // date/lunar unaffected
  p.sourceCreated(true,false); assert(p.suppression);
  p.configure(false,true); assert(!p.suppression && p.nativeDraw); // enabled linkage restores
  p.configure(false,true); assert(p.redrawRequests==4);
  p.configure(true,true); assert(p.suppression);
  p.sourceDestroyed(); assert(!p.suppression && p.nativeDraw);
  return 0;
}
