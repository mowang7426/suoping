#include <cassert>
#include <cmath>
#include <string>
static int minutes(double v,bool seconds){ if(!std::isfinite(v)||v<=0||v>86400)return 0; int m=seconds?(int)std::ceil(v/60.0):(int)std::llround(v); return m>0&&m<=1440?m:0; }
static bool trusted(const std::string& source,const std::string& key){ return (source.rfind("SBUIBattery",0)==0||source.rfind("SBBattery",0)==0||source.rfind("BUICharging",0)==0||source=="BatteryData") && (key.find("estimatedTimeRemaining")!=std::string::npos||key.find("chargingTimeRemaining")!=std::string::npos||key.find("batteryTimeRemaining")!=std::string::npos); }
int main(){
 assert(minutes(120,false)==120); assert(minutes(120,true)==2); assert(minutes(61,true)==2);
 assert(minutes(0,true)==0); assert(minutes(-1,true)==0); assert(minutes(86401,true)==0); assert(minutes(NAN,true)==0); assert(minutes(86400,false)==0);
 assert(trusted("SBUIBatteryData","estimatedTimeRemaining")); assert(trusted("BUIChargingData","chargingTimeRemainingMinutes"));
 assert(!trusted("UIDevice","batteryLevel")); assert(!trusted("NSProcessInfo","estimatedTimeRemaining")); assert(!trusted("SBBatteryData","percent"));
 return 0;
}
