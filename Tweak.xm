#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreText/CoreText.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <math.h>
#import "LSGCEdgeMath.h"
#import "LSGCGradientMath.h"
#import "LSGCPalette.h"
#import "LSGCVersion.h"
#import "LSGCFont.h"
#import "LSGCClockSafety.h"
#import "LSGCClockScope.h"
#import "LSGCClockRender.h"
#import "LSGCWakeStrategy.h"

// An optional companion: never patch, replace or distribute Liquidify binaries.
extern "C" void MSHookMessageEx(Class, SEL, IMP, IMP *);
static NSString *const Domain = @"com.minis.lockscreengradientclock";
static CFStringRef const Changed = CFSTR("com.minis.lockscreengradientclock/changed");
static CFStringRef const Diagnose = CFSTR("com.minis.lockscreengradientclock/diagnose");
static CFStringRef const Replied = CFSTR("com.minis.lockscreengradientclock/diagnosed");
static CFStringRef const Sample = CFSTR("com.minis.lockscreengradientclock/sampleWallpaper");
static CFStringRef const Sampled = CFSTR("com.minis.lockscreengradientclock/sampled");
static CGFloat ParallaxDegrees;
static CFTimeInterval ParallaxStamp;
static NSDictionary *Config;
static NSHashTable<UILabel *> *Labels;
static NSHashTable<UIView *> *DateViews;
static Class GlassClass;
static BOOL Hooked;
static BOOL LabelHooked;
static NSMutableSet<NSString *> *ClockHookKeys;
static BOOL NativeClassesLoaded;
static BOOL StartupComplete;
static BOOL ImageRefreshPending;
static void Walk(UIView *view,NSUInteger depth);
static NSString *HookReport;
static char StateKey, PendingKey;
static BOOL Rendering;
static BOOL NativeClockSuppressionState;
static NSUInteger Revision;
static void Apply(UILabel *label);
static BOOL NativeClockSuppressionEnabled(void);
static void RefreshNativeClockSuppression(void);
static BOOL ClockReplacementReady(UILabel *label);
static BOOL ClockReplacementReadyForCommit(UILabel *label);
static void InstallHooks(void);
static void InstallLabelHooks(void);
static void Discover(void);
static void RegisterUserFont(void);
static void InstallClockHooks(void);
static UIFont *ImportedFont;
static NSString *ImportedPath;
static NSString *FontStatus;
// Bounded diagnostics: scalar totals and one last snapshot, no frame sampling.
static unsigned long long DiagLayout, DiagMove, DiagDraw, DiagMainDraw, DiagNative, DiagSuppress;
static unsigned long long DiagSchedule, DiagApply, DiagInstall;
static NSUInteger DiagDrawDepth;
static NSString *DiagScheduleReturn, *DiagApplyReturn, *DiagMainApplyReturn;
static unsigned long long DiagMainApply;
static NSDictionary *DiagMask, *DiagFailure;
static NSMutableDictionary<NSString *, NSValue *> *DiagOriginals, *DiagExpected;
static void DiagInc(unsigned long long *value) {
    unsigned long long old=__atomic_load_n(value,__ATOMIC_RELAXED);
    while (old!=~0ULL && !__atomic_compare_exchange_n(value,&old,old+1,NO,__ATOMIC_RELAXED,__ATOMIC_RELAXED)) {}
}
static void DiagRememberIMP(Class cls, SEL sel, IMP original, IMP hook) {
    if (!DiagOriginals) { DiagOriginals=[NSMutableDictionary dictionary]; DiagExpected=[NSMutableDictionary dictionary]; }
    NSString *key=[NSString stringWithFormat:@"%@/%@",NSStringFromClass(cls),NSStringFromSelector(sel)];
    DiagOriginals[key]=[NSValue valueWithPointer:(const void *)original];
    DiagExpected[key]=[NSValue valueWithPointer:(const void *)hook];
}
static void DiagCaptureFailure(UILabel *label, NSString *reason);
static void DiagCaptureMask(UIImage *image, CGSize requested, CGFloat scale);
static NSString *DiagReport(void);


