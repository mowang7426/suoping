#include "../LSGCWakeStrategy.h"
#include <cassert>
#include <string>

static LSGCWakeSnapshot snap(LSGCWakePolicy& p,const char* k){return p.begin(k);}
int main() {
  bool pending=false; unsigned queued=0;
  for (int i=0;i<100000;i++) if (LSGCShouldQueueWake(pending)) { pending=true; ++queued; }
  assert(queued==1); pending=false; assert(LSGCShouldQueueWake(pending));
  LSGCSetterGuard g;
  bool privateOuter=g.enter(); bool superOuter=g.enter(); // private override calls super
  assert(privateOuter && !superOuter); g.leave(); g.leave(); assert(g.depth==0);
  bool noSuperOuter=g.enter(); assert(noSuperOuter); g.leave(); // override without super
  bool exceptionOuter=g.enter(); assert(exceptionOuter); g.leave(); assert(g.depth==0); // finally path

  LSGCWakePolicy p;
  auto a=snap(p,"10:21");
  assert(!p.failedEarly(a));
  assert(p.commit(a));                         // first native submission edge
  assert(!p.commit(a));                        // duplicate apply does not redraw
  assert(p.removeQuiet());                     // committed -> uncommitted once
  assert(!p.removeQuiet());
  assert(p.commit(a));                         // transient retry can recover
  p.failTransient();
  assert(!p.currentSubmission(a));             // stale submission is discarded
  assert(!p.commit(a));
  auto b=snap(p,"10:22");
  assert(p.commit(b));
  p.failResource(b);
  assert(p.failedEarly(b));                    // production failed-key early return
  assert(!p.commit(b));
  for (int i=0;i<10000;i++) { auto x=snap(p,"10:22"); assert(p.failedEarly(x)); }
  p.invalidate();                               // real content generation clears latch
  auto c=snap(p,"10:22"); assert(!p.failedEarly(c)); assert(p.commit(c));
  auto old=c; p.invalidate();                   // stale resource cannot install
  assert(!p.currentResource(old,"10:22"));
  auto d=snap(p,"10:23"); assert(p.commit(d));
  assert(LSGCResourceBindingConsistent("10:23",p.resourceGeneration,"10:23",p.resourceGeneration,120,40,true,true));
  assert(!LSGCResourceBindingConsistent("10:23",p.resourceGeneration,"10:23",p.resourceGeneration,120,40,false,true));
  assert(!LSGCResourceBindingConsistent("10:23",p.resourceGeneration,"10:22",p.resourceGeneration,120,40,true,true));
  assert(!LSGCResourceBindingConsistent("10:23",p.resourceGeneration,"10:23",p.resourceGeneration-1,120,40,true,true));
  // Repeated draw/events are observational only; no policy edge is created.
  unsigned redraws=0;
  for (int i=0;i<1000;i++) { assert(!p.commit(d)); }
  assert(redraws==0 && p.committed);
  return 0;
}
