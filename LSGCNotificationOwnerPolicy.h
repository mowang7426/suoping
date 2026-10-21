#pragma once
#include <cmath>
namespace LSGCNotificationOwner {
inline bool GapFits(double bottom,double ceiling,double width,double height) {
    return std::isfinite(bottom) && std::isfinite(ceiling) && std::isfinite(width) && std::isfinite(height) && width>=160 && height>=44 && ceiling-bottom-8>=height;
}
}
