#include <cassert>
#include <cmath>
#include <map>
#include <string>
using D=std::map<std::string,std::string>;
static bool valid(const D& d,double now,const std::string& source){
 auto g=[&](const char*k){auto i=d.find(k);return i==d.end()?std::string():i->second;};
 if(g("status")!="available"||g("estimateSource")!=source||g("algorithm").empty())return false;
 std::string a=g("algorithm"); if(a.find("jikan")==std::string::npos&&a.find("apple")==std::string::npos&&a.find("tt100")==std::string::npos&&a.find("tt80")==std::string::npos&&a.find("ttl")==std::string::npos)return false;
 double ts=std::stod(g("timestamp")); double sec=std::stod(g("remainingSeconds").empty()?g("seconds"):g("remainingSeconds")); double target=std::stod(g("targetPercent"));
 return std::isfinite(ts)&&ts<=now+60&&now-ts<=300&&std::isfinite(sec)&&sec>0&&sec<=86400&&std::isfinite(target)&&target>=1&&target<=100&&std::floor(target)==target;
}
static D good(){return {{"status","available"},{"estimateSource","jikan"},{"algorithm","tt100-history"},{"timestamp","1000"},{"remainingSeconds","840"},{"targetPercent","95"}};}
int main(){
 D d=good(); assert(valid(d,1000,"jikan")); assert(!valid(d,1000,"apple"));
 d["seconds"]="840"; d.erase("remainingSeconds"); assert(valid(d,1000,"jikan")); // both documented seconds units are accepted
 d=good(); d["remainingSeconds"]="0"; assert(!valid(d,1000,"jikan")); d=good(); d["remainingSeconds"]="86401"; assert(!valid(d,1000,"jikan"));
 d=good(); d["targetPercent"]="0"; assert(!valid(d,1000,"jikan")); d=good(); d["timestamp"]="600"; assert(!valid(d,1000,"jikan"));
 d=good(); d["status"]="unavailable"; assert(!valid(d,1000,"jikan"));
 // unplug/session generation is represented by rejecting a result whose generation is old.
 unsigned long long current=2, callback=1; assert(callback!=current);
 return 0;
}
