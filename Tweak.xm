#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <math.h>
#import "LSGCEdgeMath.h"
#import "LSGCGradientMath.h"
#import "LSGCPalette.h"
#import "LSGCVersion.h"

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
static Class GlassClass;
static BOOL Hooked;
static NSString *HookReport;
static char StateKey, PendingKey;
static BOOL Rendering;
static NSUInteger Revision;
static void Apply(UILabel *label);
static void InstallHooks(void);
static void Discover(void);

@interface LSGCState : NSObject
@property(nonatomic,strong) CAGradientLayer *gradient;
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
    NSMutableDictionary *values=[@{@"enabled":@YES,@"color1":@"#39D6ED",@"color2":@"#4D7CFF",@"color3":@"#AD4DF5",@"color4":@"#F950B0",@"color5":@"#FFBD61",@"direction":@0,@"opacity":@0.65,@"animate":@NO,@"strictScope":@YES,@"maskMode":@0,@"glassBlend":@YES,@"glassTint":@0.32,@"edgeEnabled":@NO,@"edgePalette":@0,@"edgeCore":@0.22,@"edgeStrength":@0.65,@"edgeWidth":@1.5,@"edgeHighlight":@0.35,@"edgeReveal":@NO,@"customAngleEnabled":@NO,@"gradientAngle":@0,@"customStopsEnabled":@NO,@"stop1":@0,@"stop2":@0.25,@"stop3":@0.5,@"stop4":@0.75,@"stop5":@1,@"reverseColors":@NO,@"independentEdges":@NO,@"edgeColor1":@"#D0FAFF",@"edgeColor2":@"#B39CFF",@"edgeColor3":@"#F7A9DD",@"timeShift":@NO,@"parallaxAngle":@NO} mutableCopy];
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
static UIImage *SnapshotText(UILabel *label,CGFloat scale) {
    UILabel *mirror=[[UILabel alloc] initWithFrame:(CGRect){CGPointZero,label.bounds.size}];
    mirror.font=label.font; mirror.textColor=UIColor.whiteColor;
    mirror.textAlignment=label.textAlignment; mirror.numberOfLines=label.numberOfLines;
    mirror.lineBreakMode=label.lineBreakMode; mirror.adjustsFontSizeToFitWidth=label.adjustsFontSizeToFitWidth;
    mirror.minimumScaleFactor=label.minimumScaleFactor; mirror.baselineAdjustment=label.baselineAdjustment;
    // Use the displayed label's attributes, not Liquidify's private mask-canvas offsets.
    NSAttributedString *source=label.attributedText;
    if (![source isKindOfClass:NSAttributedString.class]) source=nil;
    if (source.length) {
        NSMutableAttributedString *text=[source mutableCopy]; NSRange all=NSMakeRange(0,text.length);
        [text addAttribute:NSForegroundColorAttributeName value:UIColor.whiteColor range:all];
        [text removeAttribute:NSBackgroundColorAttributeName range:all];
        [text removeAttribute:NSShadowAttributeName range:all];
        mirror.attributedText=text;
    } else mirror.text=label.text;
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
static BOOL BuildEdgeImages(UIImage *image,CGFloat edgeWidth,CGImageRef *ringOut,CGImageRef *bevelOut) {
    if (ringOut) *ringOut=NULL;
    if (bevelOut) *bevelOut=NULL;
    CGImageRef input=image.CGImage;
    size_t w=input ? CGImageGetWidth(input) : 0,h=input ? CGImageGetHeight(input) : 0;
    if (!w || !h || w>4096 || h>4096 || w*h>4194304) return NO;
    size_t count=w*h*4;
    unsigned char *rgba=(unsigned char *)calloc(count,1);
    unsigned char *ring=(unsigned char *)calloc(count,1);
    unsigned char *bevel=(unsigned char *)calloc(count,1);
    if (!rgba || !ring || !bevel) { free(rgba); free(ring); free(bevel); return NO; }
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo flags=kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big;
    CGContextRef source=CGBitmapContextCreate(rgba,w,h,8,w*4,space,flags);
    CGContextRef ringContext=CGBitmapContextCreate(ring,w,h,8,w*4,space,flags);
    CGContextRef bevelContext=CGBitmapContextCreate(bevel,w,h,8,w*4,space,flags);
    CGColorSpaceRelease(space);
    BOOL valid=source && ringContext && bevelContext;
    CGImageRef ringImage=NULL,bevelImage=NULL;
    if (valid) {
        CGContextDrawImage(source,CGRectMake(0,0,w,h),input);
        float radius=(float)(Clamp(edgeWidth,0.5,4)*image.scale);
        valid=LSGCMakeEdges(rgba,w,h,radius,ring,bevel);
        if (valid) {
            ringImage=CGBitmapContextCreateImage(ringContext);
            bevelImage=CGBitmapContextCreateImage(bevelContext);
            valid=ringImage && bevelImage;
        }
    }
    if (source) CGContextRelease(source);
    if (ringContext) CGContextRelease(ringContext);
    if (bevelContext) CGContextRelease(bevelContext);
    free(rgba); free(ring); free(bevel);
    if (!valid) {
        if (ringImage) CGImageRelease(ringImage);
        if (bevelImage) CGImageRelease(bevelImage);
        return NO;
    }
    *ringOut=ringImage; *bevelOut=bevelImage;
    return YES;
}
static void InstallEdgeContents(LSGCState *s,CGImageRef ringImage,CGImageRef bevelImage,CGFloat scale) {
    if (!ringImage || !bevelImage) { ClearEdges(s); return; }
    if (!s.edgeHost) {
        s.edgeHost=[CALayer layer]; s.edgeHost.name=@"LSGC.OptionalColorEdges";
        s.edgeTint=[CAGradientLayer layer]; s.edgeMask=[CALayer layer]; s.edgeBevel=[CALayer layer];
        s.edgeTint.mask=s.edgeMask;
        [s.edgeHost addSublayer:s.edgeTint]; [s.edgeHost addSublayer:s.edgeBevel];
    }
    s.edgeMask.contents=(__bridge id)ringImage;
    s.edgeMask.contentsScale=scale; s.edgeMask.contentsGravity=kCAGravityResize;
    s.edgeBevel.contents=(__bridge id)bevelImage;
    s.edgeBevel.contentsScale=scale; s.edgeBevel.contentsGravity=kCAGravityResize;
}
static void MatchGeometry(CALayer *layer,CALayer *reference) {
    layer.transform=CATransform3DIdentity;
    layer.bounds=reference.bounds; layer.anchorPoint=reference.anchorPoint;
    layer.position=reference.position; layer.transform=reference.transform;
}
static void ApplyEdges(LSGCState *s,CALayer *host) {
    if (![Config[@"edgeEnabled"] boolValue]) { ClearEdges(s); return; }
    if (!s.edgeHost) return;
    BOOL appearing=s.edgeHost.superlayer==nil;
    s.edgeHost.bounds=(CGRect){CGPointZero,host.bounds.size};
    s.edgeHost.position=CGPointMake(CGRectGetMidX(host.bounds),CGRectGetMidY(host.bounds));
    s.edgeHost.zPosition=s.gradient.zPosition+0.01;
    s.edgeTint.bounds=(CGRect){CGPointZero,host.bounds.size};
    s.edgeTint.position=CGPointMake(host.bounds.size.width*.5,host.bounds.size.height*.5);
    MatchGeometry(s.edgeMask,s.mask); MatchGeometry(s.edgeBevel,s.mask);
    NSInteger preset=[Config[@"edgePalette"] integerValue];
    NSArray *colors;
    if ([Config[@"independentEdges"] boolValue]) {
        NSMutableArray *custom=[NSMutableArray array];
        NSArray *fallback=@[@"#D0FAFF",@"#B39CFF",@"#F7A9DD"];
        for (NSUInteger i=0;i<3;i++) {
            NSString *key=[NSString stringWithFormat:@"edgeColor%lu",(unsigned long)i+1];
            UIColor *c=Color(Config[key],Color(fallback[i],UIColor.whiteColor));
            [custom addObject:(__bridge id)c.CGColor];
        }
        colors=custom;
    } else if (preset==2) colors=s.gradient.colors;
    else {
        NSArray *hex=preset==1 ? @[@"#FFF1DB",@"#F7B2CB",@"#E1B7FF",@"#FFD296"] :
                                @[@"#D0FAFF",@"#72CFFB",@"#B39CFF",@"#F7A9DD"];
        NSMutableArray *built=[NSMutableArray array];
        for (NSString *h in hex) [built addObject:(__bridge id)Color(h,UIColor.whiteColor).CGColor];
        colors=built;
    }
    s.edgeTint.colors=colors;
    s.edgeTint.startPoint=CGPointMake(0,0); s.edgeTint.endPoint=CGPointMake(1,1);
    s.edgeTint.opacity=Clamp([Config[@"edgeStrength"] doubleValue],0,1);
    float intensity=(float)Clamp([Config[@"edgeHighlight"] doubleValue],0,1);
    s.edgeBevel.opacity=intensity;
    if (![Config[@"edgeReveal"] boolValue]) [s.edgeBevel removeAllAnimations];
    if (s.edgeHost.superlayer!=host) {
        [s.edgeHost removeFromSuperlayer]; [host addSublayer:s.edgeHost];
    }
    if (appearing && [Config[@"edgeReveal"] boolValue] && (s.motionBits&7)==0 && intensity>0) {
        CAKeyframeAnimation *flash=[CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        flash.values=@[@0,@(MIN(1,intensity*1.5)),@(intensity)];
        flash.keyTimes=@[@0,@0.25,@1]; flash.duration=0.9;
        [s.edgeBevel addAnimation:flash forKey:@"LSGC.EdgeReveal"];
    }
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
    BOOL edges=[Config[@"edgeEnabled"] boolValue];
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
        ReadFlag(label,@"cachedBuildFinished"),native,scale,Clamp([Config[@"edgeWidth"] doubleValue],0.5,4),glass,edges];
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
    BOOL styleDirty=s.styleToken!=token || s.motionBits!=motionBits;
    BOOL glass=[Config[@"glassBlend"] boolValue] && (motionBits&8)==0;
    BOOL quiet=(motionBits&7)!=0;
    s.motionBits=motionBits; s.styleToken=token;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    s.gradient.bounds=(CGRect){CGPointZero,host.bounds.size};
    s.gradient.position=CGPointMake(CGRectGetMidX(host.bounds),CGRectGetMidY(host.bounds));
    s.gradient.opacity=glass ? Clamp([Config[@"glassTint"] doubleValue],0,0.65) : Clamp([Config[@"opacity"] doubleValue],0,1);
    if ([Config[@"edgeEnabled"] boolValue] && s.edgeHost)
        s.gradient.opacity *= Clamp([Config[@"edgeCore"] doubleValue],0,1);
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
    ApplyEdges(s,host);
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
        s.mask.bounds=(CGRect){CGPointZero,label.bounds.size};
        s.mask.position=CGPointMake(label.bounds.size.width*.5,label.bounds.size.height*.5);
    }
    s.maskMode=native ? @"原插件文字遮罩" : @"同字体文字重绘";
    [CATransaction commit];
}
static void RemoveOverlay(UILabel *label) {
    LSGCState *s=objc_getAssociatedObject(label,&StateKey);
    if (!s) return;
    s.ticket++; s.busy=NO; s.dirty=NO;
    [s.gradient removeFromSuperlayer]; [s.gradient removeAllAnimations];
    ClearEdges(s);
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
    CGFloat edgeWidth=Clamp([Config[@"edgeWidth"] doubleValue],0.5,4);
    BOOL wantEdges=edges,wantGlass=glass;
    __weak UILabel *weak=label; LSGCState *state=s;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        CGImageRef ring=NULL,bevel=NULL;
        BOOL edgeOK=wantEdges && BuildEdgeImages(image,edgeWidth,&ring,&bevel);
        UIImage *tinted=wantGlass ? GlassTintMask(image) : image;
        dispatch_async(dispatch_get_main_queue(), ^{
            UILabel *strong=weak;
            if (!strong || state.ticket!=ticket) {
                if (ring) CGImageRelease(ring);
                if (bevel) CGImageRelease(bevel);
                return;
            }
            @try {
                CALayer *nowSource=nil,*nowOwner=nil; NSUInteger nowMotion=0;
                NSString *now=DescribeMask(strong,&nowSource,&nowOwner,NULL,NULL,&nowMotion,NULL,NULL,NULL);
                if (![now isEqualToString:signature] || ![Config[@"enabled"] boolValue] || !Visible(strong) || !TimeText(strong.text ?: strong.attributedText.string)) {
                    if ([Config[@"enabled"] boolValue] && Visible(strong) && TimeText(strong.text ?: strong.attributedText.string)) Schedule(strong);
                    else RemoveOverlay(strong);
                } else {
                    CALayer *installHost=(usedNative && nowOwner) ? nowOwner : strong.layer;
                    if (edgeOK) InstallEdgeContents(state,ring,bevel,tinted.scale);
                    else ClearEdges(state);
                    InstallMask(state,tinted,usedNative && nowOwner!=nil,nowSource,installHost,strong);
                    state.signature=signature;
                    ApplyStyle(strong,state,installHost,nowMotion);
                }
            } @catch (NSException *exception) {
                RemoveOverlay(strong);
                state.maskMode=[@"兼容异常：" stringByAppendingString:exception.name];
            } @finally {
                if (ring) CGImageRelease(ring);
                if (bevel) CGImageRelease(bevel);
                if (state.ticket==ticket) state.busy=NO;
            }
            if (strong && state.dirty && state.ticket==ticket) { state.dirty=NO; Schedule(strong); }
        });
    });
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
static void NoteHook(const char *name,BOOL ok) {
    NSString *line=[NSString stringWithFormat:@"%s=%@",name,ok?@"是":@"否"];
    HookReport=HookReport.length ? [HookReport stringByAppendingFormat:@" %@",line] : line;
}
static void Hook(const char *name,IMP replacement,IMP *original,NSUInteger arguments) {
    SEL sel=sel_registerName(name); Method method=class_getInstanceMethod(GlassClass,sel);
    if (!method || method_getNumberOfArguments(method)!=arguments) { NoteHook(name,NO); return; }
    char ret[16]={0}; method_getReturnType(method,ret,sizeof(ret));
    if (ret[0]!='v') { NoteHook(name,NO); return; }
    MSHookMessageEx(GlassClass,sel,replacement,original);
    NoteHook(name,original && *original);
}
static void InstallHooks(void) {
    if (Hooked) return;
    Class cls=NSClassFromString(@"CCLiquidGlassLabel");
    if (!cls || ![cls isSubclassOfClass:UILabel.class]) return;
    GlassClass=cls; HookReport=nil;
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
            [details addObject:[NSString stringWithFormat:@"时间形态=%@ 锁屏范围=%@ 可见=%@ 分隔符=%@\n模式=%@\n%@",time?@"是":@"否",lock?@"是":@"否",Visible(label)?@"是":@"否",SeparatorCodes(label.text ?: label.attributedText.string),s.maskMode?:@"尚未渲染",[chain componentsJoinedByString:@" > "]]];
        }
    }
    NSString *report=[NSString stringWithFormat:@"兼容层 %@\n类已加载：%@\nHook 已安装：%@\nHook 明细：%@\n玻璃标签：%lu\n时间标签：%lu\n锁屏范围命中：%lu\n已附加渐变：%lu\n开关：%@\n\n%@",
        LSGCVersionString,GlassClass?@"是":@"否",Hooked?@"是":@"否",HookReport?:@"无",(unsigned long)Labels.allObjects.count,(unsigned long)clocks,(unsigned long)scoped,(unsigned long)active,[Config[@"enabled"] boolValue]?@"开":@"关",[details componentsJoinedByString:@"\n\n"]];
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
static UIColor *AverageOfView(UIView *view) {
    CGSize size=view.bounds.size;
    if (!view || size.width<2 || size.height<2) return nil;
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];
    format.opaque=YES; format.scale=1;
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(24,24) format:format];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextScaleCTM(context.CGContext,24.0/size.width,24.0/size.height);
        [view.layer renderInContext:context.CGContext];
    }];
    CGImageRef cg=image.CGImage;
    if (!cg) return nil;
    unsigned char rgba[24*24*4];
    for (NSUInteger i=0;i<sizeof(rgba);i++) rgba[i]=0;
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(rgba,24,24,8,24*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) return nil;
    CGContextDrawImage(ctx,CGRectMake(0,0,24,24),cg);
    CGContextRelease(ctx);
    double r=0,g=0,b=0; NSUInteger n=0;
    for (NSUInteger i=0;i<24*24;i++) {
        if (rgba[i*4+3]<16) continue;
        r+=rgba[i*4]; g+=rgba[i*4+1]; b+=rgba[i*4+2]; n++;
    }
    if (!n) return nil;
    return [UIColor colorWithRed:r/n/255.0 green:g/n/255.0 blue:b/n/255.0 alpha:1];
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
    UIColor *color=ControllerWallpaperColor();
    BOOL fromSnapshot=NO;
    if (!color) { color=AverageOfView(WallpaperView()); fromSnapshot=YES; }
    double r=0,g=0,b=0;
    if (!color || !ColorRGB(color,&r,&g,&b) || (fromSnapshot && r+g+b<0.02)) {
        WriteSampleMessage(@"没有读到壁纸颜色，当前配色未改变。",NO);
        return;
    }
    double colors[5][3],edges[3][3];
    LSGCWallpaperPalette(r,g,b,brighter,colors,edges);
    NSString *keys[5]={@"color1",@"color2",@"color3",@"color4",@"color5"};
    for (int i=0;i<5;i++) CFPreferencesSetAppValue((__bridge CFStringRef)keys[i],(__bridge CFStringRef)HexRGB(colors[i][0],colors[i][1],colors[i][2]),(__bridge CFStringRef)Domain);
    NSString *edgeKeys[3]={@"edgeColor1",@"edgeColor2",@"edgeColor3"};
    for (int i=0;i<3;i++) CFPreferencesSetAppValue((__bridge CFStringRef)edgeKeys[i],(__bridge CFStringRef)HexRGB(edges[i][0],edges[i][1],edges[i][2]),(__bridge CFStringRef)Domain);
    CFPreferencesSetAppValue(CFSTR("independentEdges"),(__bridge CFNumberRef)@YES,(__bridge CFStringRef)Domain);
    WriteSampleMessage(brighter?@"已按更亮一档写入壁纸配色。":@"已按贴近壁纸写入配色。",YES);
}
static void Notification(CFNotificationCenterRef center,void *observer,CFStringRef name,const void *object,CFDictionaryRef info) {
    (void)center; (void)observer; (void)object; (void)info;
    BOOL diagnostic=name && CFEqual(name,Diagnose);
    BOOL sample=name && CFEqual(name,Sample);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (diagnostic) { WriteDiagnostics(); return; }
        if (sample) { SampleWallpaper(); return; }
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
            CFNotificationCenterAddObserver(center,NULL,Notification,Sample,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
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
