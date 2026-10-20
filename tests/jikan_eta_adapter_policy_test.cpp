#include "../LSGCJikanRuntimePolicy.h"
#include "../LSGCChargingPillPolicy.h"
#include <cassert>
int main() {
 LSGCJikanSession s={1,false,false,0};
 assert(!LSGCJikanFresh(&s,true,false,10)); // first read/baseline is not fresh
 assert(!LSGCJikanFresh(&s,false,true,11)); // old object notification
 assert(LSGCJikanFresh(&s,true,true,12));
 assert(LSGCJikanFresh(&s,false,false,312));
 assert(!LSGCJikanFresh(&s,false,true,313)); // unchanged old notification never renews
 assert(LSGCJikanFresh(&s,true,true,314));
 auto generation=s.generation; LSGCJikanSessionEnd(&s);
 assert(s.generation>generation && !s.active && !s.witnessed);
 assert(!LSGCJikanFresh(&s,false,true,315)); // replug cannot reuse old object
 assert(LSGCJikanNumbers(840,95)); assert(!LSGCJikanNumbers(0,95));
 assert(!LSGCJikanNumbers(NAN,95)); assert(!LSGCJikanNumbers(86401,95));
 assert(!LSGCJikanNumbers(840,0)); assert(!LSGCJikanNumbers(840,100.5));
 assert(!LSGCPillAllowed(true,true,1)); assert(!LSGCPillAllowed(true,true,0));
 assert(LSGCPillAllowed(true,true,3));
 LSGCPillQueue q; uint64_t ticket=0; assert(q.enqueue(ticket)); assert(!q.enqueue(ticket)); q.clear(); assert(!q.consume(ticket));
}
