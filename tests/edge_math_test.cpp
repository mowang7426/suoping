#include "../LSGCEdgeMath.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    const size_t w=32,h=32,n=w*h*4;
    uint8_t source[n], ring[n], light[n];
    memset(source,0,n);
    for(size_t y=4;y<28;y++) for(size_t x=4;x<28;x++) source[(y*w+x)*4+3]=255;
    // Inner hole exercises the inner glyph boundary as well as the outer one.
    for(size_t y=12;y<20;y++) for(size_t x=12;x<20;x++) source[(y*w+x)*4+3]=0;
    assert(LSGCMakeEdges(source,w,h,2,ring,light));
    unsigned total=0;
    for(size_t i=0;i<w*h;i++) {
        assert(ring[i*4+3]<=source[i*4+3]);
        assert(light[i*4+3]<=source[i*4+3]);
        assert(light[i*4]<=light[i*4+3]);
        total+=ring[i*4+3];
    }
    assert(total>0);
    assert(ring[(8*w+8)*4+3]==0); // Interior remains unpainted.
    assert(ring[(4*w+8)*4+3]>0); // Outer edge.
    assert(ring[(11*w+16)*4+3]>0); // Hole edge.
    assert(light[(4*w+8)*4]>0); // Top-facing highlight.
    assert(light[(27*w+8)*4]==0 && light[(27*w+8)*4+3]>0); // Opposite shadow.
    assert(!LSGCMakeEdges(NULL,w,h,2,ring,light));
    assert(!LSGCMakeEdges(source,5000,h,2,ring,light));
    assert(!LSGCMakeEdges(source,w,h,NAN,ring,light));
    memset(source,0,n);
    assert(LSGCMakeEdges(source,w,h,2,ring,light));
    for(size_t i=0;i<n;i++) assert(ring[i]==0 && light[i]==0);
    puts("PASS: bounds, inner/outer contour, directional highlight, transparent center, invalid inputs");
}
