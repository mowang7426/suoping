#include "../LSGCGradientMath.h"
#include <assert.h>
#include <stdio.h>
int main() {
 double p[4];
 LSGCGradientEndpoints(0,300,900,p);
 assert(fabs(p[0])<1e-9 && fabs(p[2]-1)<1e-9 && fabs(p[1]-.5)<1e-9);
 LSGCGradientEndpoints(90,300,900,p);
 assert(fabs(p[1])<1e-9 && fabs(p[3]-1)<1e-9);
 LSGCGradientEndpoints(45,300,900,p);
 assert(fabs((p[3]-p[1])*900-(p[2]-p[0])*300)<1e-6);
 for(int a=-720;a<=720;a++) {
  LSGCGradientEndpoints(a,300,900,p);
  for(int i=0;i<4;i++) assert(isfinite(p[i]) && p[i]>=-1e-9 && p[i]<=1+1e-9);
 }
 LSGCGradientEndpoints(NAN,0,-1,p);
 for(int i=0;i<4;i++) assert(isfinite(p[i]));
 double input[5]={1,-1,NAN,2,.1},out[5]; LSGCOrderedStops(input,out);
 for(int i=0;i<5;i++) { assert(out[i]>=0 && out[i]<=1+1e-9); if(i) assert(out[i]-out[i-1]>=.01-1e-9); }
 double normal[5]={0,.25,.5,.75,1};LSGCOrderedStops(normal,out);
 for(int i=0;i<5;i++) assert(out[i]==normal[i]);
 puts("PASS: angles, aspect ratio, invalid geometry, ordered stops and unchanged defaults");
}
