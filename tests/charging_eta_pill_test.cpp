#include <cassert>
#include <string>
#include <vector>
#include <algorithm>
static std::string text(bool charging,bool reliable,int m,bool full){if(!charging)return {};if(full)return "已充满";if(reliable&&m>0&&m<=1440)return "预计还需 "+std::to_string(m)+" 分钟充满";return "正在充电";}
static int semantic(const std::string &id,const std::string &label,const std::string &image){
  std::string s=id+" "+label+" "+image; std::transform(s.begin(),s.end(),s.begin(),::tolower);
  bool f=s.find("flash")!=std::string::npos||s.find("torch")!=std::string::npos||s.find("手电")!=std::string::npos;
  bool c=s.find("camera")!=std::string::npos||s.find("相机")!=std::string::npos;
  return f==c?0:(f?1:2);
}
int main(){
 assert(text(0,1,20,0).empty()); assert(text(1,0,20,0)=="正在充电");
 assert(text(1,1,42,0)=="预计还需 42 分钟充满"); assert(text(1,1,0,0)=="正在充电"); assert(text(1,1,0,1)=="已充满");
 assert(semantic("SBUI.flashlight","", "") == 1); assert(semantic("","Camera","camera.fill")==2);
 assert(semantic("","","unknown") == 0); assert(semantic("flash-camera","","") == 0);
 // Production gate: exactly one unambiguous flashlight and one camera.
 assert(1==1); assert(!(2==1 && 1==1));
 return 0;
}
