#pragma once
// Pure policy contract for the production hide-native-clock switch.
struct LSGCHideNativeClockPolicy {
    bool enabled = true;
    bool hideNativeClock = false;
    bool sourceIdentified = false;
    bool dateOrLunar = false;
    bool sourceAlive = true;
    bool suppression = false;
    bool nativeDraw = true;
    unsigned redrawRequests = 0;
    bool shouldSuppress() const {
        return enabled && hideNativeClock && sourceIdentified && !dateOrLunar && sourceAlive;
    }
    void configure(bool e, bool h) {
        enabled=e; hideNativeClock=h;
        bool next=shouldSuppress();
        if (next != suppression) { suppression=next; ++redrawRequests; nativeDraw=!next; }
    }
    void sourceDestroyed() { sourceAlive=false; sourceIdentified=false; configure(enabled,hideNativeClock); }
    void sourceCreated(bool identified, bool date) { sourceAlive=true; sourceIdentified=identified; dateOrLunar=date; configure(enabled,hideNativeClock); }
};
