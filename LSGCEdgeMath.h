#pragma once
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <math.h>

// Pure CPU inner contour. Never paints outside the source alpha.
// Coordinates use bitmap rows; the caller provides top-down RGBA.
static inline float LSGCMin(float a,float b) { return a<b?a:b; }
static inline uint8_t LSGCAlpha(const uint8_t *rgba,size_t w,size_t h,long x,long y) {
    if (x<0 || y<0 || (size_t)x>=w || (size_t)y>=h) return 0;
    return rgba[((size_t)y*w+(size_t)x)*4+3];
}
static inline bool LSGCMakeEdges(const uint8_t *rgba,size_t w,size_t h,float radius,
                                uint8_t *ring,uint8_t *bevel) {
    if (!rgba || !ring || !bevel || !w || !h || w>4096 || h>4096 || w*h>4194304 || !isfinite(radius)) return false;
    radius=fmaxf(0.5f,fminf(radius,12.0f));
    float *distance=(float *)malloc(w*h*sizeof(float));
    if (!distance) return false;
    for(size_t y=0;y<h;y++) for(size_t x=0;x<w;x++) {
        size_t i=y*w+x; uint8_t a=rgba[i*4+3];
        distance[i]=a<128 ? 0 : ((x==0 || y==0 || x+1==w || y+1==h) ? 1 : 100000);
    }
    for(size_t y=0;y<h;y++) for(size_t x=0;x<w;x++) {
        size_t i=y*w+x; float d=distance[i];
        if(x) d=LSGCMin(d,distance[i-1]+1);
        if(y) d=LSGCMin(d,distance[i-w]+1);
        if(x && y) d=LSGCMin(d,distance[i-w-1]+1.414214f);
        if(x+1<w && y) d=LSGCMin(d,distance[i-w+1]+1.414214f);
        distance[i]=d;
    }
    for(size_t yy=h;yy>0;yy--) for(size_t xx=w;xx>0;xx--) {
        size_t y=yy-1,x=xx-1,i=y*w+x; float d=distance[i];
        if(x+1<w) d=LSGCMin(d,distance[i+1]+1);
        if(y+1<h) d=LSGCMin(d,distance[i+w]+1);
        if(x+1<w && y+1<h) d=LSGCMin(d,distance[i+w+1]+1.414214f);
        if(x && y+1<h) d=LSGCMin(d,distance[i+w-1]+1.414214f);
        distance[i]=d;
    }
    long sample=(long)ceilf(radius+1);
    for(size_t y=0;y<h;y++) for(size_t x=0;x<w;x++) {
        size_t i=y*w+x; float a=rgba[i*4+3]/255.0f;
        float t=fmaxf(0,fminf(1,(radius+0.75f-distance[i])/fmaxf(radius,1)));
        float coverage=a*t*t*(3-2*t);
        float dx=(float)LSGCAlpha(rgba,w,h,(long)x+sample,(long)y)-(float)LSGCAlpha(rgba,w,h,(long)x-sample,(long)y);
        float dy=(float)LSGCAlpha(rgba,w,h,(long)x,(long)y+sample)-(float)LSGCAlpha(rgba,w,h,(long)x,(long)y-sample);
        float norm=hypotf(dx,dy), light=norm>1 ? (dx+dy)/(1.414214f*norm) : 0;
        // Asymmetric soft contour, not an opaque uniform outline.
        uint8_t ra=(uint8_t)lroundf(255*coverage*(0.65f+0.35f*fabsf(light)));
        ring[i*4]=ring[i*4+1]=ring[i*4+2]=ring[i*4+3]=ra;
        float amount=light>0 ? light : -light*0.45f;
        uint8_t ba=(uint8_t)lroundf(255*coverage*amount);
        bevel[i*4]=bevel[i*4+1]=bevel[i*4+2]=light>0 ? ba : 0;
        bevel[i*4+3]=ba;
    }
    free(distance); return true;
}
