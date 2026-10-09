#include <cassert>
#include <string>
#include <vector>

// Executable model of the production wake state policy. It deliberately models
// resource, submission and lifecycle/input generations separately.
struct WakeState {
  std::string resourceKey, failedResourceKey;
  unsigned resourceGen=0, submissionGen=0, applyCount=0, pending=0;
  bool committed=false, drawChanged=false, redrawRequested=false;
  void input(bool contentChanged) { if (contentChanged) { ++resourceGen; ++submissionGen; resourceKey.clear(); failedResourceKey.clear(); committed=false; } }
  void event() { pending=1; }
  void drain(bool resourceBuildOK, bool hostVisible, bool geometryOK) {
    if (!pending) return;
    pending=0;
    ++applyCount;
    if (!resourceBuildOK) { failedResourceKey=resourceKey; committed=false; return; }
    if (!hostVisible || !geometryOK) { committed=false; ++submissionGen; return; }
    committed=true;
  }
  void draw() { bool before=committed; (void)before; drawChanged=false; redrawRequested=false; }
};

int main() {
  WakeState s;
  // Duplicate lifecycle/layout/visibility events coalesce into one async apply.
  s.event(); s.event(); s.event(); s.drain(true,true,true); assert(s.applyCount==1 && s.committed);
  // draw is a read-only gate: no scheduling, apply, removal, or redraw feedback.
  unsigned applies=s.applyCount, sub=s.submissionGen; s.draw();
  assert(s.applyCount==applies && s.submissionGen==sub && !s.redrawRequested && !s.drawChanged);
  // A temporary host/geometry failure is retryable on the next real input.
  s.event(); s.drain(true,false,false); assert(s.failedResourceKey.empty() && !s.committed);
  s.event(); s.drain(true,true,true); assert(s.committed && s.applyCount==3);
  // A deterministic resource failure is latched, but only by resource key.
  s.committed=false; s.resourceKey="same-content"; s.event(); s.drain(false,true,true);
  assert(s.failedResourceKey=="same-content");
  unsigned failedApply=s.applyCount; s.event(); s.drain(false,true,true); assert(s.applyCount==failedApply+1);
  // Content change clears the resource latch and allows a retry.
  s.input(true); assert(s.failedResourceKey.empty()); s.event(); s.drain(true,true,true); assert(s.committed);
  // Same text does not invalidate warm resources; lifecycle still can retry submission.
  unsigned rg=s.resourceGen; s.input(false); assert(s.resourceGen==rg);
  // Minute update is a real resource/input generation; date is intentionally absent.
  s.input(true); assert(s.resourceGen==rg+1 && s.submissionGen>=2);
  return 0;
}
