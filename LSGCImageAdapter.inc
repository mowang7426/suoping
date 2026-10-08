#include "LSGCImagePolicy.h"
// Traditional image-backed adapter. Native image contents/visibility are never mutated.
// Empty masks are leases: preserve the latest system mask, not a startup snapshot.
static char ImageLeaseKey;
@interface LSGCImageLease : NSObject
@property(nonatomic,weak) UILabel *source;
@property(nonatomic,strong) CALayer *nativeMask;
@property(nonatomic,strong) CALayer *blank;
@end
@implementation LSGCImageLease
@end
static void (*ImageOrigMask)(id,SEL,CALayer *);
static void (*ImageOrigContents)(id,SEL,id);
static void (*ImageOrigSetImage)(id,SEL,UIImage *);
static void (*ImageOrigHidden)(id,SEL,BOOL);
static void (*ImageOrigAlpha)(id,SEL,CGFloat);
static BOOL ImageMutation;
static unsigned long long ImageCommits, ImageRollbacks, ImageUpdates, ImageCacheHits;
static NSString *ImageLastReason;
static int ImageRole(UILabel *label) {
    const char *names[8]; unsigned count=0;
    for (UIView *view=label; view && count<8; view=view.superview) names[count++]=class_getName(view.class);
    return LSGCImageRole(names,count);
}
static NSArray<UIView *> *ImageNodes(UILabel *label) {
    if (!ImageRole(label)) return @[];
    NSMutableArray *nodes=[NSMutableArray array];
    for (UIView *branch in label.superview.subviews) {
        if (![NSStringFromClass(branch.class) isEqualToString:@"_UILegibilityView"]) continue;
        for (UIView *image in branch.subviews) {
            if (![NSStringFromClass(image.class) isEqualToString:@"_UILegibilityImageView"]) return @[];
            [nodes addObject:image];
        }
    }
    return nodes;
}
static UIView *ImageParent(UILabel *label) {
    if (!ImageRole(label) || !ImageNodes(label).count) return nil;
    UIView *wrapper=label.superview;
    NSUInteger sources=0, branches=0; UIView *host=nil;
    for (UIView *child in wrapper.subviews) {
        if ([child isKindOfClass:UILabel.class]) sources++;
        else if ([NSStringFromClass(child.class) isEqualToString:@"_UILegibilityView"]) { branches++; host=child; }
        else return nil;
    }
    if (sources!=1 || branches!=1) return nil;
    if (ImageRole(label)==1) {
        NSUInteger clocks=0;
        for (UIView *child in wrapper.superview.subviews)
            if ([NSStringFromClass(child.class) isEqualToString:@"SBUILegibilityLabel"]) clocks++;
        if (clocks!=1) return nil;
    }
    // Host within the native animated legibility branch, not a detached sibling
    // of SBFLockScreenDateView: inherit branch alpha/transform exactly once.
    return host;
}
static void ImageReleaseLayers(NSArray<CALayer *> *layers) {
    if (!layers.count || !ImageOrigMask) return;
    BOOL previous=ImageMutation; ImageMutation=YES;
    @try {
        for (CALayer *layer in layers) {
            LSGCImageLease *lease=objc_getAssociatedObject(layer,&ImageLeaseKey);
            if (!lease) continue;
            if (LSGCImageRestoreOwnedMask((__bridge const void *)layer.mask,(__bridge const void *)lease.blank)) ImageOrigMask(layer,@selector(setMask:),lease.nativeMask);
            objc_setAssociatedObject(layer,&ImageLeaseKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } @finally { ImageMutation=previous; }
}
static void ImageRestore(UILabel *label) {
    LSGCState *s=objc_getAssociatedObject(label,&StateKey);
    if (!s.imageLeased.count) return;
    ImageReleaseLayers(s.imageLeased);
    s.imageLeased=nil; DiagInc(&ImageRollbacks);
}
static BOOL ImageVisible(UIView *view) {
    if (!view.window) return NO;
    CGRect rect=[view convertRect:view.bounds toView:view.window];
    if (CGRectIsEmpty(rect) || CGRectIsInfinite(rect) || CGRectIsNull(rect)) return NO;
    rect=CGRectIntersection(rect,view.window.bounds);
    for (UIView *v=view; v; v=v.superview) {
        CALayer *p=(CALayer *)v.layer.presentationLayer ?: v.layer;
        if (v.hidden || !isfinite(v.alpha) || v.alpha<.01 || v.layer.hidden || p.hidden ||
            !isfinite(v.layer.opacity) || !isfinite(p.opacity) || v.layer.opacity<.01 || p.opacity<.01 ||
            !CATransform3DIsAffine(v.layer.transform) || !CATransform3DIsAffine(p.transform)) return NO;
        if (v.clipsToBounds || v.layer.masksToBounds)
            rect=CGRectIntersection(rect,[v convertRect:v.bounds toView:view.window]);
    }
    return !CGRectIsEmpty(rect) && !CGRectIsNull(rect);
}
static UIView *ImageGlyph(UILabel *label) {
    // UIKit's first oversized image is a blurred shadow; only the native-sized
    // image is a valid glyph mask. Never treat the shadow as a second source.
    UIView *glyph=nil;
    for (UIView *image in ImageNodes(label)) {
        if (!LSGCImageGlyphSize(image.bounds.size.width,image.bounds.size.height,
            label.bounds.size.width,label.bounds.size.height)) continue;
        id pixels=image.layer.contents;
        UIImage *ui=[image isKindOfClass:UIImageView.class] ? ((UIImageView *)image).image : nil;
        if ((!pixels && !ui.CGImage) || !ImageVisible(image)) continue;
        if (glyph) return nil;
        glyph=image;
    }
    return glyph;
}
static UIImage *ImageDateMask(UILabel *label) {
    UIView *glyph=ImageGlyph(label);
    if (!glyph) return nil;
    LSGCImageLease *lease=objc_getAssociatedObject(glyph.layer,&ImageLeaseKey);
    // Raw alpha preserves exact native glyphs. Unknown native masking requires
    // fail-open rather than replacing a clipped native date with full glyphs.
    if ((lease ? lease.nativeMask : glyph.layer.mask)!=nil ||
        !CGRectEqualToRect(glyph.layer.contentsRect,CGRectMake(0,0,1,1))) return nil;
    UIImage *image=[glyph isKindOfClass:UIImageView.class] ? ((UIImageView *)glyph).image : nil;
    if (image.CGImage && image.imageOrientation==UIImageOrientationUp && HasAlpha(image)) return image;
    id contents=glyph.layer.contents;
    if (contents && CFGetTypeID((__bridge CFTypeRef)contents)==CGImageGetTypeID()) {
        UIImage *copy=[UIImage imageWithCGImage:(__bridge CGImageRef)contents scale:MAX(1,glyph.layer.contentsScale) orientation:UIImageOrientationUp];
        if (HasAlpha(copy)) return copy;
    }
    return nil;
}
static BOOL ImageReady(UILabel *label, LSGCState *s) {
    UIView *host=ImageParent(label);
    int role=ImageRole(label);
    if (!ImageOrigMask || !ImageOrigContents || !ImageOrigSetImage || !host || !ImageGlyph(label) ||
        ![Config[@"enabled"] boolValue] || (role==2 && ![Config[@"dateGradient"] boolValue]) ||
        !s.maskHasInk || !s.mask.contents || s.dateHost.superlayer!=host.layer ||
        s.gradient.superlayer!=s.dateHost || s.gradient.mask!=s.mask ||
        s.dateHost.hidden || s.gradient.hidden || s.gradient.opacity<.01 ||
        ![s.signature isEqualToString:DateSignature(label)] || !ImageVisible(host)) return NO;
    NSString *text=label.attributedText.string ?: label.text;
    if (!text.length || (role==1 && !TimeText(text)) || (role==2 && TimeText(text))) return NO;
    if (role==1 && [Config[@"clockEdgeEnabled"] boolValue] &&
        (!s.clockRim.path || s.clockRim.superlayer!=s.dateHost || s.clockRim.lineWidth<=0)) return NO;
    NSString *font=[Config[@"fontName"] isKindOfClass:NSString.class] ? Config[@"fontName"] : @"";
    if (role==1 && font.length && !ImportedFont &&
        ([Config[@"fontPath"] length] || ![UIFont fontWithName:font size:label.font.pointSize])) return NO;
    CGFloat alpha=0;
    for (id color in s.gradient.colors) alpha=MAX(alpha,CGColorGetAlpha((__bridge CGColorRef)color));
    if (alpha*s.gradient.opacity*s.dateHost.opacity<.01) return NO;
    CGRect rect=[s.dateHost convertRect:s.dateHost.bounds toLayer:label.window.layer];
    for (UIView *v=host; v; v=v.superview) if (v.clipsToBounds || v.layer.masksToBounds)
        rect=CGRectIntersection(rect,[v convertRect:v.bounds toView:label.window]);
    return LSGCImageCommitPolicy([Config[@"enabled"] boolValue],role==1,
        [Config[@"dateGradient"] boolValue],text.length>0,ImageGlyph(label)!=nil,
        ImageVisible(host),s.dateHost.superlayer==host.layer,s.maskHasInk,
        [s.signature isEqualToString:DateSignature(label)]) &&
        !CGRectIsEmpty(rect) && !CGRectIsInfinite(rect) && !CGRectIsNull(rect) &&
        CGRectIntersectsRect(rect,label.window.bounds);
}
static BOOL ImageSuppressed(UILabel *label, LSGCState *s) {
    NSArray *nodes=ImageNodes(label);
    if (!nodes.count || s.imageLeased.count!=nodes.count) return NO;
    for (UIView *view in nodes) {
        LSGCImageLease *lease=objc_getAssociatedObject(view.layer,&ImageLeaseKey);
        if (!lease || lease.source!=label || view.layer.mask!=lease.blank) return NO;
    }
    return YES;
}
static BOOL ImageCommit(UILabel *label, LSGCState *s) {
    if (!ImageReady(label,s)) { ImageLastReason=@"image-readiness-rejected"; return NO; }
    NSArray *nodes=ImageNodes(label);
    // Restore obsolete image layers when UIKit replaces its image-view tree.
    // Re-lease current nodes in the same outer disabled-actions transaction.
    ImageRestore(label);
    NSMutableArray *layers=[NSMutableArray array];
    ImageMutation=YES;
    @try {
        for (UIView *view in nodes) {
            CALayer *layer=view.layer;
            LSGCImageLease *lease=objc_getAssociatedObject(layer,&ImageLeaseKey);
            if (lease && lease.source!=label) @throw [NSException exceptionWithName:@"ImageLeaseConflict" reason:nil userInfo:nil];
            if (!lease) {
                lease=[LSGCImageLease new]; lease.source=label; lease.nativeMask=layer.mask;
                lease.blank=[CALayer layer]; lease.blank.frame=layer.bounds;
                objc_setAssociatedObject(layer,&ImageLeaseKey,lease,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            [layers addObject:layer]; s.imageLeased=[layers copy];
            ImageOrigMask(layer,@selector(setMask:),lease.blank);
            if (layer.mask!=lease.blank) @throw [NSException exceptionWithName:@"ImageMaskAttachFailed" reason:nil userInfo:nil];
            // Source lookup on layer uses the weak lease, avoiding retain cycles.
        }
        DiagInc(&ImageCommits); ImageLastReason=@"image-backed-mounted-and-native-masked";
    } @catch (NSException *exception) {
        ImageMutation=NO; ImageRestore(label); ImageLastReason=exception.name; return NO;
    } @finally { ImageMutation=NO; }
    return s.imageLeased.count==nodes.count && nodes.count>0;
}
static void ImageInvalidate(UILabel *source) {
    if (!source || !ImageRole(source) || ImageMutation || Rendering || !NSThread.isMainThread) return;
    LSGCState *s=objc_getAssociatedObject(source,&StateKey);
    if (s) {
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        @try { RemoveOverlay(source); } @finally { [CATransaction commit]; }
    }
    DiagInc(&ImageUpdates); Schedule(source);
}
static UILabel *ImageSourceForView(UIView *view) {
    for (UIView *v=view; v; v=v.superview) {
        if ([NSStringFromClass(v.class) isEqualToString:@"SBUILegibilityLabel"])
            for (UIView *child in v.subviews) if ([child isKindOfClass:UILabel.class] && ImageRole((UILabel *)child)) return (UILabel *)child;
        if ([NSStringFromClass(v.class) isEqualToString:@"SBFLockScreenDateView"]) break;
    }
    return nil;
}
static void ImageMaskHook(id obj, SEL sel, CALayer *mask) {
    LSGCImageLease *lease=objc_getAssociatedObject(obj,&ImageLeaseKey);
    if (lease && !ImageMutation) {
        lease.nativeMask=mask;
        // A system mask update is an invalidation, never restore an old mask.
        ImageOrigMask(obj,sel,mask); ImageInvalidate(lease.source); return;
    }
    ImageOrigMask(obj,sel,mask);
}
static void ImageContentsHook(id obj, SEL sel, id contents) {
    LSGCImageLease *lease=objc_getAssociatedObject(obj,&ImageLeaseKey);
    ImageOrigContents(obj,sel,contents);
    if (lease && !ImageMutation) ImageInvalidate(lease.source);
    else if (!Rendering && [NSStringFromClass([((CALayer *)obj).delegate class]) isEqualToString:@"_UILegibilityImageView"])
        ImageInvalidate(ImageSourceForView((UIView *)((CALayer *)obj).delegate));
}
static void ImageSetHook(id obj, SEL sel, UIImage *image) {
    ImageOrigSetImage(obj,sel,image);
    if ([NSStringFromClass([obj class]) isEqualToString:@"_UILegibilityImageView"])
        ImageInvalidate(ImageSourceForView((UIView *)obj));
}
static void ImageVisibilityEvent(UIView *view) {
    NSString *name=NSStringFromClass(view.class);
    if ([name isEqualToString:@"_UILegibilityImageView"] || [name isEqualToString:@"_UILegibilityView"] || [name isEqualToString:@"SBUILegibilityLabel"])
        ImageInvalidate(ImageSourceForView(view));
    else if ([name isEqualToString:@"UILabel"] && ImageRole((UILabel *)view)) ImageInvalidate((UILabel *)view);
}
static void ImageHiddenHook(id obj,SEL sel,BOOL hidden) {
    ImageOrigHidden(obj,sel,hidden); if (!Rendering && !ImageMutation) ImageVisibilityEvent((UIView *)obj);
}
static void ImageAlphaHook(id obj,SEL sel,CGFloat alpha) {
    ImageOrigAlpha(obj,sel,alpha); if (!Rendering && !ImageMutation) ImageVisibilityEvent((UIView *)obj);
}
static void InstallImageHooks(void) {
    if (!ImageOrigHidden) MSHookMessageEx(UIView.class,@selector(setHidden:),(IMP)ImageHiddenHook,(IMP *)&ImageOrigHidden);
    if (!ImageOrigAlpha) MSHookMessageEx(UIView.class,@selector(setAlpha:),(IMP)ImageAlphaHook,(IMP *)&ImageOrigAlpha);
    if (!ImageOrigMask) MSHookMessageEx(CALayer.class,@selector(setMask:),(IMP)ImageMaskHook,(IMP *)&ImageOrigMask);
    if (!ImageOrigContents) MSHookMessageEx(CALayer.class,@selector(setContents:),(IMP)ImageContentsHook,(IMP *)&ImageOrigContents);
    if (!ImageOrigSetImage) MSHookMessageEx(UIImageView.class,@selector(setImage:),(IMP)ImageSetHook,(IMP *)&ImageOrigSetImage);
}
