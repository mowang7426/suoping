#ifndef LSGC_WAKE_STRATEGY_H
#define LSGC_WAKE_STRATEGY_H
#include <string>
#include <cstddef>

// Production-shared, UIKit-free wake/submission policy.  Tweak.xm owns the
// resource objects; this type owns only immutable-key and edge semantics.
inline bool LSGCShouldQueueWake(bool pending) { return !pending; }

struct LSGCSetterGuard {
  unsigned depth;
  LSGCSetterGuard() : depth(0) {}
  bool enter() { bool outer=depth==0; ++depth; return outer; }
  void leave() { if (depth) --depth; }
};

struct LSGCWakeSnapshot { std::size_t resourceGeneration, submissionGeneration; std::string key; };
// All four cache products (image, canvas, outline path, key) are accepted only
// when they describe one immutable build. UIKit objects remain owned by Tweak.xm.
inline bool LSGCResourceBindingConsistent(const std::string& key, std::size_t generation,
    const std::string& cachedKey, std::size_t cachedGeneration,
    double canvasWidth, double canvasHeight, bool pathValid, bool imageValid) {
  return imageValid && pathValid && canvasWidth>0 && canvasHeight>0 &&
         !key.empty() && key==cachedKey && generation==cachedGeneration;
}
struct LSGCWakePolicy {
  std::size_t resourceGeneration, submissionGeneration;
  std::string failedKey;
  bool committed;
  LSGCWakePolicy() : resourceGeneration(0), submissionGeneration(0), committed(false) {}
  LSGCWakeSnapshot begin(const std::string& key) const {
    LSGCWakeSnapshot x = {resourceGeneration, submissionGeneration, key}; return x;
  }
  bool failedEarly(const LSGCWakeSnapshot& x) const {
    return !x.key.empty() && failedKey==x.key && x.resourceGeneration==resourceGeneration;
  }
  bool currentResource(const LSGCWakeSnapshot& x, const std::string& key) const {
    return x.resourceGeneration==resourceGeneration && x.key==key;
  }
  bool currentSubmission(const LSGCWakeSnapshot& x) const {
    return x.submissionGeneration==submissionGeneration;
  }
  void invalidate() { ++resourceGeneration; ++submissionGeneration; failedKey.clear(); committed=false; }
  void failResource(const LSGCWakeSnapshot& x) { if (currentResource(x,x.key)) { failedKey=x.key; committed=false; } }
  void failTransient() { ++submissionGeneration; committed=false; }
  // Returns true only on the committed -> submitted edge.
  bool commit(const LSGCWakeSnapshot& x) {
    if (failedEarly(x) || !currentResource(x,x.key) || !currentSubmission(x)) return false;
    bool edge=!committed; committed=true; failedKey.clear(); return edge;
  }
  // Returns true only when a previously committed native backing store needs
  // one recovery draw. Repeated failures are deliberately no-ops.
  bool removeQuiet() { bool edge=committed; committed=false; return edge; }
};
#endif
