#include "../LSGCPalette.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    assert(fabs(LSGCHueForHour(0) + 18) < 1e-9);
    assert(fabs(LSGCHueForHour(6) - 16) < 1e-9);
    assert(fabs(LSGCHueForHour(12)) < 1e-9);
    assert(fabs(LSGCHueForHour(18) - 22) < 1e-9);
    assert(fabs(LSGCHueForHour(24) + 18) < 1e-9);
    assert(fabs(LSGCHueForHour(NAN)) < 1e-9);
    for (double hour = 0; hour <= 24; hour += 0.25) assert(isfinite(LSGCHueForHour(hour)));
    double r, g, b;
    LSGCShiftRGB(0.8, 0.2, 0.1, 0, 1, 1, &r, &g, &b);
    assert(fabs(r - 0.8) < 1e-6 && fabs(g - 0.2) < 1e-6 && fabs(b - 0.1) < 1e-6);
    LSGCShiftRGB(2, -1, NAN, NAN, NAN, NAN, &r, &g, &b);
    assert(isfinite(r) && isfinite(g) && isfinite(b));
    assert(r >= 0 && r <= 1 && g >= 0 && g <= 1 && b >= 0 && b <= 1);
    double close[5][3], bright[5][3], edges[3][3], unused[3][3];
    LSGCWallpaperPalette(0.12, 0.16, 0.34, 0, close, edges);
    LSGCWallpaperPalette(0.12, 0.16, 0.34, 1, bright, unused);
    double closeV = 0, brightV = 0;
    for (int i = 0; i < 5; i++) {
        for (int k = 0; k < 3; k++) {
            assert(close[i][k] >= 0 && close[i][k] <= 1);
            assert(bright[i][k] >= 0 && bright[i][k] <= 1);
        }
        closeV += fmax(close[i][0], fmax(close[i][1], close[i][2]));
        brightV += fmax(bright[i][0], fmax(bright[i][1], bright[i][2]));
    }
    assert(brightV > closeV);
    double bands[3][3] = {{0.85, 0.15, 0.1}, {0.1, 0.7, 0.2}, {0.1, 0.2, 0.75}};
    double bandColors[5][3], bandEdges[3][3], brightBands[5][3];
    LSGCBandPalette(bands, 0, bandColors, bandEdges);
    LSGCBandPalette(bands, 1, brightBands, unused);
    assert(bandColors[0][0] > bandColors[0][1] && bandColors[0][0] > bandColors[0][2]);
    assert(bandColors[2][1] > bandColors[2][0] && bandColors[2][1] > bandColors[2][2]);
    assert(bandColors[4][2] > bandColors[4][0] && bandColors[4][2] > bandColors[4][1]);
    double dark[3][3] = {{0.08, 0.05, 0.04}, {0.05, 0.08, 0.05}, {0.04, 0.05, 0.1}};
    double darkClose[5][3], darkBright[5][3];
    LSGCBandPalette(dark, 0, darkClose, bandEdges);
    LSGCBandPalette(dark, 1, darkBright, bandEdges);
    double darkCloseV = 0, darkBrightV = 0;
    for (int i = 0; i < 5; i++) {
        darkCloseV += fmax(darkClose[i][0], fmax(darkClose[i][1], darkClose[i][2]));
        darkBrightV += fmax(darkBright[i][0], fmax(darkBright[i][1], darkBright[i][2]));
        for (int k = 0; k < 3; k++) {
            assert(bandColors[i][k] >= 0 && bandColors[i][k] <= 1);
            assert(isfinite(brightBands[i][k]));
        }
    }
    assert(darkBrightV > darkCloseV);
    puts("PASS: hour hue, shift bounds, brighter wallpaper palette, band samples");
}
