#pragma once
#include <string>
#include <vector>
#include <initializer_list>

// Pure policy contract for the native lock-screen date/lunar leaf gate.
namespace LSGCNativeDateLunar {
struct Input { std::string text; std::vector<std::string> chain; bool leaf=false; bool attached=false; int tag=0; };
inline bool explicitDateOrLunar(const std::string &s) {
    if (s.empty() || s.size()>192) return false;
    // Conservative: never treat a reused battery/time/prompt leaf as a date.
    for (const char *token : {"%", "％", ":", "：", "充电", "电量", "分钟", "小时", "前", "后"})
        if (s.find(token)!=std::string::npos) return false;
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
    if (exactClass(in.chain,"BSUIRelativeDateLabel") ||
        exactClass(in.chain,"CSProminentTimeView")) return false;
    // Exact ordered iOS 17 subtitle ancestry, not generic ProminentDisplay/time.
    bool prominent=false;
    for (size_t i=0; i+3<in.chain.size(); ++i) {
        if (in.chain[i]=="_UIAnimatingLabel" &&
            in.chain[i+1]=="CSProminentSubtitleDateView" &&
            in.chain[i+2]=="CSProminentDisplayView" &&
            in.chain[i+3]=="SBFLockScreenDateView") prominent=true;
    }
    // The shared date container is only a scope marker; never hide it.
    return exactClass(in.chain,"SBFLockScreenDateView") &&
      (prominent || exactClass(in.chain,"SBFLockScreenDateSubtitleDateView") ||
       exactClass(in.chain,"SBFLockScreenAlternateDateLabel") ||
       exactClass(in.chain,"SBUILegibilityLabel"));
}
inline bool suppress(bool enabled, bool hide, bool rendering, bool identified) {
    return enabled && hide && !rendering && identified;
}
struct Transition { bool suppressed; bool invalidate; };
inline Transition transition(bool known, bool previous, bool next) {
    return {next, (known && previous!=next) || (!known && next)};
}
inline bool purgeDateOverlay(bool registeredDate, bool enabled, bool dateGradient) {
    return registeredDate && (!enabled || !dateGradient);
}
}
