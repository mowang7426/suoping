#pragma once
#include <string>
#include <vector>
#include <cctype>
namespace LSGCPrompt {
inline std::string normalize(std::string s) {
    for (const auto &p : std::vector<std::pair<std::string,std::string>>{{"％","%"},{"：",":"},{"　",""},{"\xc2\xa0",""},{"\xe2\x80\xaf",""},{"\xe2\x80\x8e",""},{"\xe2\x80\x8f",""}}) {
        size_t i=0; while ((i=s.find(p.first,i))!=std::string::npos) { s.replace(i,p.first.size(),p.second); i+=p.second.size(); }
    }
    std::string r; for (unsigned char c:s) if (!std::isspace(c)) r+=char(c<128?std::tolower(c):c); return r;
}
inline bool percentage(const std::string &s) {
    if (s.size()<2 || s.size()>4 || s.back()!='%') return false;
    unsigned n=0; for (size_t i=0;i+1<s.size();++i) { if(s[i]<'0'||s[i]>'9') return false; n=n*10+unsigned(s[i]-'0'); }
    return n<=100;
}
inline bool charging(const std::string &input) {
    const auto s=normalize(input);
    for (const auto &prefix : {"目前电量","当前电量","目前電量","當前電量","电池电量","電池電量","正在充电","正在充電","充电中","充電中","currentbatterylevel","batterylevel","batterycharging","charging"}) {
        const std::string p=prefix;
        if (s.compare(0,p.size(),p)) continue;
        auto tail=s.substr(p.size()); if (!tail.empty()&&tail[0]==':') tail.erase(0,1);
        if (percentage(tail)) return true;
    }
    for (const auto &suffix : {"charged","充电","充電","已充电","已充電"}) {
        std::string p=suffix; if (s.size()>p.size() && s.compare(s.size()-p.size(),p.size(),p)==0 && percentage(s.substr(0,s.size()-p.size()))) return true;
    }
    return false;
}
enum class Kind { none, charging, unlock };
struct Input { std::string text; std::vector<std::string> chain; bool attached=true, label=true, leaf=true, owned=false; };
struct Result { Kind kind=Kind::none; const char *reason="unknown-text"; };
inline Result identify(const Input &in) {
    if(!in.label || !in.leaf) return {Kind::none,"not-leaf-label"};
    if(!in.attached) return {Kind::none,"detached"};
    if(in.owned) return {Kind::none,"plugin-owned"};
    bool cover=false,date=false,unlock=false;
    for(const auto &n:in.chain) {
        if(n.compare(0,4,"LSGC")==0) return {Kind::none,"plugin-owned"};
        if(n.compare(0,2,"NC")==0 || n=="CSCombinedListView" || n.compare(0,14,"CSNotification")==0) return {Kind::none,"notification"};
        if(n=="CSProminentTimeView") return {Kind::none,"main-time"};
        cover|=n=="CSCoverSheetView";
        date|=n=="SBFLockScreenDateView";
        unlock|=n=="CSTeachableMomentsContainerView";
    }
    if(!cover) return {Kind::none,"no-known-coversheet"};
    if(charging(in.text)) return date ? Result{Kind::charging,"matched-complete-charge-percent"} : Result{Kind::none,"no-known-date-host"};
    const auto s=normalize(in.text);
    if(unlock && (s=="向上滑动解锁" || s=="向上滑动以解锁" || s=="向上滑動以解鎖" || s=="向上滑動解鎖" || s=="swipeuptounlock" || s=="swipeuptoopen")) return {Kind::unlock,"matched-complete-unlock"};
    return {Kind::none,"unknown-text-or-date"};
}
struct State {
    bool suppressed=false;
    unsigned suppressions=0,restores=0;
    bool update(Result r,bool enabled,bool hide) {
        bool next=enabled && hide && r.kind!=Kind::none;
        if(next==suppressed) return false;
        suppressed=next; if(next) ++suppressions; else ++restores; return true;
    }
};
}
