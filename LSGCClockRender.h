#pragma once
#include <cmath>
// One logical canvas centered on the source; glyph bearings are normalized by
// the caller. A full outset plus two antialiasing points survives magnification.
struct LSGCClockCanvas { double width, height, padding; };
static inline LSGCClockCanvas LSGCFullClockCanvas(double sourceW, double sourceH,
                                                double inkW, double inkH,
                                                double weight, double outline) {
    double p=std::ceil(std::fmax(0,weight)+std::fmax(0,outline))+2;
    return {std::ceil(std::fmax(sourceW,inkW+2*p)),
            std::ceil(std::fmax(sourceH,inkH+2*p)),p};
}
static inline double LSGCClockFillOpacity(double value) {
    // Explicit zero still invokes the native fallback. Migrate legacy glass
    // opacity (.32, previously limited to .65) to a solid glyph, not faint tint.
    return value<=0 ? 0 : std::fmax(.85,std::fmin(1.0,value));
}
