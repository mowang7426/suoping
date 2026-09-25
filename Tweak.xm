#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <math.h>

// An optional companion: never patch, replace or distribute Liquidify binaries.
extern "C" void MSHookMessageEx(Class, SEL, IMP, IMP *);
static NSString *const Domain = @"com.minis.lockscreengradientclock";
static CFStringRef const Changed = CFSTR("com.minis.lockscreengradientclock/changed");
static CFStringRef const Diagnose = CFSTR("com.minis.lockscreengradientclock/diagnose");
static CFStringRef const Replied = CFSTR("com.minis.lockscreengradientclock/diagnosed");
static NSDictionary *Config;
static NSHashTable<UILabel *> *Labels;
static Class GlassClass;
static BOOL Hooked;
static char StateKey, PendingKey;
static NSUInteger Revision;
static void Apply(UILabel *label);
static void InstallHooks(void);
static void Discover(void);

@interface LSGCState : NSObject
@property(nonatomic,strong) CAGradientLayer *gradient;
@property(nonatomic,strong) CALayer *mask;
@property(nonatomic,copy) NSString *signature;
@property(nonatomic,copy) NSString *maskMode;
@property(nonatomic) BOOL busy;
@property(nonatomic) NSUInteger revision;
@end
@implementation LSGCState
@end

