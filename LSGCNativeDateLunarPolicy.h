#pragma once
#include <string>
#include <vector>

// Pure policy contract for the native lock-screen date/lunar leaf gate.
namespace LSGCNativeDateLunar {
struct Input { std::string text; std::vector<std::string> chain; bool leaf=false; bool attached=false; int tag=0; };
inline bool explicitDateOrLunar(const std::string &s) {
    if (s.empty() || s.size()>192) return false;
    bool marker=s.find("年")!=std::string::npos || s.find("月")!=std::string::npos ||
      s.find("日")!=std::string::npos || s.find("星期")!=std::string::npos ||
      s.find("农历")!=std::string::npos || s.find("闰")!=std::string::npos ||
      s.find("閏")!=std::string::npos || s.find("周")!=std::string::npos;
    return marker;
}
inline bool exactClass(const std::vector<std::string> &c,const char *name) {
    for (const auto &n:c) { if (n==name) return true; }
    return false;
}
inline bool identify(const Input &in) {
    if (!in.leaf || !in.attached || in.tag==7001 || !explicitDateOrLunar(in.text)) return false;
    if (exactClass(in.chain,"BSUIRelativeDateLabel")) return false;
    // The shared date container is only a scope marker; never hide it.
    return exactClass(in.chain,"SBFLockScreenDateView") &&
      (exactClass(in.chain,"SBFLockScreenDateSubtitleDateView") ||
       exactClass(in.chain,"SBFLockScreenAlternateDateLabel") ||
       exactClass(in.chain,"SBUILegibilityLabel"));
}
}
