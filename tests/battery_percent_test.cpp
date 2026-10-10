#include <cassert>
#include <cmath>
#include <string>
#include <algorithm>

enum State { Unknown=0, Unplugged=1, Charging=2, Full=3 };
static int percent(float level) {
  if (!std::isfinite(level) || level < 0.0f || level > 1.0f) return -1;
  return std::max(0, std::min(100, (int)std::floor(level * 100.0f + 0.5f)));
}
static std::string batteryText(State state, float level) {
  if (state != Charging && state != Full) return {};
  if (state == Full) return "已充满 · 100%";
  int p=percent(level); return p < 0 ? "正在充电" : "正在充电 · " + std::to_string(p) + "%";
}
int main() {
  assert(percent(0.0f)==0); assert(percent(1.0f)==100); assert(percent(-1.0f)==-1);
  assert(percent(NAN)==-1); assert(percent(1.01f)==-1);
  assert(batteryText(Charging,0.0f)=="正在充电 · 0%");
  assert(batteryText(Charging,0.73f)=="正在充电 · 73%");
  assert(batteryText(Charging,-1.0f)=="正在充电");
  assert(batteryText(Full,0.01f)=="已充满 · 100%");
  assert(batteryText(Unplugged,0.73f).empty()); assert(batteryText(Unknown,0.73f).empty());
  assert(batteryText(Charging,0.73f)==batteryText(Charging,0.73f));
  return 0;
}
