#import <Foundation/Foundation.h>
#import "../LSGCChargingCapsuleText.h"
#import "../LSGCChargingCapsuleGeometry.h"
#include <cassert>
// A Foundation label shell exercises the actual production formatting/dedup,
// not an independent reimplementation and not an iOS screenshot claim.
@interface LabelShell : NSObject
@property(nonatomic,copy) NSString *text;
@end
@implementation LabelShell
@end
int main() { @autoreleasepool {
 auto g=LSGCCapsuleLayout(230,60); assert(g.valid && g.width<=218 && g.height==56);
 double leftButtonRight=90,rightButtonLeft=320;
 double x=leftButtonRight+(230-g.width)/2;
 assert(x>leftButtonRight && x+g.width<rightButtonLeft);
 assert(g.topX+g.textWidth<=g.width-8 && g.textWidth>=94);
 assert(!LSGCCapsuleLayout(175,60).valid); assert(!LSGCCapsuleLayout(230,47).valid);
 assert(!LSGCCapsuleLayout(NAN,60).valid);
 NSString *text=LSGCCapsulePresentation(2,59,840,95);
 assert([text isEqual:@"14分钟\n充至95%还需"]);
 assert([LSGCCapsulePresentation(2,59,1,95) hasPrefix:@"1分钟"]);
 assert([LSGCCapsulePresentation(2,59,0,0) isEqual:@"正在充电\n当前59%"]);
 assert([LSGCCapsulePresentation(3,100,840,95) isEqual:@"已充满\n当前100%"]);
 assert(!LSGCCapsulePresentation(1,59,840,95)); assert(!LSGCCapsulePresentation(0,-1,0,0));
 LabelShell *top=[LabelShell new],*bottom=[LabelShell new];
 assert(LSGCCapsuleNeedsRender(nil,@"key",top.text,bottom.text,text));
 top.text=@"14分钟"; bottom.text=@"充至95%还需";
 assert(!LSGCCapsuleNeedsRender(@"key",@"key",top.text,bottom.text,text));
 bottom.text=@""; assert(LSGCCapsuleNeedsRender(@"key",@"key",top.text,bottom.text,text));
 assert(LSGCCapsuleNeedsRender(@"key59",@"key60",top.text,bottom.text,text));
 NSLog(@"PASS production capsule geometry, two-line label shell, unplug hiding, redraw dedup");
} return 0; }
