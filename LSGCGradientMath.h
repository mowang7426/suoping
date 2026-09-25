#pragma once
#include <math.h>
#include <stddef.h>

// Return endpoints inside the unit rectangle; angle measured in displayed points.
static inline void LSGCGradientEndpoints(double degrees,double width,double height,double out[4]) {
    if (!isfinite(degrees)) degrees=0;
    if (!isfinite(width) || width<=0) width=1;
    if (!isfinite(height) || height<=0) height=1;
    double r=fmod(degrees,360.0)*3.14159265358979323846/180.0;
    double dx=cos(r)/width,dy=sin(r)/height;
    double scale=0.5/fmax(fabs(dx),fabs(dy));
    out[0]=0.5-dx*scale; out[1]=0.5-dy*scale;
    out[2]=0.5+dx*scale; out[3]=0.5+dy*scale;
}
// Fix invalid stored positions without ever handing descending stops to Core Animation.
static inline void LSGCOrderedStops(const double input[5],double output[5]) {
    for (size_t i=0;i<5;i++) {
        double value=isfinite(input[i]) ? input[i] : i*0.25;
        double low=i ? output[i-1]+0.01 : 0;
        double high=1-(4-i)*0.01;
        output[i]=fmax(low,fmin(high,value));
    }
}
