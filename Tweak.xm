#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString * const LSGCEnabled = @"enabled";
static NSString * const LSGCStart = @"startColor";
static NSString * const LSGCEnd = @"endColor";
static NSString * const LSGCDirection = @"direction";
static NSString * const LSGCOpacity = @"opacity";
static NSString * const LSGCAnimate = @"animate";

static NSDictionary *LSGCDefaults(void) {
    NSDictionary *d = @{LSGCEnabled:@YES, LSGCStart:@"#FFFFFF", LSGCEnd:@"#66CCFF", LSGCDirection:@0, LSGCOpacity:@1.0, LSGCAnimate:@NO};
    NSDictionary *p = [[NSUserDefaults standardUserDefaults] persistentDomainForName:@"com.minis.lockscreengradientclock"];
    NSMutableDictionary *m = [d mutableCopy]; if (p) [m addEntriesFromDictionary:p]; return m;
}
static UIColor *LSGCColor(NSString *s) {
    if (![s isKindOfClass:NSString.class]) return UIColor.whiteColor;
    NSString *h = [s stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned v=0; [[NSScanner scannerWithString:h] scanHexInt:&v];
    if (h.length >= 8) return [UIColor colorWithRed:((v>>24)&255)/255.0 green:((v>>16)&255)/255.0 blue:((v>>8)&255)/255.0 alpha:(v&255)/255.0];
    return [UIColor colorWithRed:((v>>16)&255)/255.0 green:((v>>8)&255)/255.0 blue:(v&255)/255.0 alpha:1];
}
static CAGradientLayer *LSGCLayerFor(UIView *clock) {
    static char key; CAGradientLayer *g = objc_getAssociatedObject(clock, &key);
    if (!g) { g = [CAGradientLayer layer]; objc_setAssociatedObject(clock,&key,g,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [clock.layer addSublayer:g]; }
    return g;
}
static void LSGCApply(UIView *clock) {
    if (!clock || !clock.window) return;
    NSDictionary *d=LSGCDefaults(); CAGradientLayer *g=LSGCLayerFor(clock);
    if (![d[LSGCEnabled] boolValue]) { g.hidden=YES; return; } g.hidden=NO;
    g.frame=clock.bounds; g.colors=@[(id)LSGCColor(d[LSGCStart]).CGColor,(id)LSGCColor(d[LSGCEnd]).CGColor];
    NSInteger dir=[d[LSGCDirection] integerValue];
    g.startPoint=dir==1 ? CGPointMake(.5,0) : CGPointMake(0,0); g.endPoint=dir==1 ? CGPointMake(.5,1) : CGPointMake(1,1);
    g.opacity=[d[LSGCOpacity] floatValue];
    UILabel *label=(UILabel *)clock;
    if ([label isKindOfClass:UILabel.class] && label.text.length) { CATextLayer *m=[CATextLayer layer]; m.frame=g.bounds; m.string=label.attributedText ?: label.text; m.font=(__bridge CFTypeRef)label.font; m.fontSize=label.font.pointSize; m.foregroundColor=UIColor.whiteColor.CGColor; m.alignmentMode = label.textAlignment == NSTextAlignmentCenter ? kCAAlignmentCenter : (label.textAlignment == NSTextAlignmentRight ? kCAAlignmentRight : kCAAlignmentLeft); m.contentsScale=UIScreen.mainScreen.scale; g.mask=m; } else { g.hidden=YES; }
    if ([d[LSGCAnimate] boolValue]) { CABasicAnimation *a=[CABasicAnimation animationWithKeyPath:@"locations"]; a.fromValue=@[@0,@0.35]; a.toValue=@[@0.65,@1]; a.duration=3; a.autoreverses=YES; a.repeatCount=HUGE_VALF; [g addAnimation:a forKey:@"lsgc"]; }
}
static BOOL LSGCIsClock(UIView *v) {
    NSString *n=NSStringFromClass(v.class).lowercaseString;
    return [n containsString:@"time"] || [n containsString:@"date"] || [n containsString:@"lockscreenclock"];
}

%hook UIView
- (void)didMoveToWindow { %orig; if (LSGCIsClock(self)) dispatch_async(dispatch_get_main_queue(), ^{ LSGCApply(self); }); }
- (void)layoutSubviews { %orig; if (LSGCIsClock(self)) LSGCApply(self); }
%end

%ctor {
    [[NSNotificationCenter defaultCenter] addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
        dispatch_async(dispatch_get_main_queue(), ^{
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (![scene isKindOfClass:UIWindowScene.class]) continue;
                for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                    [window.rootViewController.view setNeedsLayout];
                }
            }
        });
    }];
}
