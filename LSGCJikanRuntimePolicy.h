#pragma once
#include <stdbool.h>
#include <math.h>
// Shared production policy; no inferred producer timestamps.
typedef struct { unsigned long long generation; bool active, witnessed; double observed; } LSGCJikanSession;
static inline void LSGCJikanSessionEnd(LSGCJikanSession *s) { s->generation++; s->active=false; s->witnessed=false; s->observed=0; }
static inline bool LSGCJikanFresh(LSGCJikanSession *s, bool changed, bool published, double now) {
    if (!s->active) { s->active=true; s->witnessed=false; }
    // A notification with an unchanged object is NOT proof of recomputation.
    if (changed && !published) s->witnessed=false;
    if (changed && published) { s->witnessed=true; s->observed=now; }
    return s->witnessed && now>=s->observed && now-s->observed<=300;
}
static inline bool LSGCJikanNumbers(double seconds,double target) {
    return isfinite(seconds) && seconds>0 && seconds<=86400 && isfinite(target) && target>=1 && target<=100 && floor(target)==target;
}