@interface LSGCState : NSObject {
@public
    LSGCWakePolicy wakePolicy;
}
@property(nonatomic,strong) CAGradientLayer *gradient;
@property(nonatomic,strong) CALayer *dateHost;
@property(nonatomic,strong) CAShapeLayer *clockRim;
@property(nonatomic) CGSize clockCanvasSize;
@property(nonatomic,weak) UIView *clockHost;
@property(nonatomic,copy) NSString *hostSelection;
@property(nonatomic,strong) CALayer *mask;
@property(nonatomic,strong) CALayer *edgeHost;
@property(nonatomic,strong) CAGradientLayer *edgeTint;
@property(nonatomic,strong) CALayer *edgeMask;
@property(nonatomic,strong) CALayer *edgeBevel;
@property(nonatomic,copy) NSString *signature;
@property(nonatomic,copy) NSString *maskMode;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL dirty;
@property(nonatomic) NSUInteger revision;
@property(nonatomic) NSUInteger ticket;
@property(nonatomic) NSUInteger motionBits;
@property(nonatomic) NSUInteger styleToken;
@property(nonatomic) BOOL clockCommitted;
@property(nonatomic) BOOL didUnclipClock;
@property(nonatomic) BOOL originalClipsToBounds;
@property(nonatomic) BOOL maskHasInk;
@property(nonatomic) BOOL hidOriginalLabel;
@property(nonatomic) CGFloat originalAlpha;
@property(nonatomic) BOOL originalHidden;
@property(nonatomic,strong) UIImage *cachedMask;
@property(nonatomic,copy) NSString *cachedMaskSignature;
@property(nonatomic) NSUInteger cachedResourceGeneration;
@property(nonatomic,copy) NSString *failedResourceKey;
@property(nonatomic) NSUInteger resourceGeneration;
@property(nonatomic) NSUInteger submissionGeneration;
@end
@implementation LSGCState
- (void)dealloc { [_dateHost removeFromSuperlayer]; }
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
    NSMutableDictionary *values=[@{@"enabled":@YES,@"color1":@"#39D6ED",@"color2":@"#4D7CFF",@"color3":@"#AD4DF5",@"color4":@"#F950B0",@"color5":@"#FFBD61",@"direction":@0,@"opacity":@0.65,@"animate":@NO,@"strictScope":@YES,@"maskMode":@0,@"glassBlend":@YES,@"glassTint":@0.32,@"edgeEnabled":@NO,@"edgePalette":@0,@"edgeCore":@0.22,@"edgeStrength":@0.65,@"edgeWidth":@1.5,@"edgeHighlight":@0.35,@"edgeReveal":@NO,@"customAngleEnabled":@NO,@"gradientAngle":@0,@"customStopsEnabled":@NO,@"stop1":@0,@"stop2":@0.25,@"stop3":@0.5,@"stop4":@0.75,@"stop5":@1,@"reverseColors":@NO,@"independentEdges":@NO,@"edgeColor1":@"#D0FAFF",@"edgeColor2":@"#B39CFF",@"edgeColor3":@"#F7A9DD",@"timeShift":@NO,@"parallaxAngle":@NO,@"scheduleEnabled":@NO,@"hideNativeClock":@NO} mutableCopy];
    // Standalone native lock-screen clock mode: no Liquidify object is required.
    values[@"dateGradient"]=@YES;
    values[@"clockScale"]=@2.35;
    values[@"clockWidth"]=@1.0;
    values[@"clockSpacing"]=@0.0;
    values[@"clockColonScale"]=@1.0;
    values[@"clockOffsetY"]=@0.0;
    values[@"clockOffsetX"]=@0.0;
    values[@"clockHeight"]=@1.0;
    values[@"fontName"]=@"";
    values[@"fontPath"]=@"";
    values[@"fontFamily"]=@"";
    values[@"clockOpacity"]=@1.0;
    values[@"clockWeight"]=@0.8;
    values[@"clockEdgeEnabled"]=@YES;
    values[@"clockEdgeWidth"]=@1.5;
    values[@"clockEdgeStrength"]=@1.0;
    values[@"clockEdgeColor"]=@"#FFFFFF";
    for (NSString *key in values.allKeys) {
        id value=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,(__bridge CFStringRef)Domain));
        if (value) values[key]=value;
    }
    Config=values; Revision++; RegisterUserFont();
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
static BOOL ClockDateText(NSString *s) {
    if (TimeText(s)) return YES;
    if (!s.length || s.length>64) return NO;
    BOOL hasDateMarker=[s containsString:@"年"] || [s containsString:@"月"] ||
        [s containsString:@"日"] || [s containsString:@"星期"] ||
        [s containsString:@"周"] || [s containsString:@"农历"] ||
        [s containsString:@"閏"] || [s containsString:@"闰"];
    if (!hasDateMarker) return NO;
    NSUInteger digits=0;
    for (NSUInteger i=0;i<s.length;i++) if ([NSCharacterSet.decimalDigitCharacterSet characterIsMember:[s characterAtIndex:i]]) digits++;
    if (digits>0 || [s containsString:@"星期"] || [s containsString:@"周"] || [s containsString:@"农历"]) return YES;
    // Lunar dates commonly omit both Arabic digits and the calendar name.
    return [s rangeOfString:@"[闰閏]?(正|冬|腊|臘|十[一二]?|[一二三四五六七八九])月(初[一二三四五六七八九十]|十[一二三四五六七八九]?|二十|廿[一二三四五六七八九]?|三十)"
                   options:NSRegularExpressionSearch].location!=NSNotFound;
}
static BOOL GradientText(NSString *s) {
    return TimeText(s) || ([Config[@"dateGradient"] boolValue] && ClockDateText(s));
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
static BOOL IsDateSubtitleView(NSString *name) {
    return [name isEqualToString:@"CSProminentSubtitleDateView"] ||
        [name containsString:@"SubtitleDate"] ||
        [name containsString:@"LockScreenDateSubtitle"];
}
static BOOL IsVibrancyView(NSString *name) {
    return [name isEqualToString:@"BSUIVibrancyEffectView"] || [name hasSuffix:@"VibrancyEffectView"];
}
static BOOL IsStandaloneTimeLabel(UILabel *label) {
    const char *names[64]; unsigned count=0;
    for (UIView *view=label; view && count<64; view=view.superview)
        names[count++]=class_getName(view.class);
    return LSGCMainClockChain(names,count);
}
// Select before visibility: the transparent source wrapper is not on the
// sibling overlay's render path. Identity is the complete exact main-time chain.
static UIView *ClockSourceWrapper(UILabel *label) {
    const char *names[64]; UIView *views[64]; unsigned count=0;
    for (UIView *v=label; v && count<64; v=v.superview) {
        names[count]=class_getName(v.class); views[count++]=v;
    }
    int index=LSGCClockWrapperIndex(names,count);
    return index<0 ? nil : views[index];
}
static UIView *ClockSelectOverlayParent(UILabel *label, NSString **reason) {
    if (!IsStandaloneTimeLabel(label)) { if (reason) *reason=@"identity"; return nil; }
    UIView *wrapper=ClockSourceWrapper(label);
    if (!wrapper) { if (reason) *reason=@"sibling-wrapper-missing:requires-direct-UIView-parent-of-time-or-label"; return nil; }
    BOOL bypass=LSGCAllowSourceWrapper(true, wrapper.class==UIView.class,
        true, wrapper.hidden, wrapper.alpha);
    if (!bypass) {
        if (reason) *reason=wrapper.hidden ? @"sibling-wrapper-hidden" :
            (wrapper.class!=UIView.class ? @"sibling-wrapper-class" : @"sibling-wrapper-alpha-not-zero");
        return nil; // Native glyph fallback, never a native-label custom host.
    }
    if (!wrapper.superview) { if (reason) *reason=@"sibling-host-missing"; return nil; }
    UIView *host=wrapper.superview;
    if (reason) *reason=@"alpha-zero-wrapper-sibling";
    return host;
}
static UIView *ClockOverlayParent(UILabel *label, NSString **reason) {
    // Never run Visible(label) or a label->window alpha gate before selection.
    UIView *host=ClockSelectOverlayParent(label,reason);
    if (!host) return nil;
    UIView *wrapper=ClockSourceWrapper(label);
    BOOL bypass=wrapper && host==wrapper.superview && wrapper.class==UIView.class && wrapper.alpha==0.0 && !wrapper.hidden;
    if (!label.window || host.window!=label.window) { if (reason) *reason=@"identity-or-window"; return nil; }
    CGRect hostRect=[host convertRect:host.bounds toView:label.window];
    if (CGRectIsEmpty(hostRect) || CGRectIsNull(hostRect) || CGRectIsInfinite(hostRect) ||
        !isfinite(hostRect.origin.x) || !isfinite(hostRect.origin.y) ||
        !isfinite(hostRect.size.width) || !isfinite(hostRect.size.height) ||
        !CGRectIntersectsRect(hostRect,label.window.bounds)) {
        if (reason) *reason=@"sibling-host-invalid-or-offscreen-rect"; return nil;
    }
    // Source-only validation: skip alpha/opacity on exactly the chosen wrapper,
    // not hidden, other low-alpha views, or any ancestor of the visible host.
    for (UIView *v=label; v && v!=host; v=v.superview) {
        CALayer *shown=(CALayer *)v.layer.presentationLayer ?: v.layer;
        if (v.hidden || v.layer.hidden || shown.hidden ||
            (!(bypass && v==wrapper) && (!isfinite(v.alpha) || v.alpha<0.01 ||
                !isfinite(v.layer.opacity) || v.layer.opacity<0.01 || !isfinite(shown.opacity) || shown.opacity<0.01))) {
            if (reason) *reason=[@"hidden-or-low-alpha:" stringByAppendingString:NSStringFromClass(v.class)]; return nil;
        }
        if (!CATransform3DIsAffine(v.layer.transform) || !CATransform3DIsAffine(v.layer.sublayerTransform)) {
            if (reason) *reason=@"unsupported-source-3d-transform"; return nil;
        }
    }
    CGFloat effectiveOpacity=1;
    CGRect visibleRect=[label convertRect:label.bounds toView:label.window];
    if (CGRectIsEmpty(visibleRect) || CGRectIsNull(visibleRect) || CGRectIsInfinite(visibleRect) ||
        !isfinite(visibleRect.origin.x) || !isfinite(visibleRect.origin.y) ||
        !isfinite(visibleRect.size.width) || !isfinite(visibleRect.size.height)) {
        if (reason) *reason=@"source-off-screen"; return nil;
    }
    visibleRect=CGRectIntersection(visibleRect,label.window.bounds);
    // All visibility/clip gates now follow the selected host's actual ancestry.
    for (UIView *v=host; v; v=v.superview) {
        CALayer *shown=(CALayer *)v.layer.presentationLayer ?: v.layer;
        if (v.hidden || v.layer.hidden || shown.hidden || !isfinite(v.alpha) || v.alpha<0.01 ||
            !isfinite(v.layer.opacity) || v.layer.opacity<0.01 || !isfinite(shown.opacity) || shown.opacity<0.01) {
            if (reason) *reason=[@"hidden-or-low-alpha:" stringByAppendingString:NSStringFromClass(v.class)]; return nil;
        }
        effectiveOpacity*=MIN(v.layer.opacity,shown.opacity);
        if (!CATransform3DIsAffine(v.layer.transform) || !CATransform3DIsAffine(v.layer.sublayerTransform) ||
            !CATransform3DIsAffine(shown.transform) || !CATransform3DIsAffine(shown.sublayerTransform)) {
            if (reason) *reason=@"unsupported-host-3d-transform"; return nil;
        }
        if (v.layer.mask || shown.mask) {
            if (reason) *reason=[@"unsupported-host-layer-mask:" stringByAppendingString:NSStringFromClass(v.class)]; return nil;
        }
        if (v.clipsToBounds || v.layer.masksToBounds || shown.masksToBounds)
            visibleRect=CGRectIntersection(visibleRect,[v convertRect:v.bounds toView:label.window]);
    }
    if (effectiveOpacity<0.01 || CGRectIsEmpty(visibleRect) || CGRectIsNull(visibleRect)) {
        if (reason) *reason=effectiveOpacity<0.01 ? @"host-low-effective-opacity" : @"source-off-screen"; return nil;
    }
    return host;
}
static BOOL ClockHostVisible(UILabel *label, LSGCState *s) {
    UIView *host=ClockOverlayParent(label,NULL);
    if (!host || host!=s.clockHost || s.dateHost.hidden || s.gradient.hidden) return NO;
    CGFloat effectiveOpacity=1;
    for (CALayer *layer=s.dateHost; layer; layer=layer.superlayer) {
        CALayer *shown=(CALayer *)layer.presentationLayer ?: layer;
        if (layer.hidden || shown.hidden || layer.opacity<0.01 || shown.opacity<0.01) return NO;
        effectiveOpacity*=MIN(layer.opacity,shown.opacity);
    }
    return effectiveOpacity*s.gradient.opacity>=0.01;
}
static UIView *DateOverlayParent(UILabel *label) {
    // A sibling of the actual time label inherits every native ancestor
    // transform/animation (notification reflow, swipe and clock shrink).
    // Do not move time out of its animated hierarchy as we do for date vibrancy.
    if (IsStandaloneTimeLabel(label)) return nil; // Main time never enters the date-only route.
    BOOL subtitle=NO;
    UIView *dateView=nil, *parent=nil;
    for (UIView *view=label.superview;view;view=view.superview) {
        NSString *name=NSStringFromClass(view.class);
        if ([name isEqualToString:@"CSProminentTimeView"]) return nil;
        if (IsDateSubtitleView(name)) { subtitle=YES; dateView=view; }
        if (subtitle && !parent && IsVibrancyView(name)) parent=view.superview;
        if ([name isEqualToString:@"SBFLockScreenDateView"])
            return subtitle ? (parent ?: dateView) : nil;
    }
    return nil;
}
static void Schedule(UILabel *label) {
    DiagInc(&DiagSchedule);
    if (!NSThread.isMainThread || Rendering || !StartupComplete) {
        DiagScheduleReturn=!NSThread.isMainThread ? @"not-main-thread" : (Rendering ? @"snapshot-rendering" : @"startup-incomplete"); return;
    }
    if (!Hooked && IsStandaloneTimeLabel(label)) InstallHooks();
    BOOL tracked=objc_getAssociatedObject(label,&StateKey)!=nil;
    BOOL glass=GlassClass && [label isKindOfClass:GlassClass];
    if (!tracked && !glass && !IsStandaloneTimeLabel(label) && !DateOverlayParent(label)) { DiagScheduleReturn=@"not-tracked/glass/date-or-main-clock"; return; }
    BOOL pending=objc_getAssociatedObject(label,&PendingKey)!=nil;
    if (!LSGCShouldQueueWake(pending)) { DiagScheduleReturn=@"already-pending"; return; }
    DiagScheduleReturn=@"queued";
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
static CGFloat MaskScale(CGSize size) {
    CGFloat screen=UIScreen.mainScreen.scale;
    if (screen<1) screen=1;
    CGFloat area=size.width*size.height;
    if (!(area>0)) return MIN(screen,3);
    CGFloat fit=sqrt((1024.0*1024.0)/area);
    return MAX(1,MIN(screen,fit));
}
static UIImage *SnapshotMask(CALayer *source,CGFloat scale) {
    CGSize size=source.bounds.size;
    if (!HasInk(source,0) || size.width<1 || size.height<1 || size.width>2048 || size.height>2048) return nil;
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];
    format.opaque=NO; format.scale=MAX(1,scale);
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextTranslateCTM(context.CGContext,-source.bounds.origin.x,-source.bounds.origin.y);
        [source renderInContext:context.CGContext];
    }];
    return HasAlpha(image) ? image : nil;
}
// CoreText outlines avoid UILabel's native-sized backing-store clipping and
// line truncation. Preserve run fonts/kern/colon sizing; normalize true bearings.
static UIImage *SnapshotClockGlyphs(UILabel *label,NSAttributedString *text,CGFloat scale) {
    if (!text.length) return nil;
    CTLineRef line=CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)text);
    if (!line) return nil;
    CGMutablePathRef glyphs=CGPathCreateMutable();
    CFArrayRef runs=CTLineGetGlyphRuns(line);
    BOOL valid=YES;
    for (CFIndex i=0;i<CFArrayGetCount(runs) && valid;i++) {
        CTRunRef run=(CTRunRef)CFArrayGetValueAtIndex(runs,i);
        CTFontRef font=(CTFontRef)CFDictionaryGetValue(CTRunGetAttributes(run),kCTFontAttributeName);
        CFIndex count=CTRunGetGlyphCount(run);
        if (!font || count<=0 || count>256) { valid=NO; break; }
        CGGlyph ids[256]; CGPoint positions[256];
        CTRunGetGlyphs(run,CFRangeMake(0,count),ids);
        CTRunGetPositions(run,CFRangeMake(0,count),positions);
        for (CFIndex j=0;j<count;j++) {
            CGPathRef path=CTFontCreatePathForGlyph(font,ids[j],NULL);
            if (!path || CGPathIsEmpty(path)) { if (path) CGPathRelease(path); valid=NO; break; }
            CGAffineTransform move=CGAffineTransformMakeTranslation(positions[j].x,positions[j].y);
            CGPathAddPath(glyphs,&move,path); CGPathRelease(path);
        }
    }
    CFRelease(line);
    CGRect ink=CGPathGetPathBoundingBox(glyphs);
    if (!valid || CGRectIsEmpty(ink) || CGRectIsInfinite(ink) || CGRectIsNull(ink)) { CGPathRelease(glyphs); return nil; }
    CGFloat weight=Clamp([Config[@"clockWeight"] doubleValue],0,4);
    CGFloat edge=[Config[@"clockEdgeEnabled"] boolValue] ? Clamp([Config[@"clockEdgeWidth"] doubleValue],0.5,6) : 0;
    LSGCClockCanvas canvas=LSGCFullClockCanvas(label.bounds.size.width,label.bounds.size.height,ink.size.width,ink.size.height,weight,edge);
    CGSize size=CGSizeMake(canvas.width,canvas.height);
    // Include padding in the supersampling budget, never resize a clipped image.
    scale=MAX(1,MIN(scale,MIN(4096.0/MAX(size.width,size.height),sqrt(8388608.0/MAX(1,size.width*size.height)))));
    if (size.width>4096 || size.height>4096 || size.width*size.height>8388608) { CGPathRelease(glyphs); return nil; }
    CGAffineTransform normalize=CGAffineTransformMake(1,0,0,-1,size.width*.5-CGRectGetMidX(ink),size.height*.5+CGRectGetMidY(ink));
    CGPathRef path=CGPathCreateCopyByTransformingPath(glyphs,&normalize); CGPathRelease(glyphs);
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];
    format.opaque=NO; format.scale=scale;
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextRef ctx=context.CGContext;
        CGContextSetFillColorWithColor(ctx,UIColor.whiteColor.CGColor);
        CGContextSetStrokeColorWithColor(ctx,UIColor.whiteColor.CGColor);
        CGContextSetLineJoin(ctx,kCGLineJoinRound); CGContextSetLineWidth(ctx,2*weight);
        CGContextAddPath(ctx,path);
        CGContextDrawPath(ctx,weight>0 ? kCGPathFillStroke : kCGPathFill);
    }];
    LSGCState *state=objc_getAssociatedObject(label,&StateKey);
    state.clockCanvasSize=size;
    if (!state.clockRim) { state.clockRim=[CAShapeLayer layer]; state.clockRim.name=@"LSGC.ClockOutline"; }
    state.clockRim.path=path;
    state.clockRim.lineJoin=kCALineJoinRound;
    state.clockRim.lineWidth=2*(weight+edge);
    state.clockRim.masksToBounds=NO;
    CGPathRelease(path);
    DiagCaptureMask(image,size,scale);
    return HasAlpha(image) ? image : nil;
}
static UIImage *SnapshotText(UILabel *label,CGFloat scale) {
    BOOL clock=IsStandaloneTimeLabel(label);
    NSString *fontName=clock && [Config[@"fontName"] isKindOfClass:NSString.class] ? Config[@"fontName"] : @"";
    UIFont *customFont=nil;
    if (clock && ImportedFont && fontName.length) customFont=[ImportedFont fontWithSize:label.font.pointSize];
    else if (fontName.length) customFont=[UIFont fontWithName:fontName size:label.font.pointSize];
    UILabel *mirror=[[UILabel alloc] initWithFrame:(CGRect){CGPointZero,label.bounds.size}];
    mirror.contentScaleFactor=MAX(1,scale);
    mirror.layer.contentsScale=MAX(1,scale);
    mirror.layer.shouldRasterize=NO;
    mirror.font=customFont ?: label.font;
    mirror.textColor=UIColor.whiteColor;
    mirror.textAlignment=label.textAlignment; mirror.numberOfLines=label.numberOfLines;
    mirror.lineBreakMode=label.lineBreakMode; mirror.adjustsFontSizeToFitWidth=label.adjustsFontSizeToFitWidth;
    mirror.minimumScaleFactor=label.minimumScaleFactor; mirror.baselineAdjustment=label.baselineAdjustment;
    // Replace the font attribute too; attributedText otherwise overrides mirror.font.
    NSAttributedString *source=label.attributedText;
    if (![source isKindOfClass:NSAttributedString.class]) source=nil;
    if (!source.length && label.text.length) source=[[NSAttributedString alloc] initWithString:label.text attributes:@{NSFontAttributeName:mirror.font}];
    if (source.length) {
        NSMutableAttributedString *text=[source mutableCopy]; NSRange all=NSMakeRange(0,text.length);
        [text addAttribute:NSForegroundColorAttributeName value:UIColor.whiteColor range:all];
        if (customFont) [text addAttribute:NSFontAttributeName value:customFont range:all];
        if (clock) {
            CGFloat spacing=Clamp([Config[@"clockSpacing"] doubleValue],-10,20);
            if (fabs(spacing)>0.01) [text addAttribute:NSKernAttributeName value:@(spacing) range:all];
            CGFloat colonScale=Clamp([Config[@"clockColonScale"] doubleValue],0.5,1.5);
            if (fabs(colonScale-1.0)>0.01) {
                NSString *string=text.string;
                for (NSUInteger i=0;i<string.length;i++) {
                    unichar ch=[string characterAtIndex:i];
                    if (ch==':' || ch==0xFF1A || ch==0x2236) {
                        NSRange r=NSMakeRange(i,1);
                        UIFont *base=customFont ?: label.font;
                        UIFont *colon=[UIFont fontWithDescriptor:base.fontDescriptor size:base.pointSize*colonScale];
                        [text addAttribute:NSFontAttributeName value:colon range:r];
                    }
                }
            }
        }
        [text removeAttribute:NSBackgroundColorAttributeName range:all];
        [text removeAttribute:NSShadowAttributeName range:all];
        if (!clock) {
            // Native attributed outline must not hollow or double the alpha mask.
            [text removeAttribute:NSStrokeWidthAttributeName range:all];
            [text removeAttribute:NSStrokeColorAttributeName range:all];
        }
        mirror.attributedText=text;
    } else mirror.text=label.text;
    if (clock) return SnapshotClockGlyphs(label,mirror.attributedText,scale);
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];
    format.opaque=NO; format.scale=MAX(1,scale);
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:mirror.bounds.size format:format];
    [mirror setNeedsLayout]; [mirror layoutIfNeeded];
    [mirror.layer setNeedsDisplay]; [mirror.layer displayIfNeeded];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        // Render the complete UILabel once. Passing textRect to drawTextInRect:
        // can apply vertical alignment twice and clip oversized clock fonts.
        [mirror.layer renderInContext:context.CGContext];
    }];
    if (clock) DiagCaptureMask(image,label.bounds.size,scale);
    return HasAlpha(image) ? image : nil;
}
// Preserve original highlights by fading tint at the glyph boundary.
// This edits only our copied mask, never Liquidify's own mask or filters.
static UIImage *GlassTintMask(UIImage *image) {
    if (!image.CGImage) return image;
    size_t w=CGImageGetWidth(image.CGImage), h=CGImageGetHeight(image.CGImage);
    if (!w || !h || w>4096 || h>4096) return image;
    size_t bytes=w*h*4;
    unsigned char *pixels=(unsigned char *)calloc(bytes,1);
    unsigned char *alpha=(unsigned char *)malloc(w*h);
    if (!pixels || !alpha) { free(pixels); free(alpha); return image; }
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(pixels,w,h,8,w*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) { free(pixels); free(alpha); return image; }
    CGContextDrawImage(ctx,CGRectMake(0,0,w,h),image.CGImage);
    for (size_t i=0;i<w*h;i++) alpha[i]=pixels[i*4+3];
    size_t d=(size_t)MAX(1,lround(image.scale*1.2));
    for (size_t y=0;y<h;y++) for (size_t x=0;x<w;x++) {
        size_t i=y*w+x; unsigned char a=alpha[i];
        unsigned char inner=0;
        if (x>=d && y>=d && x+d<w && y+d<h) {
            inner=MIN(MIN(alpha[i-d],alpha[i+d]),MIN(alpha[i-d*w],alpha[i+d*w]));
        }
        unsigned char out=(unsigned char)lround(a*(0.15+0.85*inner/255.0));
        pixels[i*4]=pixels[i*4+1]=pixels[i*4+2]=pixels[i*4+3]=out;
    }
    CGImageRef result=CGBitmapContextCreateImage(ctx);
    UIImage *output=result ? [UIImage imageWithCGImage:result scale:image.scale orientation:image.imageOrientation] : image;
    if (result) CGImageRelease(result);
    CGContextRelease(ctx); free(pixels); free(alpha);
    return output;
}
// Only reorder against an actual sibling; never lift a glass container above its backdrop.
static void PlaceTint(CALayer *host, CAGradientLayer *tint, UILabel *label, BOOL glass) {
    UIView *rim=ReadObject(label,@"rimView");
    CALayer *edge=[rim isKindOfClass:UIView.class] ? rim.layer : nil;
    if (glass && edge.superlayer==host && !rim.hidden && rim.alpha>0.01) {
        tint.zPosition=edge.zPosition;
        NSArray *layers=host.sublayers;
        NSUInteger ti=[layers indexOfObjectIdenticalTo:tint], ei=[layers indexOfObjectIdenticalTo:edge];
        if (tint.superlayer!=host || ti==NSNotFound || ti+1!=ei) {
            [tint removeFromSuperlayer]; [host insertSublayer:tint below:edge];
        }
    } else {
        tint.zPosition=100;
        if (tint.superlayer!=host) { [tint removeFromSuperlayer]; [host addSublayer:tint]; }
    }
}

