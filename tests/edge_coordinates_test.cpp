#include "../LSGCEdgeMath.h"
#include <CoreGraphics/CoreGraphics.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>
// Exercise the exact DrawImage -> CPU edges -> CreateImage pipeline, using
// asymmetric glyph-like ink so any vertical flip or duplicate row fails.
int main() {
    const size_t w=23,h=17,n=w*h*4;
    unsigned char ink[n]={0}, copy[n]={0}, ring[n]={0}, bevel[n]={0}, installed[n]={0};
    for(size_t y=2;y<7;y++) for(size_t x=3;x<9;x++)
        memset(ink+(y*w+x)*4,255,4);
    for(size_t y=5;y<14;y++) memset(ink+(y*w+5)*4,255,4);
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo flags=kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big;
    CGContextRef src=CGBitmapContextCreate(ink,w,h,8,w*4,space,flags);
    CGContextRef dst=CGBitmapContextCreate(copy,w,h,8,w*4,space,flags);
    CGImageRef image=CGBitmapContextCreateImage(src);
    CGContextDrawImage(dst,CGRectMake(0,0,w,h),image);
    assert(!memcmp(ink,copy,n)); // No flip at CGImage decode.
    assert(LSGCMakeEdges(copy,w,h,2,ring,bevel));
    CGContextRef edge=CGBitmapContextCreate(ring,w,h,8,w*4,space,flags);
    CGContextRef out=CGBitmapContextCreate(installed,w,h,8,w*4,space,flags);
    CGImageRef edgeImage=CGBitmapContextCreateImage(edge);
    CGContextDrawImage(out,CGRectMake(0,0,w,h),edgeImage);
    assert(!memcmp(ring,installed,n)); // No flip at edge export/install.
    for(size_t i=0;i<w*h;i++) {
        assert(installed[i*4+3]<=ink[i*4+3]); // Cannot duplicate a displaced glyph.
        assert(bevel[i*4+3]<=ink[i*4+3]);
    }
    CGImageRelease(image); CGImageRelease(edgeImage);
    CGContextRelease(src); CGContextRelease(dst); CGContextRelease(edge); CGContextRelease(out);
    CGColorSpaceRelease(space);
    puts("PASS: asymmetric CoreGraphics edge image roundtrip; identical coordinates and no extra glyph ink");
}
