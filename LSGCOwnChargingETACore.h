#pragma once
// Independently authored, portable production math/state machine. Seconds, mAh, mA.
#include <array>
#include <vector>
#include <map>
#include <string>
#include <algorithm>
#include <cmath>
#include <cstdint>
namespace OwnETA {
struct Tick { double seconds; uint64_t session; double wall; };
using History = std::array<std::vector<Tick>,100>;
struct Input {
    double now=0, wall=0, soc=-1, maximum=NAN, capacity=NAN, current=NAN;
    bool connected=false, charging=false, full=false;
    std::string charger="unknown";
};
struct Result {
    double seconds=NAN; int coverage=0, needed=0, samples=0; bool coarse=false;
    std::string reason="learning", source="none";
};
inline bool validCurrent(double i) { return std::isfinite(i) && i>=50 && i<=10000; }
inline bool validCapacity(const Input &x) {
    return std::isfinite(x.maximum) && x.maximum>=500 && x.maximum<=15000 &&
        std::isfinite(x.capacity) && x.capacity>=0 && x.capacity<=x.maximum &&
        x.soc>=0 && x.soc<=100 && std::abs(x.capacity/x.maximum*100-x.soc)<=8;
}
inline double bucketValue(const std::vector<Tick> &v, double wall, int &samples) {
    std::vector<double> values; std::vector<uint64_t> sessions;
    for (const auto &t:v) if (std::isfinite(t.seconds) && t.seconds>=10 && t.seconds<=3600 &&
        std::isfinite(t.wall) && wall>=t.wall && wall-t.wall<=30*86400) {
        values.push_back(t.seconds);
        if (std::find(sessions.begin(),sessions.end(),t.session)==sessions.end()) sessions.push_back(t.session);
    }
    samples=(int)values.size();
    if (values.size()<3 || sessions.size()<3) return NAN;
    std::sort(values.begin(),values.end());
    double median=values[values.size()/2];
    if (values.back()>median*2 || values.front()<median*.5) return NAN;
    return median;
}
inline Result estimate(double soc,const History &h,double wall,double baseline=NAN) {
    Result r;
    if (!std::isfinite(soc) || soc<0 || soc>=100) return r;
    double total=0; bool missing=false;
    for (int p=(int)std::floor(soc);p<100;++p) {
        int samples=0; double d=bucketValue(h[p],wall,samples); r.samples+=samples; ++r.needed;
        if (std::isfinite(d)) ++r.coverage;
        else { d=baseline; r.coarse=true; }
        if (!std::isfinite(d) || d<=0) missing=true;
        else total+=d*(p+1-std::max((double)p,soc));
    }
    if (!missing && std::isfinite(total) && total>0 && total<=7*86400) {
        r.seconds=total; r.source=r.coarse?"own_history+current_linear":"own_history";
        r.reason=r.coarse?"coarse_current_no_CV_guarantee":"history_estimate";
    } else r.coarse=false;
    return r;
}
class Engine {
    double lastTime=NAN, anchorTime=NAN; int lastSOC=-1; bool boundary=false;
    std::string active; std::vector<Input> currents;
public:
    std::map<std::string,History> histories;
    uint64_t serial=0, session=0; double batteryMaximum=NAN;
    bool dirty=false;
    void reset() { lastTime=NAN; anchorTime=NAN; lastSOC=-1; boundary=false; currents.clear(); active.clear(); session=0; }
    Result consume(const Input &x) {
        Result r;
        if (!x.connected) { reset(); r.reason="disconnected"; return r; }
        if (!std::isfinite(x.soc) || x.soc<0 || x.soc>100 || !std::isfinite(x.now) || !std::isfinite(x.wall)) { reset(); r.reason="invalid_soc_or_clock"; return r; }
        if (x.full || x.soc>=100) {
            // Only observed, uninterrupted 99->100 edge; never fill a terminal gap/pause.
            double elapsed=x.now-anchorTime;
            if (x.soc==100 && lastSOC==99 && boundary && session && active==x.charger &&
                std::isfinite(lastTime) && x.now>lastTime && x.now-lastTime<=45 && elapsed>=10 && elapsed<=3600) {
                auto &v=histories[active][99]; if (v.size()>=8) v.erase(v.begin());
                v.push_back({elapsed,session,x.wall}); dirty=true;
            }
            reset(); r.reason="full"; return r;
        }
        if (!x.charging || (std::isfinite(x.current) && x.current<=0)) { reset(); r.reason="paused_or_net_discharge"; return r; }
        bool gap=std::isfinite(lastTime) && (x.now<=lastTime || x.now-lastTime>95);
        if (gap || (!active.empty() && active!=x.charger)) reset();
        if (validCapacity(x)) {
            if (std::isfinite(batteryMaximum) && std::abs(x.maximum/batteryMaximum-1)>.15) {
                histories.clear(); dirty=true; reset();
            }
            if (!std::isfinite(batteryMaximum) || std::abs(x.maximum/batteryMaximum-1)>.15) { batteryMaximum=x.maximum; dirty=true; }
        }
        if (!session) { session=++serial; dirty=true; active=x.charger; }
        if (!histories.count(active) && histories.size()>=4) { histories.clear(); dirty=true; }
        History &history=histories[active];
        int p=(int)std::floor(x.soc);
        if (lastSOC<0) { lastSOC=p; anchorTime=x.now; boundary=false; }
        else if (p!=lastSOC) {
            double elapsed=x.now-anchorTime;
            if (p==lastSOC+1 && boundary && elapsed>=10 && elapsed<=3600) {
                auto &v=history[lastSOC]; if (v.size()>=8) v.erase(v.begin());
                v.push_back({elapsed,session,x.wall}); dirty=true;
            }
            // A single observed boundary starts the NEXT complete interval only.
            boundary=(p==lastSOC+1); anchorTime=x.now; lastSOC=p;
            currents.clear();
        }
        if (validCapacity(x) && validCurrent(x.current)) {
            currents.push_back(x); if (currents.size()>8) currents.erase(currents.begin());
        } else currents.clear();
        double baseline=NAN;
        if (currents.size()>=3) {
            const auto &first=currents.front(); double dt=x.now-first.now, sum=0,low=1e9,high=0;
            for (const auto &v:currents) { sum+=v.current; low=std::min(low,v.current); high=std::max(high,v.current); }
            double mean=sum/currents.size(), observed=x.capacity-first.capacity;
            double expected=mean*dt/3600;
            // Empirical charge-integration gate validates both positive sign and mA/mAh scale.
            if (dt>=50 && dt<=240 && high/low<=1.35 && std::abs(x.maximum-first.maximum)<=first.maximum*.02 &&
                observed>.2 && expected>0 && observed/expected>=.35 && observed/expected<=2.5 && x.capacity<x.maximum)
                baseline=(x.maximum-x.capacity)/(100-x.soc)/mean*3600;
        }
        lastTime=x.now;
        r=estimate(x.soc,history,x.wall,baseline);
        if (!std::isfinite(r.seconds)) r.reason=gap?"gap_reset_learning":(!validCapacity(x)?"missing_or_untrusted_capacity":"learning_or_unvalidated_current");
        return r;
    }
};
inline bool acceptGeneration(uint64_t requested,uint64_t current,bool enabled,bool connected) {
    return requested==current && enabled && connected;
}
}