// New effect owns its own layers. Nothing here changes Liquidify's native layers.
static void ClearEdges(LSGCState *s) {
    [s.edgeHost removeFromSuperlayer];
    [s.edgeBevel removeAllAnimations];
    s.edgeHost=nil; s.edgeTint=nil; s.edgeMask=nil; s.edgeBevel=nil;
}
static CGFloat Quantize(CGFloat value,CGFloat scale) {
    if (!(scale>0) || !isfinite(value)) return 0;
    return round(value*scale)/scale;
}
static NSString *QuantizedRect(CGRect rect,CGFloat scale) {
    return [NSString stringWithFormat:@"%.3f,%.3f,%.3f,%.3f",Quantize(rect.origin.x,scale),Quantize(rect.origin.y,scale),Quantize(rect.size.width,scale),Quantize(rect.size.height,scale)];
}
static BOOL AlwaysOn(UIView *view) {
    for (UIView *v=view; v; v=v.superview) {
        if ([NSStringFromClass(v.class) containsString:@"AlwaysOn"]) return YES;
        for (UIResponder *r=v; r; r=r.nextResponder) {
            if ([NSStringFromClass(r.class) containsString:@"AlwaysOn"]) return YES;
            if ([r isKindOfClass:UIWindow.class]) break;
        }
    }
    return NO;
}
static NSUInteger MotionBits(UIView *view) {
    NSUInteger bits=0;
    if (UIAccessibilityIsReduceMotionEnabled()) bits|=1;
    if (NSProcessInfo.processInfo.lowPowerModeEnabled) bits|=2;
    if (AlwaysOn(view)) bits|=4;
    if (UIAccessibilityIsReduceTransparencyEnabled()) bits|=8;
    return bits;
}
static NSString *SeparatorCodes(NSString *text) {
    if (!text.length) return @"无";
    NSMutableArray *codes=[NSMutableArray array];
    NSCharacterSet *digits=NSCharacterSet.decimalDigitCharacterSet;
    NSUInteger limit=MIN(text.length,(NSUInteger)24);
    [text enumerateSubstringsInRange:NSMakeRange(0,limit) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *sub,NSRange substringRange,NSRange enclosingRange,BOOL *stop) {
        (void)substringRange; (void)enclosingRange;
        if (!sub.length) return;
        unichar c=[sub characterAtIndex:0];
        if ([digits characterIsMember:c] || [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:c]) return;
        NSString *code=[NSString stringWithFormat:@"U+%04X",(unsigned)c];
        if (![codes containsObject:code] && codes.count<6) [codes addObject:code];
        if (codes.count>=6) *stop=YES;
    }];
    return codes.count ? [codes componentsJoinedByString:@","] : @"无";
}
static NSString *DescribeMask(UILabel *label,CALayer **sourceOut,CALayer **ownerOut,CALayer **hostOut,BOOL *nativeOut,NSUInteger *motionOut,BOOL *glassOut,BOOL *edgesOut,CGFloat *scaleOut) {
    CALayer *source=ReadObject(label,@"textMaskLayer");
    if (![source isKindOfClass:CALayer.class]) source=nil;
    CALayer *owner=source ? MaskOwner(label.layer,source,0) : nil;
    BOOL native=owner && [Config[@"maskMode"] integerValue]!=1;
    NSUInteger motion=MotionBits(label);
    BOOL glass=[Config[@"glassBlend"] boolValue] && (motion&8)==0;
    BOOL edges=NO;
    CGFloat scale=MaskScale(label.bounds.size);
    LSGCState *state=objc_getAssociatedObject(label,&StateKey);
    CALayer *host=native ? owner : label.layer;
    if ([state.maskMode isEqualToString:@"同字体文字重绘"]) host=label.layer;
    if (sourceOut) *sourceOut=source;
    if (ownerOut) *ownerOut=owner;
    if (hostOut) *hostOut=host;
    if (nativeOut) *nativeOut=native;
    if (motionOut) *motionOut=motion;
    if (glassOut) *glassOut=glass;
    if (edgesOut) *edgesOut=edges;
    if (scaleOut) *scaleOut=scale;
    return [NSString stringWithFormat:@"%@|%@|%@|%p|%p|%@|%@|%@|%p|%@|%d|%d|%.3f|%.3f|%d|%d",
        label.attributedText ?: (id)label.text,QuantizedRect(label.bounds,scale),label.font,source,(__bridge void *)source.contents,
        QuantizedRect(source ? source.frame : CGRectZero,scale),QuantizedRect(source ? source.bounds : CGRectZero,scale),
        source ? [NSValue valueWithCATransform3D:source.transform] : @"none",owner,QuantizedRect(owner ? owner.bounds : label.bounds,scale),
        ReadFlag(label,@"cachedBuildFinished"),native,scale,0.0,glass,edges];
}
static void ConsiderWallpaper(UIView *view,NSArray<NSString *> *needles,NSUInteger depth,UIView **best,CGFloat *bestArea) {
    if (!view || depth>28) return;
    NSString *name=NSStringFromClass(view.class);
    for (NSString *needle in needles) if ([name containsString:needle]) {
        CGFloat area=view.bounds.size.width*view.bounds.size.height;
        if (!view.hidden && view.alpha>0.05 && area>180*180 && area>*bestArea) { *bestArea=area; *best=view; }
        break;
    }
    for (UIView *child in view.subviews) ConsiderWallpaper(child,needles,depth+1,best,bestArea);
}
static UIView *WallpaperView(void) {
    UIView *best=nil; CGFloat area=0;
    NSArray *needles=@[@"Wallpaper",@"Poster"];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) ConsiderWallpaper(window,needles,0,&best,&area);
    }
    return best;
}
static void UpdateParallax(void) {
    BOOL quiet=UIAccessibilityIsReduceMotionEnabled() || NSProcessInfo.processInfo.lowPowerModeEnabled;
    if (![Config[@"parallaxAngle"] boolValue] || quiet) { ParallaxDegrees=0; return; }
    CFTimeInterval now=CACurrentMediaTime();
    if (ParallaxStamp>0 && now-ParallaxStamp<0.25) return;
    ParallaxStamp=now;
    UIView *wall=WallpaperView();
    CALayer *layer=wall ? (wall.layer.presentationLayer ?: wall.layer) : nil;
    CGFloat shift=layer ? layer.transform.m41 : 0;
    ParallaxDegrees=wall ? Clamp(shift/40.0*12.0,-12,12) : 0;
}
static NSUInteger StyleToken(NSUInteger motionBits) {
    NSUInteger token=((NSUInteger)Revision) ^ (motionBits<<16);
    BOOL quiet=(motionBits&7)!=0;
    if ([Config[@"timeShift"] boolValue] && !quiet) {
        NSDateComponents *parts=[[NSCalendar currentCalendar] components:(NSCalendarUnitHour|NSCalendarUnitMinute) fromDate:[NSDate date]];
        token ^= (NSUInteger)(parts.hour*60+parts.minute);
    }
    if ([Config[@"parallaxAngle"] boolValue] && !quiet) token ^= ((NSUInteger)lround(ParallaxDegrees*4.0))<<8;
    return token;
}
static UIColor *ShiftedColor(UIColor *color,double hue) {
    CGFloat r=0,g=0,b=0,a=1;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat w=0;
        if (![color getWhite:&w alpha:&a]) return color;
        r=g=b=w;
    }
    double outR,outG,outB;
    LSGCShiftRGB(r,g,b,hue,1,1,&outR,&outG,&outB);
    return [UIColor colorWithRed:outR green:outG blue:outB alpha:a];
}
static void ApplyStyle(UILabel *label,LSGCState *s,CALayer *host,NSUInteger motionBits) {
    NSUInteger token=StyleToken(motionBits);
    BOOL styleDirty=s.revision!=Revision || s.styleToken!=token || s.motionBits!=motionBits;
    BOOL standaloneTime=IsStandaloneTimeLabel(label);
    BOOL glass=[Config[@"glassBlend"] boolValue] && (motionBits&8)==0;
    BOOL quiet=(motionBits&7)!=0;
    s.motionBits=motionBits; s.styleToken=token;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    s.gradient.bounds=(CGRect){CGPointZero,host.bounds.size};
    s.gradient.position=CGPointMake(CGRectGetMidX(host.bounds),CGRectGetMidY(host.bounds));
    s.gradient.opacity=standaloneTime ? LSGCClockFillOpacity([Config[@"clockOpacity"] doubleValue]) : (glass ? Clamp([Config[@"glassTint"] doubleValue],0,0.65) : Clamp([Config[@"opacity"] doubleValue],0,1));
    if (s.dateHost && !standaloneTime) s.gradient.opacity=1;
    if (motionBits&4) s.gradient.opacity*=0.4;
    NSInteger direction=[Config[@"direction"] integerValue];
    double base=[Config[@"customAngleEnabled"] boolValue] ? [Config[@"gradientAngle"] doubleValue] : (direction==1 ? 90 : (direction==2 ? 45 : 0));
    BOOL useAngle=[Config[@"customAngleEnabled"] boolValue] || ([Config[@"parallaxAngle"] boolValue] && !quiet);
    if ([Config[@"parallaxAngle"] boolValue] && !quiet) base+=ParallaxDegrees;
    if (useAngle) {
        double endpoints[4];
        LSGCGradientEndpoints(base,host.bounds.size.width,host.bounds.size.height,endpoints);
        s.gradient.startPoint=CGPointMake(endpoints[0],endpoints[1]);
        s.gradient.endPoint=CGPointMake(endpoints[2],endpoints[3]);
    } else {
        s.gradient.startPoint=direction==1 ? CGPointMake(.5,0) : CGPointMake(0,.5);
        s.gradient.endPoint=direction==1 ? CGPointMake(.5,1) : CGPointMake(1,.5);
        if (direction==2) { s.gradient.startPoint=CGPointMake(0,0); s.gradient.endPoint=CGPointMake(1,1); }
    }
    if (styleDirty) {
        NSArray *defaults=@[@"#39D6ED",@"#4D7CFF",@"#AD4DF5",@"#F950B0",@"#FFBD61"];
        double hue=0;
        if ([Config[@"timeShift"] boolValue] && !quiet) {
            NSDateComponents *parts=[[NSCalendar currentCalendar] components:(NSCalendarUnitHour|NSCalendarUnitMinute) fromDate:[NSDate date]];
            hue=LSGCHueForHour(parts.hour+parts.minute/60.0);
        }
        NSMutableArray *colors=[NSMutableArray array];
        for (NSUInteger i=0;i<5;i++) {
            NSString *key=[NSString stringWithFormat:@"color%lu",(unsigned long)i+1];
            UIColor *c=Color(Config[key],Color(defaults[i],UIColor.whiteColor));
            // Main time keeps opaque ink; all palette/shift decisions are shared.
            if (standaloneTime) c=[c colorWithAlphaComponent:1];
            if (hue!=0) c=ShiftedColor(c,hue);
            [colors addObject:(__bridge id)c.CGColor];
        }
        if ([Config[@"reverseColors"] boolValue]) colors=[[[colors reverseObjectEnumerator] allObjects] mutableCopy];
        s.gradient.colors=colors; s.gradient.locations=@[@0,@0.25,@0.5,@0.75,@1];
        if ([Config[@"customStopsEnabled"] boolValue]) {
            double input[5],output[5];
            for (NSUInteger i=0;i<5;i++) input[i]=[Config[[NSString stringWithFormat:@"stop%lu",(unsigned long)i+1]] doubleValue];
            LSGCOrderedStops(input,output);
            NSMutableArray *locations=[NSMutableArray array];
            for (NSUInteger i=0;i<5;i++) [locations addObject:@(output[i])];
            s.gradient.locations=locations;
        }
        [s.gradient removeAllAnimations];
        if ([Config[@"animate"] boolValue] && (motionBits&7)==0) {
            NSMutableArray *reverse=[NSMutableArray arrayWithArray:[[colors reverseObjectEnumerator] allObjects]];
            CABasicAnimation *a=[CABasicAnimation animationWithKeyPath:@"colors"];
            a.fromValue=colors; a.toValue=reverse; a.duration=6; a.autoreverses=YES; a.repeatCount=HUGE_VALF;
            [s.gradient addAnimation:a forKey:@"LSGC.colors"];
        }
        s.revision=Revision;
    }
    PlaceTint(host,s.gradient,label,glass);
    if (standaloneTime) {
        // Dedicated outline sits behind the solid fill, not an inner low-alpha
        // date contour. Source hierarchy supplies animation geometry only once.
        ClearEdges(s);
        s.gradient.masksToBounds=NO; host.masksToBounds=NO;
        BOOL outlined=[Config[@"clockEdgeEnabled"] boolValue];
        s.clockRim.bounds=s.gradient.bounds; s.clockRim.position=s.gradient.position;
        s.clockRim.fillColor=[Color(Config[@"clockEdgeColor"],UIColor.whiteColor) colorWithAlphaComponent:1].CGColor;
        s.clockRim.strokeColor=s.clockRim.fillColor;
        s.clockRim.opacity=outlined ? Clamp([Config[@"clockEdgeStrength"] doubleValue],0,1) : 0;
        if (motionBits&4) s.clockRim.opacity*=0.4;
        s.clockRim.hidden=!outlined;
        s.clockRim.zPosition=s.gradient.zPosition-0.01;
        if (s.clockRim.superlayer!=host) [host insertSublayer:s.clockRim below:s.gradient];
    } else ClearEdges(s);
    [CATransaction commit];
}
static void InstallMask(LSGCState *s,UIImage *image,BOOL native,CALayer *source,CALayer *host,UILabel *label) {
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    s.mask.contents=(__bridge id)image.CGImage;
    s.mask.contentsScale=image.scale;
    s.mask.contentsGravity=kCAGravityResize;
    s.mask.transform=CATransform3DIdentity;
    if (native && source) {
        s.mask.bounds=source.bounds; s.mask.anchorPoint=source.anchorPoint;
        s.mask.position=CGPointMake(source.position.x-host.bounds.origin.x,source.position.y-host.bounds.origin.y); s.mask.transform=source.transform;
    } else {
        s.mask.anchorPoint=CGPointMake(.5,.5);
        CGSize canvas=IsStandaloneTimeLabel(label) ? s.clockCanvasSize : label.bounds.size;
        s.mask.bounds=(CGRect){CGPointZero,canvas};
        s.mask.position=CGPointMake(canvas.width*.5,canvas.height*.5);
    }
    s.maskMode=native ? @"原插件文字遮罩" : @"同字体文字重绘";
    [CATransaction commit];
}
static void RemoveOverlay(UILabel *label) {
    LSGCState *s=objc_getAssociatedObject(label,&StateKey);
    if (!s) return;
    BOOL clock=IsStandaloneTimeLabel(label);
    if (s.hidOriginalLabel) {
        label.alpha=s.originalAlpha;
        label.hidden=s.originalHidden;
        s.hidOriginalLabel=NO;
    }
    if (s.didUnclipClock) { label.clipsToBounds=s.originalClipsToBounds; s.didUnclipClock=NO; }
    if (s.clockCommitted) { s.clockCommitted=NO; [label setNeedsDisplay]; }
    if (clock) s->wakePolicy.committed=NO;
    if (!clock) s.maskHasInk=NO;
    s.ticket++; s.busy=NO; s.dirty=NO;
    [s.gradient removeFromSuperlayer]; [s.gradient removeAllAnimations];
    [s.dateHost removeFromSuperlayer];
    if (s.clockRim) [s.clockRim removeFromSuperlayer];
    ClearEdges(s);
    // A visibility/host rejection detaches the submission, not the reusable
    // glyph resource. Text/config invalidation explicitly clears this cache.
    if (!clock) { s.signature=nil; s.revision=0; }
}
// Render at the final clock magnification, not native label resolution.
// Cap each dimension and total pixels; no bitmap work for position/transform updates.
static void RemoveOverlayQuiet(UILabel *label) {
    // A quiet removal is an edge, not a fake committed state: preserve the
    // committed->native transition and request one recovery draw only then.
    LSGCState *s=objc_getAssociatedObject(label,&StateKey);
    BOOL restore=s && (s.clockCommitted || s->wakePolicy.committed);
    if (s) {
        s.clockCommitted=NO;
        s->wakePolicy.removeQuiet();
    }
    RemoveOverlay(label);
    if (restore) [label setNeedsDisplay];
}
static CGFloat TextMaskScale(UILabel *label) {
    if (!IsStandaloneTimeLabel(label)) return MaskScale(label.bounds.size);
    CGFloat zoom=Clamp([Config[@"clockScale"] doubleValue],0.80,3.50);
    CGFloat width=Clamp([Config[@"clockWidth"] doubleValue],0.80,1.50);
    CGFloat height=Clamp([Config[@"clockHeight"] doubleValue],0.50,4.00);
    CGSize size=label.bounds.size;
    CGFloat desired=UIScreen.mainScreen.scale*zoom*MAX(width,height);
    CGFloat budget=sqrt((4096.0*2048.0)/MAX(1,size.width*size.height));
    return MAX(1,MIN(desired,MIN(budget,4096.0/MAX(size.width,size.height))));
}
// Suppress only the exact standalone main-time UILabel draw. The custom
// gradient is a sibling host, so this never hides its container or date/lunar views.
// The main enabled switch is a safety link: disabling the plugin always restores
// the native draw, even when hideNativeClock remains stored as ON.
static BOOL NativeClockSuppressionEnabled(void) {
    return [Config[@"enabled"] boolValue] && [Config[@"hideNativeClock"] boolValue];
}
static void RefreshNativeClockSuppression(void) {
    if (!NSThread.isMainThread) return;
    BOOL next=NativeClockSuppressionEnabled();
    if (next==NativeClockSuppressionState) return;
    NativeClockSuppressionState=next;
    // Clear the old UILabel backing store before requesting exactly one redraw.
    // No alpha/hidden mutation and no shared-host mutation are used.
    for (UILabel *label in Labels.allObjects) {
        if (!IsStandaloneTimeLabel(label)) continue;
        label.layer.contents=nil;
        [label.layer setNeedsDisplay];
        [label setNeedsDisplay];
    }
}
static NSString *DateSignature(UILabel *label) {
    // Date/lunar signatures never contain user clock settings.
    NSString *base=[NSString stringWithFormat:@"%@|%@|%@|%ld|%ld|%ld|%d|%g|%ld",
        label.attributedText ?: (id)label.text,label.font,NSStringFromCGSize(label.bounds.size),
        (long)label.numberOfLines,(long)label.textAlignment,(long)label.lineBreakMode,
        label.adjustsFontSizeToFitWidth,label.minimumScaleFactor,(long)label.baselineAdjustment];
    if (!IsStandaloneTimeLabel(label)) return base;
    NSString *result=[base stringByAppendingFormat:@"|%@|%@|%@|%@|%.4f",
        Config[@"fontName"],Config[@"fontPath"],Config[@"clockSpacing"],Config[@"clockColonScale"],TextMaskScale(label)];
    // Outline outsets/weight rebuild only on text or settings changes.
    return [result stringByAppendingFormat:@"|%@|%@|%@",Config[@"clockWeight"],Config[@"clockEdgeWidth"],Config[@"clockEdgeEnabled"]];
}
// Suppress only the glyph draw, never UIView alpha/hidden. The overlay lives
// in a verified visible host; native ancestor transforms are inherited once.
static BOOL ClockReplacementReadyForCommit(UILabel *label) {
    LSGCState *s=objc_getAssociatedObject(label,&StateKey);
    if (!Hooked || !LabelHooked || !s || !IsStandaloneTimeLabel(label) ||
        ![s.hostSelection isEqualToString:@"alpha-zero-wrapper-sibling"]) return NO;
    NSString *name=[Config[@"fontName"] isKindOfClass:NSString.class] ? Config[@"fontName"] : @"";
    BOOL fontReady=!name.length || (ImportedFont!=nil) ||
        (![Config[@"fontPath"] length] && [UIFont fontWithName:name size:label.font.pointSize]!=nil);
    BOOL outlineReady=![Config[@"clockEdgeEnabled"] boolValue] ||
        (s.clockRim.path && s.clockRim.superlayer==s.dateHost && s.clockRim.lineWidth>0);
    BOOL attached=outlineReady && s.clockHost && s.dateHost.superlayer==s.clockHost.layer && s.gradient.superlayer==s.dateHost &&
        s.gradient.mask==s.mask && s.mask.contents!=nil;
    CGRect rect=attached && label.window ? [s.dateHost convertRect:s.dateHost.bounds toLayer:label.window.layer] : CGRectZero;
    BOOL onScreen=!CGRectIsEmpty(rect) && !CGRectIsInfinite(rect) && !CGRectIsNull(rect) &&
        isfinite(rect.origin.x) && isfinite(rect.origin.y) && isfinite(rect.size.width) && isfinite(rect.size.height) &&
        CGRectIntersectsRect(rect,label.window.bounds);
    for (UIView *v=s.clockHost; onScreen && v; v=v.superview) {
        if (v.clipsToBounds || v.layer.masksToBounds || ((CALayer *)v.layer.presentationLayer).masksToBounds) {
            CGRect clip=[v convertRect:v.bounds toView:label.window];
            rect=CGRectIntersection(rect,clip); onScreen=!CGRectIsEmpty(rect) && !CGRectIsNull(rect);
        }
    }
    CGFloat colorAlpha=0;
    for (id color in s.gradient.colors) colorAlpha=MAX(colorAlpha,CGColorGetAlpha((__bridge CGColorRef)color));
    LSGCClockReadiness ready={ [Config[@"enabled"] boolValue], fontReady, s.maskHasInk,
        attached, ClockHostVisible(label,s), onScreen, [s.signature isEqualToString:DateSignature(label)],
        s.gradient.opacity*s.dateHost.opacity*colorAlpha, (bool)(Hooked && LabelHooked) };
    return LSGCCanReplaceClock(ready);
}
static BOOL ClockReplacementReady(UILabel *label) {
    LSGCState *s=objc_getAssociatedObject(label,&StateKey);
    return s && s.clockCommitted && ClockReplacementReadyForCommit(label);
}
static void Apply(UILabel *label) {
    BOOL visualChanged=NO;
    DiagInc(&DiagApply); DiagApplyReturn=@"entered";
    if (!NSThread.isMainThread) { DiagApplyReturn=@"not-main-thread"; return; }
    [Labels addObject:label];
    BOOL isGlassLabel=GlassClass && [label isKindOfClass:GlassClass];
    BOOL clock=IsStandaloneTimeLabel(label);
    LSGCState *clockState=objc_getAssociatedObject(label,&StateKey);
    if (clock && !clockState) {
        clockState=[LSGCState new]; clockState.gradient=[CAGradientLayer layer]; clockState.mask=[CALayer layer];
        clockState.gradient.mask=clockState.mask;
        objc_setAssociatedObject(label,&StateKey,clockState,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (clock) { DiagInc(&DiagMainApply); DiagMainApplyReturn=@"entered"; }
    NSString *hostReason=nil;
    UIView *dateParent=clock ? ClockOverlayParent(label,&hostReason) : DateOverlayParent(label);
    if (clock && !dateParent) {
        LSGCState *failed=objc_getAssociatedObject(label,&StateKey); failed.hostSelection=hostReason;
        DiagApplyReturn=hostReason; DiagCaptureFailure(label,DiagApplyReturn); RemoveOverlayQuiet(label); return;
    }
    if (clock && (!Hooked || !label.superview)) { DiagApplyReturn=!Hooked ? @"hook-not-ready" : @"no-superview"; DiagCaptureFailure(label,DiagApplyReturn); RemoveOverlayQuiet(label); return; }
    if (!isGlassLabel && dateParent) {
        NSString *displayText=label.text ?: label.attributedText.string;
        BOOL allowDate=TimeText(displayText) || [Config[@"dateGradient"] boolValue];
        if (![Config[@"enabled"] boolValue] || !allowDate || !Visible(dateParent) ||
            !(label.text.length || label.attributedText.length) || label.bounds.size.width<1 || label.bounds.size.height<1 ||
            label.bounds.size.width>2048 || label.bounds.size.height>2048) {
            DiagApplyReturn=![Config[@"enabled"] boolValue] ? @"disabled" : (!allowDate ? @"date-disabled" : (!Visible(dateParent) ? @"invisible" : (!(label.text.length || label.attributedText.length) ? @"empty-text" : @"invalid-bounds")));
            if (clock) DiagCaptureFailure(label,DiagApplyReturn);
            RemoveOverlay(label); return;
        }
        LSGCState *state=objc_getAssociatedObject(label,&StateKey);
        if (!state) {
            state=[LSGCState new]; state.gradient=[CAGradientLayer layer]; state.mask=[CALayer layer];
            state.gradient.mask=state.mask;
            objc_setAssociatedObject(label,&StateKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        ClearEdges(state); // Also purge legacy edges on cached date/lunar updates.
        if (clock) { state.clockHost=dateParent; state.hostSelection=hostReason; }
        if (!state.dateHost) { state.dateHost=[CALayer layer]; state.dateHost.name=@"LSGC.DateOverlay"; }
        NSString *signature=DateSignature(label);
        LSGCWakeSnapshot wakeSnapshot;
        if (clock) {
            std::string resourceKey([signature UTF8String] ?: "");
            wakeSnapshot=state->wakePolicy.begin(resourceKey);
            if (state->wakePolicy.failedEarly(wakeSnapshot)) {
                DiagApplyReturn=@"resource-failure-latched";
                RemoveOverlayQuiet(label); state.maskMode=@"资源失败锁存，保留系统文字"; return;
            }
        }
        if (clock && [state.failedResourceKey isEqualToString:signature]) {
            // Stable failure latch: no retry loop until a real input signature changes.
            RemoveOverlayQuiet(label); state.maskMode=@"资源失败锁存，保留系统文字"; return;
        }
        @try {
            BOOL attachedCached=clock && state.gradient.superlayer==state.dateHost;
            BOOL needsMask=!([state.signature isEqualToString:signature] && (!clock || attachedCached));
            if (needsMask) {
                BOOL completeClockResource=clock && LSGCResourceBindingConsistent(
                    std::string([signature UTF8String] ?: ""), state->wakePolicy.resourceGeneration,
                    std::string([state.cachedMaskSignature UTF8String] ?: ""), state.cachedResourceGeneration,
                    state.clockCanvasSize.width, state.clockCanvasSize.height,
                    state.clockRim.path!=nil, state.cachedMask!=nil);
                UIImage *image=(completeClockResource) ? state.cachedMask : nil;
                if (!image) {
                    if (clock) DiagMask=@{ @"source":@"SnapshotText/main-clock", @"status":@"attempted" };
                    @try { Rendering=YES; image=SnapshotText(label,TextMaskScale(label)); }
                    @finally { Rendering=NO; }
                    if (!image || !HasAlpha(image)) {
                        DiagApplyReturn=@"mask-no-ink"; if (clock) DiagCaptureFailure(label,DiagApplyReturn);
                        if (clock) { state.failedResourceKey=signature; state->wakePolicy.failResource(wakeSnapshot); }
                        RemoveOverlayQuiet(label); state.maskMode=@"遮罩无有效像素，保留系统文字"; return;
                    }
                    if (clock) { state.cachedMask=image; state.cachedMaskSignature=signature; state.cachedResourceGeneration=state->wakePolicy.resourceGeneration; state.failedResourceKey=nil; }
                }
                if (clock && !state->wakePolicy.currentResource(wakeSnapshot,std::string([signature UTF8String] ?: ""))) {
                    state.cachedMask=nil; state.cachedMaskSignature=nil; state.clockCanvasSize=CGSizeZero; state.clockRim.path=nil;
                    DiagApplyReturn=@"stale-resource-generation"; RemoveOverlayQuiet(label); return;
                }
                state.maskHasInk=YES;
                InstallMask(state,image,NO,nil,state.dateHost,label);
                // Replace the system glyph while preserving its layout and update path.
                if (!clock && !state.hidOriginalLabel) {
                    state.originalAlpha=label.alpha;
                    state.originalHidden=label.hidden;
                    state.hidOriginalLabel=YES;
                    label.alpha=0.0;
                }
                state.signature=signature;
            }
            // UIKit may restore a date label's alpha while reusing the cached
            // signature. Reassert replacement on every event, not only rebuilds,
            // otherwise native glyphs and the sibling overlay are both visible.
            if (!clock && state.hidOriginalLabel) label.alpha=0.0;
            // Convert geometry through the source hierarchy on each layout tick.
            CGRect frame=[label convertRect:label.bounds toView:dateParent];
            [CATransaction begin]; [CATransaction setDisableActions:YES];
            @try {
                // The reference uses an oversized clock. Keep the native time source,
                // but enlarge only the cached overlay; no per-frame redraw is added.
                CGFloat userScale=IsStandaloneTimeLabel(label) ? Clamp([Config[@"clockScale"] doubleValue],0.80,3.50) : 1.0;
                CGFloat widthScale=IsStandaloneTimeLabel(label) ? Clamp([Config[@"clockWidth"] doubleValue],0.80,1.50) : 1.0;
                CGFloat heightScale=IsStandaloneTimeLabel(label) ? Clamp([Config[@"clockHeight"] doubleValue],0.50,4.00) : 1.0;
                CGFloat offsetX=IsStandaloneTimeLabel(label) ? Clamp([Config[@"clockOffsetX"] doubleValue],-100,100) : 0.0;
                CGFloat offsetY=IsStandaloneTimeLabel(label) ? Clamp([Config[@"clockOffsetY"] doubleValue],-200,200) : 0.0;
                CGFloat sx=frame.size.width/label.bounds.size.width*userScale*widthScale;
                CGFloat sy=frame.size.height/label.bounds.size.height*userScale*heightScale;
                state.dateHost.bounds=(CGRect){CGPointZero,clock ? state.clockCanvasSize : label.bounds.size};
                state.dateHost.position=CGPointMake(CGRectGetMidX(frame)+offsetX,CGRectGetMidY(frame)+offsetY);
                state.dateHost.transform=CATransform3DMakeScale(sx,sy,1);
                if (clock) {
                    // Map basis vectors into the chosen host, retaining source
                    // rotation/shear exactly once; host inherits all higher lock-screen transforms.
                    CGPoint origin=[label convertPoint:CGPointZero toView:dateParent];
                    CGPoint x=[label convertPoint:CGPointMake(1,0) toView:dateParent];
                    CGPoint y=[label convertPoint:CGPointMake(0,1) toView:dateParent];
                    CGPoint center=[label convertPoint:CGPointMake(CGRectGetMidX(label.bounds)+offsetX,CGRectGetMidY(label.bounds)+offsetY) toView:dateParent];
                    state.dateHost.anchorPoint=CGPointMake(.5,.5);
                    state.dateHost.position=center;
                    state.dateHost.transform=CATransform3DMakeAffineTransform(CGAffineTransformMake(
                        (x.x-origin.x)*userScale*widthScale,(x.y-origin.y)*userScale*widthScale,
                        (y.x-origin.x)*userScale*heightScale,(y.y-origin.y)*userScale*heightScale,0,0));
                }
                if (state.dateHost.superlayer!=dateParent.layer) [dateParent.layer addSublayer:state.dateHost];
                if (clock && label.window) {
                    // A 2.35x native clock can exceed the physical display even
                    // with a correct backing canvas. Cap uniform magnification
                    // to screen width, but retain native notification motion and
                    // user offsets; never remap an ancestor transform twice.
                    CGRect visible=[state.dateHost convertRect:state.dateHost.bounds toLayer:label.window.layer];
                    CGFloat available=MAX(1,label.window.bounds.size.width-8);
                    if (isfinite(visible.size.width) && visible.size.width>available) {
                        CGFloat fit=available/visible.size.width;
                        state.dateHost.transform=CATransform3DScale(state.dateHost.transform,fit,fit,1);
                    }
                }
                UpdateParallax();
                NSUInteger oldStyleToken=state.styleToken, oldMotionBits=state.motionBits, oldRevision=state.revision;
                CGRect oldBounds=state.dateHost.bounds; CGPoint oldPosition=state.dateHost.position; CATransform3D oldTransform=state.dateHost.transform;
                ApplyStyle(label,state,state.dateHost,MotionBits(dateParent)|8);
                visualChanged=needsMask || oldStyleToken!=state.styleToken || oldMotionBits!=state.motionBits || oldRevision!=state.revision ||
                    !CGRectEqualToRect(oldBounds,state.dateHost.bounds) || !CGPointEqualToPoint(oldPosition,state.dateHost.position) || !CATransform3DEqualToTransform(oldTransform,state.dateHost.transform);
            } @finally { [CATransaction commit]; }
            if (clock) {
                if (!state->wakePolicy.currentResource(wakeSnapshot,std::string([signature UTF8String] ?: "")) ||
                    !state->wakePolicy.currentSubmission(wakeSnapshot)) {
                    DiagApplyReturn=@"stale-submission-generation"; RemoveOverlayQuiet(label); return;
                }
                if (!ClockReplacementReadyForCommit(label)) {
                    DiagApplyReturn=@"readiness-rejected"; DiagCaptureFailure(label,DiagApplyReturn);
                    // Transient readiness failure advances submission only after
                    // the uncommitted transition; it never commits then rolls back.
                    state->wakePolicy.failTransient();
                    state.submissionGeneration=state->wakePolicy.submissionGeneration;
                    RemoveOverlayQuiet(label); state.maskMode=@"时间替换未就绪，等待生命周期输入"; return;
                }
                BOOL committedEdge=state->wakePolicy.commit(wakeSnapshot);
                if (!committedEdge && !state->wakePolicy.committed) {
                    DiagApplyReturn=@"commit-rejected"; RemoveOverlayQuiet(label); return;
                }
                state.clockCommitted=YES;
                state.resourceGeneration=state->wakePolicy.resourceGeneration;
                state.submissionGeneration=state->wakePolicy.submissionGeneration;
                if (committedEdge || visualChanged) [label setNeedsDisplay];
            }
            DiagApplyReturn=clock ? @"main-clock-committed" : @"date-only";
            if (clock) DiagMainApplyReturn=DiagApplyReturn;
            state.maskMode=clock ? @"主时间独立宿主渐变（安全提交）" : @"日期容器外渐变";
        } @catch (NSException *exception) {
            DiagApplyReturn=[@"exception:" stringByAppendingString:exception.name]; if (clock) DiagCaptureFailure(label,DiagApplyReturn);
            RemoveOverlay(label); state.maskMode=[@"日期渲染异常：" stringByAppendingString:exception.name];
        }
        return;
    }
    // Standalone mode never touches Liquidify labels or their private masks.
    BOOL scoped=![Config[@"strictScope"] boolValue] || InLockScreen(label);
    DiagApplyReturn=@"not-eligible-standalone-clock-or-date";
    RemoveOverlay(label);
    return;
    if (![Config[@"enabled"] boolValue] || !Visible(label) || !GradientText(label.text ?: label.attributedText.string) ||
        !scoped || label.bounds.size.width<1 || label.bounds.size.height<1 ||
        label.bounds.size.width>2048 || label.bounds.size.height>2048) { RemoveOverlay(label); return; }
    LSGCState *s=objc_getAssociatedObject(label,&StateKey);
    if (!s) {
        s=[LSGCState new]; s.gradient=[CAGradientLayer layer]; s.mask=[CALayer layer];
        s.gradient.name=@"LSGC.LiquidifyGradient"; s.gradient.zPosition=100;
        s.gradient.mask=s.mask;
        objc_setAssociatedObject(label,&StateKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (s.busy) { if (!Rendering) s.dirty=YES; return; }
    CALayer *source=nil,*host=nil;
    BOOL native=NO,glass=NO,edges=NO; NSUInteger motion=0; CGFloat scale=1;
    NSString *signature=DescribeMask(label,&source,NULL,&host,&native,&motion,&glass,&edges,&scale);
    BOOL attached=s.gradient.superlayer==host;
    BOOL edgesReady=!edges || !s.edgeHost || s.edgeHost.superlayer==host;
    UpdateParallax();
    if ([s.signature isEqualToString:signature] && s.styleToken==StyleToken(motion) && attached && edgesReady) return;
    if ([s.signature isEqualToString:signature]) { ApplyStyle(label,s,host,motion); return; }
    s.busy=YES;
    UIImage *image=nil; BOOL usedNative=NO;
    @try {
        Rendering=YES;
        image=native ? SnapshotMask(source,scale) : nil;
        usedNative=image!=nil;
        if (!image) { image=SnapshotText(label,scale); usedNative=NO; }
        Rendering=NO;
    } @catch (NSException *exception) {
        Rendering=NO; RemoveOverlay(label);
        s.maskMode=[@"兼容异常：" stringByAppendingString:exception.name];
        s.busy=NO; return;
    }
    if (!image) { RemoveOverlay(label); s.maskMode=@"遮罩为空"; s.busy=NO; return; }
    NSUInteger ticket=++s.ticket;
    BOOL wantGlass=glass;
    __weak UILabel *weak=label; LSGCState *state=s;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        UIImage *tinted=wantGlass ? GlassTintMask(image) : image;
        dispatch_async(dispatch_get_main_queue(), ^{
            UILabel *strong=weak;
            if (!strong || state.ticket!=ticket) {
                return;
            }
            @try {
                CALayer *nowSource=nil,*nowOwner=nil; NSUInteger nowMotion=0;
                NSString *now=DescribeMask(strong,&nowSource,&nowOwner,NULL,NULL,&nowMotion,NULL,NULL,NULL);
                if (![now isEqualToString:signature] || ![Config[@"enabled"] boolValue] || !Visible(strong) || !GradientText(strong.text ?: strong.attributedText.string)) {
                    if ([Config[@"enabled"] boolValue] && Visible(strong) && GradientText(strong.text ?: strong.attributedText.string)) Schedule(strong);
                    else RemoveOverlay(strong);
                } else {
                    CALayer *installHost=(usedNative && nowOwner) ? nowOwner : strong.layer;
                    ClearEdges(state);
                    InstallMask(state,tinted,usedNative && nowOwner!=nil,nowSource,installHost,strong);
                    state.signature=signature;
                    ApplyStyle(strong,state,installHost,nowMotion);
                }
            } @catch (NSException *exception) {
                RemoveOverlay(strong);
                state.maskMode=[@"兼容异常：" stringByAppendingString:exception.name];
            } @finally {
                if (state.ticket==ticket) state.busy=NO;
            }
            if (strong && state.dirty && state.ticket==ticket) { state.dirty=NO; Schedule(strong); }
        });
    });
}
static void InstallHooks(void) {
    DiagInc(&DiagInstall);
    // Standalone implementation: no Liquidify class lookup or private hook.
    InstallLabelHooks(); InstallClockHooks();
    NativeClassesLoaded=NSClassFromString(@"_UIAnimatingLabel") &&
        NSClassFromString(@"CSProminentTimeView") && NSClassFromString(@"CSProminentDisplayView") &&
        NSClassFromString(@"SBFLockScreenDateView");
    // Success means native classes exist AND each actual override is installed.
    // Inherited selectors are covered by the UILabel / UIView base hooks.
    Hooked=LabelHooked && NativeClassesLoaded;
    NSMutableArray *status=[NSMutableArray array];
    for (NSString *name in @[@"SBFLockScreenDateView",@"CSProminentTimeView",@"CSProminentDisplayView",@"_UIAnimatingLabel"]) {
        Class cls=NSClassFromString(name);
        if (!cls) { [status addObject:[name stringByAppendingString:@": 未加载"]]; continue; }
        [status addObject:[name stringByAppendingString:@": 已加载"]];
        unsigned count=0; Method *methods=class_copyMethodList(cls,&count);
        NSArray *selectors=[cls isSubclassOfClass:UILabel.class] ? @[@"layoutSubviews",@"didMoveToWindow",@"drawTextInRect:",@"setText:",@"setAttributedText:"] : @[@"layoutSubviews",@"didMoveToWindow"];
        for (NSString *method in selectors) {
            SEL sel=NSSelectorFromString(method); BOOL own=NO;
            for (unsigned i=0;i<count;i++) if (method_getName(methods[i])==sel) own=YES;
            if (!own) continue;
            NSString *key=[name stringByAppendingFormat:@"/%@",method];
            BOOL ok=[ClockHookKeys containsObject:key];
            Hooked=Hooked && ok;
            [status addObject:[key stringByAppendingString:ok ? @": 已安装" : @": 失败"]];
        }
        free(methods);
    }
    NSString *previousReport=HookReport;
    HookReport=[NSString stringWithFormat:@"standalone-native-clock; UILabel/UIView=%@; %@",
        LabelHooked ? @"已安装" : @"失败",[status componentsJoinedByString:@"; "]];
    if (![previousReport isEqualToString:HookReport]) NSLog(@"[LSGC] installation: %@",HookReport);
}
static void (*OrigViewMove)(id,SEL);
static void ViewMove(id obj,SEL sel) {
    DiagInc(&DiagMove); OrigViewMove(obj,sel);
    if (!StartupComplete || !NSThread.isMainThread || Rendering) return;
    NSString *name=NSStringFromClass([obj class]);
    if ([name isEqualToString:@"SBFLockScreenDateView"] ||
        [name isEqualToString:@"CSProminentDisplayView"] ||
        [name isEqualToString:@"CSProminentTimeView"]) {
        InstallHooks(); Walk((UIView *)obj,0);
    }
}
static void (*OrigLabelDraw)(id,SEL,CGRect);
static void LabelDraw(id obj,SEL sel,CGRect rect) {
    DiagInc(&DiagDraw);
    BOOL main=!Rendering && DiagDrawDepth==0 && IsStandaloneTimeLabel((UILabel *)obj);
    if (main) DiagInc(&DiagMainDraw);
    ++DiagDrawDepth;
    @try {
        if (!Rendering && NativeClockSuppressionEnabled() && IsStandaloneTimeLabel((UILabel *)obj)) {
            if (main) DiagInc(&DiagSuppress);
            return;
        }
        if (!Rendering && ClockReplacementReady((UILabel *)obj)) { if (main) DiagInc(&DiagSuppress); return; }
        if (main) DiagInc(&DiagNative);
        OrigLabelDraw(obj,sel,rect);
    } @finally { --DiagDrawDepth; }
}
static void (*OrigLabelLayout)(id,SEL);
static void (*OrigLabelMove)(id,SEL);
static void (*OrigLabelText)(id,SEL,id);
static void (*OrigLabelAttributed)(id,SEL,id);
static void LabelLayout(id obj,SEL sel) {
    DiagInc(&DiagLayout); OrigLabelLayout(obj,sel); Schedule((UILabel *)obj);
}
static void LabelMove(id obj,SEL sel) {
    DiagInc(&DiagMove); OrigLabelMove(obj,sel); Schedule((UILabel *)obj);
}
static void InvalidateClockResource(UILabel *label) {
    if (!IsStandaloneTimeLabel(label)) return;
    LSGCState *s=objc_getAssociatedObject(label,&StateKey);
    if (!s) return;
    RemoveOverlay(label);
    s.cachedMask=nil; s.cachedMaskSignature=nil; s.cachedResourceGeneration=0; s.failedResourceKey=nil;
    s.clockCanvasSize=CGSizeZero; s.clockRim.path=nil;
    s.signature=nil; s.maskHasInk=NO;
    s->wakePolicy.invalidate();
    s.resourceGeneration=s->wakePolicy.resourceGeneration;
    s.submissionGeneration=s->wakePolicy.submissionGeneration;
}
static char SetterDepthKey;
static BOOL BeginSetter(UILabel *label) {
    NSNumber *n=objc_getAssociatedObject(label,&SetterDepthKey);
    LSGCSetterGuard guard; guard.depth=n ? n.unsignedIntValue : 0;
    BOOL outer=guard.enter();
    objc_setAssociatedObject(label,&SetterDepthKey,@(guard.depth),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return outer;
}
static void EndSetter(UILabel *label) {
    NSNumber *n=objc_getAssociatedObject(label,&SetterDepthKey);
    LSGCSetterGuard guard; guard.depth=n ? n.unsignedIntValue : 0; guard.leave();
    objc_setAssociatedObject(label,&SetterDepthKey,guard.depth ? @(guard.depth) : nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void LabelText(id obj,SEL sel,id value) {
    UILabel *label=(UILabel *)obj; BOOL guarded=IsStandaloneTimeLabel(label); BOOL outer=!guarded || BeginSetter(label);
    NSString *before=[label.text copy];
    @try { OrigLabelText(obj,sel,value); }
    @finally {
        BOOL changed=!((before==label.text) || [before isEqualToString:label.text]);
        if (guarded) EndSetter(label);
        if (outer && changed) InvalidateClockResource(label);
        if (outer) Schedule(label);
    }
}
static void LabelAttributed(id obj,SEL sel,id value) {
    UILabel *label=(UILabel *)obj; BOOL guarded=IsStandaloneTimeLabel(label); BOOL outer=!guarded || BeginSetter(label);
    NSAttributedString *before=[label.attributedText copy];
    @try { OrigLabelAttributed(obj,sel,value); }
    @finally {
        BOOL changed=!((before==label.attributedText) || [before isEqualToAttributedString:label.attributedText]);
        if (guarded) EndSetter(label);
        if (outer && changed) InvalidateClockResource(label);
        if (outer) Schedule(label);
    }
}
static void InstallLabelHooks(void) {
    if (LabelHooked) return;
    Class cls=UILabel.class;
    Method layout=class_getInstanceMethod(cls,@selector(layoutSubviews));
    Method move=class_getInstanceMethod(cls,@selector(didMoveToWindow));
    Method text=class_getInstanceMethod(cls,@selector(setText:));
    Method attributed=class_getInstanceMethod(cls,@selector(setAttributedText:));
    Method draw=class_getInstanceMethod(cls,@selector(drawTextInRect:));
    Method viewMove=class_getInstanceMethod(UIView.class,@selector(didMoveToWindow));
    if (!layout || !move || !text || !attributed || !draw || !viewMove) return;
    // Install only missing hooks: a partial failure must not hook our own IMP again.
    if (!OrigViewMove) MSHookMessageEx(UIView.class,@selector(didMoveToWindow),(IMP)ViewMove,(IMP *)&OrigViewMove);
    if (!OrigLabelLayout) MSHookMessageEx(cls,@selector(layoutSubviews),(IMP)LabelLayout,(IMP *)&OrigLabelLayout);
    if (!OrigLabelMove) MSHookMessageEx(cls,@selector(didMoveToWindow),(IMP)LabelMove,(IMP *)&OrigLabelMove);
    if (!OrigLabelText) MSHookMessageEx(cls,@selector(setText:),(IMP)LabelText,(IMP *)&OrigLabelText);
    if (!OrigLabelAttributed) MSHookMessageEx(cls,@selector(setAttributedText:),(IMP)LabelAttributed,(IMP *)&OrigLabelAttributed);
    if (!OrigLabelDraw) MSHookMessageEx(cls,@selector(drawTextInRect:),(IMP)LabelDraw,(IMP *)&OrigLabelDraw);
    DiagRememberIMP(UIView.class,@selector(didMoveToWindow),(IMP)OrigViewMove,(IMP)ViewMove);
    DiagRememberIMP(cls,@selector(layoutSubviews),(IMP)OrigLabelLayout,(IMP)LabelLayout);
    DiagRememberIMP(cls,@selector(didMoveToWindow),(IMP)OrigLabelMove,(IMP)LabelMove);
    DiagRememberIMP(cls,@selector(setText:),(IMP)OrigLabelText,(IMP)LabelText);
    DiagRememberIMP(cls,@selector(setAttributedText:),(IMP)OrigLabelAttributed,(IMP)LabelAttributed);
    DiagRememberIMP(cls,@selector(drawTextInRect:),(IMP)OrigLabelDraw,(IMP)LabelDraw);
    LabelHooked=OrigViewMove && OrigLabelLayout && OrigLabelMove && OrigLabelText && OrigLabelAttributed && OrigLabelDraw;
}
// Hook overrides as well as UILabel: private animating labels need not call super.
// One block/original IMP per class/selector avoids inherited-hook recursion.
static void InstallClockHooks(void) {
    if (!ClockHookKeys) ClockHookKeys=[NSMutableSet set];
    NSMutableSet<NSString *> *installed=ClockHookKeys;
    for (NSString *name in @[@"SBFLockScreenDateView",@"CSProminentTimeView",@"CSProminentDisplayView",@"_UIAnimatingLabel"]) {
        Class cls=NSClassFromString(name);
        if (!cls) continue;
        BOOL labelClass=[cls isSubclassOfClass:UILabel.class];
        NSArray *selectors=labelClass ? @[@"layoutSubviews",@"didMoveToWindow",@"drawTextInRect:",@"setText:",@"setAttributedText:"] : @[@"layoutSubviews",@"didMoveToWindow"];
        for (NSString *method in selectors) {
            NSString *key=[name stringByAppendingFormat:@"/%@",method];
            SEL sel=NSSelectorFromString(method);
            if ([installed containsObject:key] || !class_getInstanceMethod(cls,sel)) continue;
            // Only actual overrides. Hooking inherited methods duplicates the
            // UILabel hook and can refresh the same layout twice.
            unsigned int count=0; Method *own=class_copyMethodList(cls,&count);
            BOOL overrides=NO;
            for (unsigned int i=0;i<count;i++) if (method_getName(own[i])==sel) overrides=YES;
            free(own); if (!overrides) continue;
            __block IMP original=NULL;
            void (^refresh)(id)=^(id obj) {
                if (Rendering || !NSThread.isMainThread) return;
                if (labelClass) { Schedule((UILabel *)obj); return; }
                // Discover NEW labels in this local subtree, not only the labels
                // captured at SpringBoard startup. No global traversal per tick.
                Walk((UIView *)obj,0);
            };
            IMP hook;
            if ([method isEqualToString:@"setText:"] || [method isEqualToString:@"setAttributedText:"]) {
                hook=imp_implementationWithBlock(^(id obj,id value) {
                    UILabel *label=(UILabel *)obj; BOOL guarded=IsStandaloneTimeLabel(label); BOOL outer=!guarded || BeginSetter(label);
                    NSString *beforeText=[label.text copy];
                    NSAttributedString *beforeAttributed=[label.attributedText copy];
                    @try { ((void(*)(id,SEL,id))original)(obj,sel,value); }
                    @finally {
                        BOOL changed=!((beforeText==label.text || [beforeText isEqualToString:label.text]) &&
                                        (beforeAttributed==label.attributedText || [beforeAttributed isEqual:label.attributedText]));
                        if (guarded) EndSetter(label);
                        if (outer && changed) InvalidateClockResource(label);
                        if (outer) Schedule(label);
                    }
                });
            } else if ([method isEqualToString:@"drawTextInRect:"]) {
                hook=imp_implementationWithBlock(^(id obj,CGRect rect) {
                    DiagInc(&DiagDraw);
                    BOOL main=!Rendering && DiagDrawDepth==0 && IsStandaloneTimeLabel((UILabel *)obj);
                    if (main) DiagInc(&DiagMainDraw);
                    ++DiagDrawDepth;
                    @try {
                        if (!Rendering && NativeClockSuppressionEnabled() && IsStandaloneTimeLabel((UILabel *)obj)) {
                            if (main) DiagInc(&DiagSuppress);
                            return;
                        }
                        if (!Rendering && ClockReplacementReady((UILabel *)obj)) { if (main) DiagInc(&DiagSuppress); return; }
                        if (main) DiagInc(&DiagNative);
                        ((void(*)(id,SEL,CGRect))original)(obj,sel,rect);
                    } @finally { --DiagDrawDepth; }
                });
            } else {
                hook=imp_implementationWithBlock(^(id obj) {
                    if ([method isEqualToString:@"layoutSubviews"]) DiagInc(&DiagLayout); else DiagInc(&DiagMove);
                    ((void(*)(id,SEL))original)(obj,sel); refresh(obj);
                });
            }
            MSHookMessageEx(cls,sel,hook,&original);
            DiagRememberIMP(cls,sel,original,hook);
            if (original) [installed addObject:key];
        }
    }
}
static void Walk(UIView *view,NSUInteger depth) {
    if (!view || depth>64) return;
    if (InLockScreen(view) && [NSStringFromClass(view.class) containsString:@"Date"]) [DateViews addObject:view];
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label=(UILabel *)view;
        BOOL clock=IsStandaloneTimeLabel(label);
        BOOL date=!clock && DateOverlayParent(label)!=nil;
        if (clock || date) { [Labels addObject:label]; Schedule(label); }
    }
    for (UIView *child in view.subviews) Walk(child,depth+1);
}
static void Discover(void) {
    InstallHooks();
    // SpringBoard may retain legacy windows outside connectedScenes.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSArray<UIWindow *> *legacyWindows=UIApplication.sharedApplication.windows;
#pragma clang diagnostic pop
    for (UIWindow *window in legacyWindows) Walk(window,0);
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) Walk(window,0);
    }
}
static void DiscoverAndApply(void) {
    Discover();
    for (UILabel *label in Labels.allObjects) Schedule(label);
}
static void RetryDateDiscover(void) {
    // Date success must never cancel the remaining bounded clock retries.
    LoadConfig(); DiscoverAndApply();
}
#include "LSGCDiagnostics.inc"
static void WriteDiagnostics(void) {
    Discover();
    NSUInteger clocks=0,scoped=0,active=0; NSMutableArray *details=[NSMutableArray array];
    NSUInteger dates=0,dateActive=0;
    NSMutableArray *dateDetails=[NSMutableArray array];
    for (UILabel *label in Labels.allObjects) {
        BOOL time=IsStandaloneTimeLabel(label); clocks+=time;
        BOOL lock=InLockScreen(label); scoped+=(time && lock);
        LSGCState *s=objc_getAssociatedObject(label,&StateKey);
        active+=(time && ClockReplacementReady(label));
        BOOL date=!time && DateOverlayParent(label)!=nil;
        if (date) {
            dates++; dateActive+=(s.gradient.superlayer!=nil);
            if (dateDetails.count<12) [dateDetails addObject:[NSString stringWithFormat:@"%@ bounds=%@ 可见=%d 锁屏=%d 渐变=%d 浓度=%.2f 模式=%@",
                NSStringFromClass(label.class),NSStringFromCGRect(label.bounds),Visible(label),lock,
                s.gradient.superlayer!=nil,s.gradient.opacity,s.maskMode?:@"未渲染"]];
        }
        if (time && details.count<6) {
            NSMutableArray *chain=[NSMutableArray array];
            UIView *v=label;
            for (NSUInteger i=0;v && i<12;i++,v=v.superview) [chain addObject:NSStringFromClass(v.class)];
            NSString *blocked=@"无";
            if (!label.window) blocked=@"未入窗";
            for (UIView *ancestor=label; ancestor; ancestor=ancestor.superview) {
                if (ancestor.hidden || ancestor.alpha<0.01) {
                    blocked=[NSString stringWithFormat:@"%@ hidden=%d alpha=%.3f",NSStringFromClass(ancestor.class),ancestor.hidden,ancestor.alpha]; break;
                }
            }
            NSString *mode=s.maskMode ?: (!Hooked ? @"Hook未就绪，保留系统时间" : (!Visible(label) ? @"原生层不可见，未尝试替换" : @"待布局/渲染，保留系统时间"));
            [details addObject:[NSString stringWithFormat:@"主时间候选=是 时间形态=%@ 锁屏范围=%@ 可见=%@ 分隔符=%@\nbounds=%@ hidden=%d alpha=%.3f 不可见原因=%@\n已渲染=%@ 模式=%@\n%@",TimeText(label.text ?: label.attributedText.string)?@"是":@"否",lock?@"是":@"否",Visible(label)?@"是":@"否",SeparatorCodes(label.text ?: label.attributedText.string),NSStringFromCGRect(label.bounds),label.hidden,label.alpha,blocked,ClockReplacementReady(label)?@"是":@"否",mode,[chain componentsJoinedByString:@" > "]]];
        }
    }
    NSString *report=[NSString stringWithFormat:@"兼容层 %@\n类已加载（原生四类）：%@\nHook 已安装：%@\nHook 明细：%@\n扫描发现（时间+日期）：%lu\n主时间扫描发现：%lu\n主时间锁屏范围命中：%lu\n主时间安全门当前通过（不代表像素上屏）：%lu\n请求开关：%@\n实际时间替换：%@\n构造器初始化：%@\n\n%@",
        LSGCVersionString,NativeClassesLoaded?@"是":@"否",Hooked?@"是":@"否",HookReport?:@"无",(unsigned long)Labels.allObjects.count,(unsigned long)clocks,(unsigned long)scoped,(unsigned long)active,[Config[@"enabled"] boolValue]?@"开":@"关",
        ([Config[@"enabled"] boolValue] && Hooked && active)?@"当前满足抑制门禁（需主时间draw计数与截图佐证）":@"未生效（保留系统时间）",StartupComplete?@"完成":@"未完成",[details componentsJoinedByString:@"\n\n"]];
    NSMutableArray *tree=[NSMutableArray array];
    for (UIView *root in DateViews.allObjects) {
        NSMutableArray<UIView *> *queue=[NSMutableArray arrayWithObject:root];
        for (NSUInteger i=0;i<queue.count && tree.count<60;i++) {
            UIView *view=queue[i];
            NSMutableArray *layers=[NSMutableArray array];
            for (CALayer *layer in view.layer.sublayers) {
                if (layers.count>=8) break;
                [layers addObject:NSStringFromClass(layer.class)];
            }
            [tree addObject:[NSString stringWithFormat:@"%@ -> %@ bounds=%@ 可见=%d layers=%@",
                NSStringFromClass(view.superview.class),NSStringFromClass(view.class),NSStringFromCGRect(view.bounds),Visible(view),[layers componentsJoinedByString:@","]]];
            if (queue.count<100) [queue addObjectsFromArray:view.subviews];
        }
        if (tree.count>=60) break;
    }
    report=[report stringByAppendingFormat:@"\n\n日期开关：%@\nUILabel Hook：%@\n日期标签：%lu\n日期渐变已附加：%lu\n%@\n日期控件树（仅类名与几何）：\n%@",
        [Config[@"dateGradient"] boolValue]?@"开":@"关",LabelHooked?@"是":@"否",(unsigned long)dates,(unsigned long)dateActive,
        [dateDetails componentsJoinedByString:@"\n"],[tree componentsJoinedByString:@"\n"]];
    report=[report stringByAppendingFormat:@"\n时间字体：%@",FontStatus?:@"未加载"];
    report=[report stringByAppendingString:DiagReport()];
    CFPreferencesSetAppValue(CFSTR("diagnosticReport"),(__bridge CFStringRef)report,(__bridge CFStringRef)Domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)Domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),Replied,NULL,NULL,true);
}
static BOOL ColorRGB(UIColor *color,double *r,double *g,double *b) {
    CGFloat rr=0,gg=0,bb=0,aa=1;
    if ([color getRed:&rr green:&gg blue:&bb alpha:&aa]) { *r=rr; *g=gg; *b=bb; return YES; }
    CGFloat w=0;
    if ([color getWhite:&w alpha:&aa]) { *r=*g=*b=w; return YES; }
    return NO;
}
static UIColor *ControllerWallpaperColor(void) {
    Class cls=NSClassFromString(@"SBWallpaperController");
    SEL shared=sel_registerName("sharedInstance");
    if (!cls || ![cls respondsToSelector:shared]) return nil;
    id ctrl=((id(*)(id,SEL))objc_msgSend)(cls,shared);
    SEL sel=sel_registerName("averageColorForVariant:");
    if (![ctrl respondsToSelector:sel]) return nil;
    for (long long variant=1; variant>=0; variant--) {
        id color=((id(*)(id,SEL,long long))objc_msgSend)(ctrl,sel,variant);
        if ([color isKindOfClass:UIColor.class]) return color;
    }
    return nil;
}
static BOOL BandsOfView(UIView *view,double bands[3][3]) {
    CGSize size=view.bounds.size;
    if (!view || size.width<2 || size.height<2) return NO;
    const int w=18,h=36,rows=h/3;
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];
    format.opaque=YES; format.scale=1;
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(w,h) format:format];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextScaleCTM(context.CGContext,w/size.width,h/size.height);
        [view.layer renderInContext:context.CGContext];
    }];
    CGImageRef cg=image.CGImage;
    if (!cg) return NO;
    unsigned char rgba[18*36*4];
    for (NSUInteger i=0;i<sizeof(rgba);i++) rgba[i]=0;
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(rgba,w,h,8,w*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) return NO;
    CGContextDrawImage(ctx,CGRectMake(0,0,w,h),cg);
    CGContextRelease(ctx);
    double energy=0;
    for (int band=0; band<3; band++) {
        double r=0,g=0,b=0; int n=0;
        for (int y=band*rows; y<(band+1)*rows; y++) for (int x=0; x<w; x++) {
            int i=y*w+x;
            if (rgba[i*4+3]<16) continue;
            r+=rgba[i*4]; g+=rgba[i*4+1]; b+=rgba[i*4+2]; n++;
        }
        if (!n) return NO;
        bands[band][0]=r/n/255.0; bands[band][1]=g/n/255.0; bands[band][2]=b/n/255.0;
        energy+=bands[band][0]+bands[band][1]+bands[band][2];
    }
    return energy>=0.08;
}
static NSString *HexRGB(double r,double g,double b) {
    return [NSString stringWithFormat:@"#%02X%02X%02X",(int)lround(Clamp(r,0,1)*255),(int)lround(Clamp(g,0,1)*255),(int)lround(Clamp(b,0,1)*255)];
}
static void WriteSampleMessage(NSString *message,BOOL changed) {
    CFPreferencesSetAppValue(CFSTR("wallpaperSampleMessage"),(__bridge CFStringRef)message,(__bridge CFStringRef)Domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)Domain);
    if (changed) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),Changed,NULL,NULL,true);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),Sampled,NULL,NULL,true);
}
static void SampleWallpaper(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)Domain);
    id modeValue=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("wallpaperSampleMode"),(__bridge CFStringRef)Domain));
    int brighter=[modeValue isKindOfClass:NSNumber.class] && [modeValue integerValue]==1;
    double colors[5][3],edges[3][3],bands[3][3];
    NSString *message=nil;
    if (BandsOfView(WallpaperView(),bands)) {
        LSGCBandPalette(bands,brighter,colors,edges);
        message=brighter?@"已按壁纸上中下更亮一档写入。":@"已按壁纸上中下三段写入。";
    } else {
        UIColor *color=ControllerWallpaperColor();
        double r=0,g=0,b=0;
        if (!color || !ColorRGB(color,&r,&g,&b)) {
            WriteSampleMessage(@"没有读到壁纸颜色，当前配色未改变。",NO);
            return;
        }
        LSGCWallpaperPalette(r,g,b,brighter,colors,edges);
        message=brighter?@"未能分段，已按平均色的更亮一档写入。":@"未能分段，已按壁纸平均色写入。";
    }
    NSString *keys[5]={@"color1",@"color2",@"color3",@"color4",@"color5"};
    for (int i=0;i<5;i++) CFPreferencesSetAppValue((__bridge CFStringRef)keys[i],(__bridge CFStringRef)HexRGB(colors[i][0],colors[i][1],colors[i][2]),(__bridge CFStringRef)Domain);
    NSString *edgeKeys[3]={@"edgeColor1",@"edgeColor2",@"edgeColor3"};
    for (int i=0;i<3;i++) CFPreferencesSetAppValue((__bridge CFStringRef)edgeKeys[i],(__bridge CFStringRef)HexRGB(edges[i][0],edges[i][1],edges[i][2]),(__bridge CFStringRef)Domain);
    CFPreferencesSetAppValue(CFSTR("independentEdges"),(__bridge CFNumberRef)@YES,(__bridge CFStringRef)Domain);
    WriteSampleMessage(message,YES);
}
static CFStringRef const VisualsChanged=CFSTR("com.minis.lockscreengradientclock/visualsChanged");
static CFTimeInterval ScheduleStamp;
static int CurrentSlot(void) {
    NSDateComponents *parts=[[NSCalendar currentCalendar] components:NSCalendarUnitHour fromDate:[NSDate date]];
    return (parts.hour>=7 && parts.hour<19) ? 0 : 1;
}
static NSDictionary *PaletteValuesNamed(NSString *name) {
    if (![name isKindOfClass:NSString.class] || !name.length) return nil;
    id stored=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("savedPalettes"),(__bridge CFStringRef)Domain));
    if (![stored isKindOfClass:NSArray.class]) return nil;
    for (id item in stored) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        if ([item[@"name"] isEqual:name] && [item[@"values"] isKindOfClass:NSDictionary.class]) return item[@"values"];
    }
    return nil;
}
static void RegisterUserFont(void) {
    NSString *path=[Config[@"fontPath"] isKindOfClass:NSString.class] ? Config[@"fontPath"] : nil;
    NSString *name=[Config[@"fontName"] isKindOfClass:NSString.class] ? Config[@"fontName"] : nil;
    if (!path.length && name.length) {
        // Migrate legacy imports by matching the selected face, not extension order.
        for (NSString *ext in @[@"ttf",@"otf",@"ttc"]) {
            NSString *candidate=[@"/var/mobile/Library/Application Support/LockScreenGradientClock/clock." stringByAppendingString:ext];
            if (LSGCFontAtURL([NSURL fileURLWithPath:candidate],name,12,NULL,NULL)) { path=candidate; break; }
        }
    }
    NSString *identity=[NSString stringWithFormat:@"%@|%@",path?:@"",name?:@""];
    static NSString *loaded;
    if ([loaded isEqualToString:identity] && (ImportedFont || !name.length)) return;
    if (ImportedPath) CTFontManagerUnregisterFontsForURL((__bridge CFURLRef)[NSURL fileURLWithPath:ImportedPath],kCTFontManagerScopeProcess,NULL);
    ImportedFont=nil; ImportedPath=nil; loaded=identity;
    if (path.length && name.length) {
        ImportedFont=LSGCFontAtURL([NSURL fileURLWithPath:path],name,12,NULL,NULL);
        if (ImportedFont) ImportedPath=path;
    }
    FontStatus=ImportedFont ? [@"生效：" stringByAppendingString:ImportedFont.fontName] : (name.length ? @"导入字体不可用，使用系统字体" : @"系统字体");
}
static void MaybeApplySchedule(BOOL force) {
    CFTimeInterval now=CACurrentMediaTime();
    if (!force && ScheduleStamp>0 && now-ScheduleStamp<20) return;
    ScheduleStamp=now;
    int slot=CurrentSlot();
    id applied=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("scheduleAppliedSlot"),(__bridge CFStringRef)Domain));
    if ([applied isKindOfClass:NSNumber.class] && [applied intValue]==slot) return;
    NSString *nameKey=slot==0?@"dayPaletteName":@"nightPaletteName";
    NSString *name=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)nameKey,(__bridge CFStringRef)Domain));
    NSDictionary *values=PaletteValuesNamed(name);
    if (!values) return;
    NSArray *keys=@[@"color1",@"color2",@"color3",@"color4",@"color5",@"edgeColor1",@"edgeColor2",@"edgeColor3",@"direction",@"opacity",@"animate",@"glassBlend",@"glassTint",@"edgeEnabled",@"edgePalette",@"edgeCore",@"edgeStrength",@"edgeWidth",@"edgeHighlight",@"edgeReveal",@"customAngleEnabled",@"gradientAngle",@"customStopsEnabled",@"stop1",@"stop2",@"stop3",@"stop4",@"stop5",@"reverseColors",@"independentEdges",@"timeShift",@"parallaxAngle"];
    for (NSString *key in keys) {
        id value=values[key];
        if (value) CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFPropertyListRef)value,(__bridge CFStringRef)Domain);
    }
    CFPreferencesSetAppValue(CFSTR("scheduleAppliedSlot"),(__bridge CFNumberRef)@(slot),(__bridge CFStringRef)Domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)Domain);
    LoadConfig();
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),Changed,NULL,NULL,true);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),VisualsChanged,NULL,NULL,true);
}
static void Notification(CFNotificationCenterRef center,void *observer,CFStringRef name,const void *object,CFDictionaryRef info) {
    (void)center; (void)observer; (void)object; (void)info;
    BOOL diagnostic=name && CFEqual(name,Diagnose);
    BOOL sample=name && CFEqual(name,Sample);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (diagnostic) { WriteDiagnostics(); return; }
        if (sample) { SampleWallpaper(); return; }
        LoadConfig(); RefreshNativeClockSuppression(); MaybeApplySchedule(YES); DiscoverAndApply();
    });
}
static void AddedImage(const struct mach_header *header,intptr_t slide) {
    (void)header; (void)slide;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!StartupComplete || ImageRefreshPending) return;
        ImageRefreshPending=YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            ImageRefreshPending=NO; DiscoverAndApply();
        });
    });
}
__attribute__((constructor)) static void Start(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            Labels=[NSHashTable weakObjectsHashTable]; DateViews=[NSHashTable weakObjectsHashTable]; LoadConfig(); NativeClockSuppressionState=NativeClockSuppressionEnabled();
            StartupComplete=YES;
            InstallHooks();
            NSLog(@"[LSGC] constructor initialized in SpringBoard; %@",HookReport);
            CFNotificationCenterRef center=CFNotificationCenterGetDarwinNotifyCenter();
            CFNotificationCenterAddObserver(center,NULL,Notification,Changed,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
            CFNotificationCenterAddObserver(center,NULL,Notification,Diagnose,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
            CFNotificationCenterAddObserver(center,NULL,Notification,Sample,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
            MaybeApplySchedule(YES);
            _dyld_register_func_for_add_image(AddedImage);
            DiscoverAndApply();
            NSNotificationCenter *notes=NSNotificationCenter.defaultCenter;
            NSOperationQueue *queue=NSOperationQueue.mainQueue;
            void (^refresh)(NSNotification *)=^(NSNotification *note) { (void)note; MaybeApplySchedule(YES); DiscoverAndApply(); };
            [notes addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:queue usingBlock:refresh];
            [notes addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:queue usingBlock:refresh];
            [notes addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:queue usingBlock:refresh];
            [notes addObserverForName:UIScreenDidConnectNotification object:nil queue:queue usingBlock:refresh];
            for (NSNumber *delay in @[@0.4,@1.2,@3.0,@8.0]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{ RetryDateDiscover(); });
            }
            // Event-driven only: system clock/layout hooks trigger updates.
            // No polling timer or display link is installed in SpringBoard.
        });
    }
}