static id ReadObject(id object, NSString *name) {
    SEL sel=NSSelectorFromString(name);
    Method m=object ? class_getInstanceMethod([object class],sel) : NULL;
    if (!m) return nil;
    char type[32]={0}; method_getReturnType(m,type,sizeof(type));
    if (type[0]!='@') return nil;
    return ((id(*)(id,SEL))objc_msgSend)(object,sel);
}
static BOOL ReadFlag(id object, NSString *name) {
    SEL sel=NSSelectorFromString(name);
    if (![object respondsToSelector:sel]) return NO;
    return ((BOOL(*)(id,SEL))objc_msgSend)(object,sel);
}
static CGFloat Clamp(CGFloat x, CGFloat lo, CGFloat hi) {
    return isfinite(x) ? MIN(hi,MAX(lo,x)) : lo;
}
static void LoadConfig(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)Domain);
    NSMutableDictionary *values=[@{@"enabled":@YES,@"color1":@"#39D6ED",@"color2":@"#4D7CFF",@"color3":@"#AD4DF5",@"color4":@"#F950B0",@"color5":@"#FFBD61",@"direction":@0,@"opacity":@0.65,@"animate":@NO,@"strictScope":@YES,@"maskMode":@0} mutableCopy];
    for (NSString *key in values.allKeys) {
        id value=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,(__bridge CFStringRef)Domain));
        if (value) values[key]=value;
    }
    Config=values; Revision++;
}
static UIColor *Color(id input, UIColor *fallback) {
    if (![input isKindOfClass:NSString.class]) return fallback;
    NSString *s=[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([s hasPrefix:@"#"]) s=[s substringFromIndex:1];
    if (s.length!=6 && s.length!=8) return fallback;
    NSCharacterSet *bad=[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet];
    if ([s rangeOfCharacterFromSet:bad].location!=NSNotFound) return fallback;
    unsigned long long v=0; [[NSScanner scannerWithString:s] scanHexLongLong:&v];
    CGFloat a=s.length==8 ? (v&255)/255.0 : 1.0;
    if (s.length==8) v >>=8;
    return [UIColor colorWithRed:((v>>16)&255)/255.0 green:((v>>8)&255)/255.0 blue:(v&255)/255.0 alpha:a];
}
static BOOL TimeText(NSString *s) {
    if (!s.length || s.length>24) return NO;
    NSCharacterSet *digits=NSCharacterSet.decimalDigitCharacterSet;
    NSUInteger count=0;
    for (NSUInteger i=0;i<s.length;i++) if ([digits characterIsMember:[s characterAtIndex:i]]) count++;
    return count>=3 && count<=6 && ([s containsString:@":"] || [s containsString:@"："] || [s containsString:@"∶"]);
}
static BOOL InLockScreen(UIView *view) {
    for (UIView *v=view; v; v=v.superview) {
        for (UIResponder *r=v; r; r=r.nextResponder) {
            NSString *n=NSStringFromClass(r.class);
            if ([n hasPrefix:@"SBFLockScreenDate"] || [n hasPrefix:@"SBLockScreen"] ||
                [n hasPrefix:@"CSCoverSheet"] || [n hasPrefix:@"CSMainPage"] ||
                [n hasPrefix:@"CSDate"] || [n hasPrefix:@"CSCombinedList"] ||
                [n hasPrefix:@"SBUILockScreen"]) return YES;
            if ([r isKindOfClass:UIWindow.class]) break;
        }
    }
    return NO;
}
static BOOL Visible(UIView *view) {
    if (!view.window) return NO;
    for (UIView *v=view; v; v=v.superview) if (v.hidden || v.alpha<0.01) return NO;
    return YES;
}
static void Schedule(UILabel *label) {
    if (!NSThread.isMainThread) return;
    if (objc_getAssociatedObject(label,&PendingKey)) return;
    objc_setAssociatedObject(label,&PendingKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UILabel *weak=label;
    dispatch_async(dispatch_get_main_queue(), ^{
        UILabel *strong=weak; if (!strong) return;
        objc_setAssociatedObject(strong,&PendingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        Apply(strong);
    });
}
static CALayer *MaskOwner(CALayer *root, CALayer *mask, NSUInteger depth) {
    if (!root || depth>16) return nil;
    if (root.mask==mask) return root;
    for (CALayer *child in root.sublayers) {
        CALayer *found=MaskOwner(child,mask,depth+1); if (found) return found;
    }
    return nil;
}
static BOOL HasInk(CALayer *layer, NSUInteger depth) {
    if (!layer || depth>12) return NO;
    if (layer.contents || ([layer isKindOfClass:CAShapeLayer.class] && ((CAShapeLayer *)layer).path) ||
        ([layer isKindOfClass:CATextLayer.class] && ((CATextLayer *)layer).string)) return YES;
    for (CALayer *child in layer.sublayers) if (HasInk(child,depth+1)) return YES;
    return NO;
}
static BOOL HasAlpha(UIImage *image) {
    if (!image.CGImage) return NO;
    unsigned char rgba[64*64*4]={0};
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(rgba,64,64,8,64*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) return NO;
    CGContextDrawImage(ctx,CGRectMake(0,0,64,64),image.CGImage); CGContextRelease(ctx);
    for (NSUInteger i=3;i<sizeof(rgba);i+=4) if (rgba[i]>8) return YES;
    return NO;
}
static UIImage *SnapshotMask(CALayer *source) {
    CGSize size=source.bounds.size;
    if (!HasInk(source,0) || size.width<1 || size.height<1 || size.width>2048 || size.height>2048) return nil;
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];
    format.opaque=NO; format.scale=MIN(UIScreen.mainScreen.scale,2.0);
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextTranslateCTM(context.CGContext,-source.bounds.origin.x,-source.bounds.origin.y);
        [source renderInContext:context.CGContext];
    }];
    return HasAlpha(image) ? image : nil;
}
static UIImage *SnapshotText(UILabel *label) {
    UILabel *mirror=[[UILabel alloc] initWithFrame:(CGRect){CGPointZero,label.bounds.size}];
    mirror.font=label.font; mirror.textColor=UIColor.whiteColor;
    mirror.textAlignment=label.textAlignment; mirror.numberOfLines=label.numberOfLines;
    mirror.lineBreakMode=label.lineBreakMode; mirror.adjustsFontSizeToFitWidth=label.adjustsFontSizeToFitWidth;
    mirror.minimumScaleFactor=label.minimumScaleFactor; mirror.baselineAdjustment=label.baselineAdjustment;
    NSAttributedString *source=ReadObject(label,@"cc_maskAttributedString");
    if (![source isKindOfClass:NSAttributedString.class]) source=label.attributedText;
    if (source.length) {
        NSMutableAttributedString *text=[source mutableCopy]; NSRange all=NSMakeRange(0,text.length);
        [text addAttribute:NSForegroundColorAttributeName value:UIColor.whiteColor range:all];
        [text removeAttribute:NSBackgroundColorAttributeName range:all];
        [text removeAttribute:NSShadowAttributeName range:all];
        mirror.attributedText=text;
    } else mirror.text=label.text;
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];
    format.opaque=NO; format.scale=MIN(UIScreen.mainScreen.scale,2.0);
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:mirror.bounds.size format:format];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        (void)context;
        CGRect rect=[mirror textRectForBounds:mirror.bounds limitedToNumberOfLines:mirror.numberOfLines];
        [mirror drawTextInRect:rect];
    }];
    return HasAlpha(image) ? image : nil;
}
static void RemoveOverlay(UILabel *label) {
    LSGCState *s=objc_getAssociatedObject(label,&StateKey);
    [s.gradient removeFromSuperlayer]; [s.gradient removeAllAnimations];
    s.signature=nil; s.revision=0;
}
static void Apply(UILabel *label) {
    if (!NSThread.isMainThread || !GlassClass || ![label isKindOfClass:GlassClass]) return;
    [Labels addObject:label];
    BOOL scoped=![Config[@"strictScope"] boolValue] || InLockScreen(label);
    if (![Config[@"enabled"] boolValue] || !Visible(label) || !TimeText(label.text ?: label.attributedText.string) ||
        !scoped || label.bounds.size.width<1 || label.bounds.size.height<1 ||
        label.bounds.size.width>2048 || label.bounds.size.height>2048) { RemoveOverlay(label); return; }
    LSGCState *s=objc_getAssociatedObject(label,&StateKey);
    if (!s) {
        s=[LSGCState new]; s.gradient=[CAGradientLayer layer]; s.mask=[CALayer layer];
        s.gradient.name=@"LSGC.LiquidifyGradient"; s.gradient.zPosition=100;
        s.gradient.mask=s.mask;
        objc_setAssociatedObject(label,&StateKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (s.busy) return; s.busy=YES;
    @try {
        CALayer *source=ReadObject(label,@"textMaskLayer");
        if (![source isKindOfClass:CALayer.class]) source=nil;
        CALayer *owner=source ? MaskOwner(label.layer,source,0) : nil;
        BOOL native=owner && [Config[@"maskMode"] integerValue]!=1;
        NSString *signature=[NSString stringWithFormat:@"%@|%@|%@|%p|%p|%@|%d|%d|%lu",
            label.attributedText ?: (id)label.text,NSStringFromCGRect(label.bounds),label.font,
            source,(__bridge void *)source.contents,NSStringFromCGRect(source ? source.frame : CGRectZero),
            ReadFlag(label,@"cachedBuildFinished"),native,(unsigned long)Revision];
        CALayer *host=native ? owner : label.layer;
        if (![s.signature isEqualToString:signature]) {
            UIImage *image=native ? SnapshotMask(source) : nil;
            if (!image) { native=NO; host=label.layer; image=SnapshotText(label); }
            if (!image) { RemoveOverlay(label); s.maskMode=@"遮罩为空"; return; }
            [CATransaction begin]; [CATransaction setDisableActions:YES];
            s.mask.contents=(__bridge id)image.CGImage;
            s.mask.contentsScale=image.scale;
            s.mask.contentsGravity=kCAGravityResize;
            s.mask.transform=CATransform3DIdentity;
            if (native) {
                s.mask.bounds=source.bounds; s.mask.anchorPoint=source.anchorPoint;
                s.mask.position=source.position; s.mask.transform=source.transform;
            } else {
                s.mask.anchorPoint=CGPointMake(.5,.5);
                s.mask.bounds=(CGRect){CGPointZero,label.bounds.size};
                s.mask.position=CGPointMake(CGRectGetMidX(label.bounds),CGRectGetMidY(label.bounds));
            }
            s.maskMode=native ? @"原插件文字遮罩" : @"同字体文字重绘";
            [CATransaction commit]; s.signature=signature;
        } else if ([s.maskMode isEqualToString:@"同字体文字重绘"]) host=label.layer;
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        s.gradient.bounds=host.bounds;
        s.gradient.position=CGPointMake(CGRectGetMidX(host.bounds),CGRectGetMidY(host.bounds));
        s.gradient.opacity=Clamp([Config[@"opacity"] doubleValue],0,1);
        NSInteger direction=[Config[@"direction"] integerValue];
        s.gradient.startPoint=direction==1 ? CGPointMake(.5,0) : CGPointMake(0,.5);
        s.gradient.endPoint=direction==1 ? CGPointMake(.5,1) : CGPointMake(1,.5);
        if (direction==2) { s.gradient.startPoint=CGPointMake(0,0); s.gradient.endPoint=CGPointMake(1,1); }
        if (s.revision!=Revision) {
            NSArray *defaults=@[@"#39D6ED",@"#4D7CFF",@"#AD4DF5",@"#F950B0",@"#FFBD61"];
            NSMutableArray *colors=[NSMutableArray array];
            for (NSUInteger i=0;i<5;i++) {
                NSString *key=[NSString stringWithFormat:@"color%lu",(unsigned long)i+1];
                UIColor *c=Color(Config[key],Color(defaults[i],UIColor.whiteColor));
                [colors addObject:(__bridge id)c.CGColor];
            }
            s.gradient.colors=colors; s.gradient.locations=@[@0,@0.25,@0.5,@0.75,@1];
            [s.gradient removeAllAnimations];
            if ([Config[@"animate"] boolValue]) {
                NSMutableArray *reverse=[NSMutableArray arrayWithArray:[[colors reverseObjectEnumerator] allObjects]];
                CABasicAnimation *a=[CABasicAnimation animationWithKeyPath:@"colors"];
                a.fromValue=colors; a.toValue=reverse; a.duration=6; a.autoreverses=YES; a.repeatCount=HUGE_VALF;
                [s.gradient addAnimation:a forKey:@"LSGC.colors"];
            }
            s.revision=Revision;
        }
        if (s.gradient.superlayer!=host) { [s.gradient removeFromSuperlayer]; [host addSublayer:s.gradient]; }
        [CATransaction commit];
    } @catch (NSException *exception) {
        RemoveOverlay(label); s.maskMode=[@"兼容异常：" stringByAppendingString:exception.name];
    } @finally { s.busy=NO; }
}
static void (*OrigLayout)(id,SEL);
static void (*OrigMove)(id,SEL);
static void (*OrigText)(id,SEL,id);
static void (*OrigAttributed)(id,SEL,id);
static void (*OrigFont)(id,SEL,id);
static void (*OrigMask)(id,SEL,id);
static void (*OrigFinished)(id,SEL,BOOL);
static void Layout(id obj,SEL sel) { OrigLayout(obj,sel); Schedule(obj); }
static void Move(id obj,SEL sel) { OrigMove(obj,sel); Schedule(obj); }
static void Text(id obj,SEL sel,id value) { OrigText(obj,sel,value); Schedule(obj); }
static void Attributed(id obj,SEL sel,id value) { OrigAttributed(obj,sel,value); Schedule(obj); }
static void Font(id obj,SEL sel,id value) { OrigFont(obj,sel,value); Schedule(obj); }
static void Mask(id obj,SEL sel,id value) {
    OrigMask(obj,sel,value);
    LSGCState *s=objc_getAssociatedObject(obj,&StateKey); s.signature=nil; Schedule(obj);
}
static void Finished(id obj,SEL sel,BOOL value) {
    OrigFinished(obj,sel,value);
    LSGCState *s=objc_getAssociatedObject(obj,&StateKey); s.signature=nil; Schedule(obj);
}
static void Hook(const char *name,IMP replacement,IMP *original,NSUInteger arguments) {
    SEL sel=sel_registerName(name); Method method=class_getInstanceMethod(GlassClass,sel);
    if (!method || method_getNumberOfArguments(method)!=arguments) return;
    char ret[16]={0}; method_getReturnType(method,ret,sizeof(ret));
    if (ret[0]!='v') return;
    MSHookMessageEx(GlassClass,sel,replacement,original);
}
static void InstallHooks(void) {
    if (Hooked) return;
    Class cls=NSClassFromString(@"CCLiquidGlassLabel");
    if (!cls || ![cls isSubclassOfClass:UILabel.class]) return;
    GlassClass=cls;
    Hook("layoutSubviews",(IMP)Layout,(IMP *)&OrigLayout,2);
    Hook("didMoveToWindow",(IMP)Move,(IMP *)&OrigMove,2);
    Hook("setText:",(IMP)Text,(IMP *)&OrigText,3);
    Hook("setAttributedText:",(IMP)Attributed,(IMP *)&OrigAttributed,3);
    Hook("setFont:",(IMP)Font,(IMP *)&OrigFont,3);
    Hook("setTextMaskLayer:",(IMP)Mask,(IMP *)&OrigMask,3);
    Hook("setCachedBuildFinished:",(IMP)Finished,(IMP *)&OrigFinished,3);
    Hooked=OrigLayout!=NULL;
}
static void Walk(UIView *view,NSUInteger depth) {
    if (!view || depth>64) return;
    if (GlassClass && [view isKindOfClass:GlassClass]) { [Labels addObject:(UILabel *)view]; Schedule((UILabel *)view); }
    for (UIView *child in view.subviews) Walk(child,depth+1);
}
static void Discover(void) {
    InstallHooks();
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) Walk(window,0);
    }
}
static void WriteDiagnostics(void) {
    Discover();
    NSUInteger clocks=0,scoped=0,active=0; NSMutableArray *details=[NSMutableArray array];
    for (UILabel *label in Labels.allObjects) {
        BOOL time=TimeText(label.text ?: label.attributedText.string); clocks+=time;
        BOOL lock=InLockScreen(label); scoped+=(time && lock);
        LSGCState *s=objc_getAssociatedObject(label,&StateKey);
        active+=(s.gradient.superlayer!=nil);
        if (details.count<6) {
            NSMutableArray *chain=[NSMutableArray array];
            UIView *v=label;
            for (NSUInteger i=0;v && i<12;i++,v=v.superview) [chain addObject:NSStringFromClass(v.class)];
            [details addObject:[NSString stringWithFormat:@"时间形态=%@ 锁屏范围=%@ 可见=%@\n模式=%@\n%@",time?@"是":@"否",lock?@"是":@"否",Visible(label)?@"是":@"否",s.maskMode?:@"尚未渲染",[chain componentsJoinedByString:@" > "]]];
        }
    }
    NSString *report=[NSString stringWithFormat:@"兼容层 1.1.0\n类已加载：%@\nHook 已安装：%@\n玻璃标签：%lu\n时间标签：%lu\n锁屏范围命中：%lu\n已附加渐变：%lu\n开关：%@\n\n%@",
        GlassClass?@"是":@"否",Hooked?@"是":@"否",(unsigned long)Labels.allObjects.count,(unsigned long)clocks,(unsigned long)scoped,(unsigned long)active,[Config[@"enabled"] boolValue]?@"开":@"关",[details componentsJoinedByString:@"\n\n"]];
    CFPreferencesSetAppValue(CFSTR("diagnosticReport"),(__bridge CFStringRef)report,(__bridge CFStringRef)Domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)Domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),Replied,NULL,NULL,true);
}
static void Notification(CFNotificationCenterRef center,void *observer,CFStringRef name,const void *object,CFDictionaryRef info) {
    (void)center; (void)observer; (void)object; (void)info;
    BOOL diagnostic=CFEqual(name,Diagnose);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (diagnostic) { WriteDiagnostics(); return; }
        LoadConfig(); Discover();
        for (UILabel *label in Labels.allObjects) Schedule(label);
    });
}
static void AddedImage(const struct mach_header *header,intptr_t slide) {
    (void)header; (void)slide;
    dispatch_async(dispatch_get_main_queue(), ^{ InstallHooks(); });
}
__attribute__((constructor)) static void Start(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            Labels=[NSHashTable weakObjectsHashTable]; LoadConfig();
            CFNotificationCenterRef center=CFNotificationCenterGetDarwinNotifyCenter();
            CFNotificationCenterAddObserver(center,NULL,Notification,Changed,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
            CFNotificationCenterAddObserver(center,NULL,Notification,Diagnose,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
            _dyld_register_func_for_add_image(AddedImage);
            Discover();
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { (void)note; Discover(); }];
            // Low-frequency geometry maintenance; no repeated bitmap work unless signature changes.
            NSTimer *timer=[NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
                (void)t;
                for (UILabel *label in Labels.allObjects) {
                    if (Visible(label)) Apply(label);
                    else RemoveOverlay(label);
                }
            }];
            [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
        });
    }
}
