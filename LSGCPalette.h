#pragma once
#include <math.h>

static inline double LSGCUnit(double v) {
    if (!isfinite(v)) return 0;
    return v < 0 ? 0 : (v > 1 ? 1 : v);
}
static inline void LSGCRgbToHsb(double r, double g, double b, double *h, double *s, double *v) {
    r = LSGCUnit(r); g = LSGCUnit(g); b = LSGCUnit(b);
    double max = fmax(r, fmax(g, b)), min = fmin(r, fmin(g, b)), d = max - min;
    *v = max;
    *s = max <= 1e-8 ? 0 : d / max;
    if (d <= 1e-8) { *h = 0; return; }
    if (max == r) *h = fmod((g - b) / d, 6.0);
    else if (max == g) *h = (b - r) / d + 2.0;
    else *h = (r - g) / d + 4.0;
    *h *= 60.0;
    if (*h < 0) *h += 360.0;
}
static inline void LSGCHsbToRgb(double h, double s, double v, double *r, double *g, double *b) {
    if (!isfinite(h)) h = 0;
    h = fmod(h, 360.0);
    if (h < 0) h += 360.0;
    s = LSGCUnit(s); v = LSGCUnit(v);
    double c = v * s;
    double x = c * (1.0 - fabs(fmod(h / 60.0, 2.0) - 1.0));
    double m = v - c;
    double rp = 0, gp = 0, bp = 0;
    int seg = (int)(h / 60.0) % 6;
    if (seg == 0) { rp = c; gp = x; }
    else if (seg == 1) { rp = x; gp = c; }
    else if (seg == 2) { gp = c; bp = x; }
    else if (seg == 3) { gp = x; bp = c; }
    else if (seg == 4) { rp = x; bp = c; }
    else { rp = c; bp = x; }
    *r = rp + m; *g = gp + m; *b = bp + m;
}
static inline void LSGCShiftRGB(double r, double g, double b, double hueDelta, double satScale, double briScale, double *outR, double *outG, double *outB) {
    double h, s, v;
    if (!isfinite(hueDelta)) hueDelta = 0;
    if (!isfinite(satScale)) satScale = 1;
    if (!isfinite(briScale)) briScale = 1;
    LSGCRgbToHsb(r, g, b, &h, &s, &v);
    LSGCHsbToRgb(h + hueDelta, s * satScale, v * briScale, outR, outG, outB);
}
static inline double LSGCHueForHour(double hour) {
    if (!isfinite(hour)) return 0;
    hour = fmod(hour, 24.0);
    if (hour < 0) hour += 24.0;
    const double marks[5] = {0, 6, 12, 18, 24};
    const double hues[5] = {-18, 16, 0, 22, -18};
    for (int i = 0; i < 4; i++) {
        if (hour >= marks[i] && hour <= marks[i + 1]) {
            double span = marks[i + 1] - marks[i];
            double t = span <= 0 ? 0 : (hour - marks[i]) / span;
            return hues[i] + (hues[i + 1] - hues[i]) * t;
        }
    }
    return 0;
}
static inline void LSGCWallpaperPalette(double r, double g, double b, int brighter, double colors[5][3], double edges[3][3]) {
    double h, s, v;
    LSGCRgbToHsb(r, g, b, &h, &s, &v);
    if (s < 0.12) s = 0.12;
    double sat = brighter ? fmin(1.0, s * 0.62) : fmin(1.0, s * 0.94);
    double bri = brighter ? fmin(1.0, fmax(0.78, v * 1.15)) : fmin(1.0, fmax(0.34, v));
    const double offsets[5] = {-28, -12, 0, 14, 30};
    for (int i = 0; i < 5; i++) LSGCHsbToRgb(h + offsets[i], sat, bri, &colors[i][0], &colors[i][1], &colors[i][2]);
    const double edgeOffsets[3] = {-10, 8, 24};
    double edgeSat = fmin(1.0, sat * 0.5);
    double edgeBri = fmin(1.0, fmax(bri, 0.9));
    for (int i = 0; i < 3; i++) LSGCHsbToRgb(h + edgeOffsets[i], edgeSat, edgeBri, &edges[i][0], &edges[i][1], &edges[i][2]);
}
static inline void LSGCMix3(const double a[3], const double b[3], double t, double out[3]) {
    out[0] = LSGCUnit(a[0] * (1.0 - t) + b[0] * t);
    out[1] = LSGCUnit(a[1] * (1.0 - t) + b[1] * t);
    out[2] = LSGCUnit(a[2] * (1.0 - t) + b[2] * t);
}
static inline void LSGCPrepareBand(const double in[3], int brighter, double out[3]) {
    double r, g, b, h, s, v;
    LSGCShiftRGB(in[0], in[1], in[2], 0, brighter ? 0.75 : 1, brighter ? 1.18 : 1, &r, &g, &b);
    if (brighter) {
        LSGCRgbToHsb(r, g, b, &h, &s, &v);
        if (v < 0.72) v = 0.72;
        LSGCHsbToRgb(h, s, v, &r, &g, &b);
    }
    out[0] = r; out[1] = g; out[2] = b;
}
static inline void LSGCBandPalette(const double bands[3][3], int brighter, double colors[5][3], double edges[3][3]) {
    double band[3][3];
    for (int i = 0; i < 3; i++) LSGCPrepareBand(bands[i], brighter, band[i]);
    colors[0][0] = band[0][0]; colors[0][1] = band[0][1]; colors[0][2] = band[0][2];
    LSGCMix3(band[0], band[1], 0.5, colors[1]);
    colors[2][0] = band[1][0]; colors[2][1] = band[1][1]; colors[2][2] = band[1][2];
    LSGCMix3(band[1], band[2], 0.5, colors[3]);
    colors[4][0] = band[2][0]; colors[4][1] = band[2][1]; colors[4][2] = band[2][2];
    for (int i = 0; i < 3; i++) {
        double h, s, v;
        LSGCRgbToHsb(band[i][0], band[i][1], band[i][2], &h, &s, &v);
        LSGCHsbToRgb(h, s * 0.45, fmin(1.0, fmax(v, 0.88)), &edges[i][0], &edges[i][1], &edges[i][2]);
    }
}
