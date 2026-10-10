#include <cassert>
#include <string>
static std::string text(bool charging,bool reliable,int m,bool full){if(!charging)return {};if(full)return "已充满";if(reliable&&m>0&&m<=1440)return "预计还需 "+std::to_string(m)+" 分钟充满";return "正在充电";}
int main(){assert(text(0,1,20,0).empty());assert(text(1,0,20,0)=="正在充电");assert(text(1,1,42,0)=="预计还需 42 分钟充满");assert(text(1,1,0,0)=="正在充电");assert(text(1,1,0,1)=="已充满");return 0;}
