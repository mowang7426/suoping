// Included after render/hook definitions; diagnostics do not authorize rendering.
static NSString *DiagGeometry(UIView *view, CALayer *host) {
    NSMutableArray *chain=[NSMutableArray array];
    CGRect intersection=view.window ? [view convertRect:view.bounds toView:view.window] : CGRectZero;
    CGRect overlay=host && view.window ? [host convertRect:host.bounds toLayer:view.window.layer] : CGRectZero;
    CGRect clipped=overlay;
    for (UIView *v=view; v; v=v.superview) {
        CGRect rect=view.window ? [v convertRect:v.bounds toView:view.window] : CGRectZero;
        if (v.clipsToBounds) { intersection=CGRectIntersection(intersection,rect); clipped=CGRectIntersection(clipped,rect); }
        [chain addObject:[NSString stringWithFormat:@"%@ %p hidden=%d alpha=%.4f clipsToBounds=%d windowRect=%@ labelIntersection=%@ overlayIntersection=%@",
            NSStringFromClass(v.class),v,v.hidden,v.alpha,v.clipsToBounds,NSStringFromCGRect(rect),NSStringFromCGRect(intersection),NSStringFromCGRect(clipped)]];
    }
    return [NSString stringWithFormat:@"label/windowRect=%@ host/overlayWindowRect=%@ windowBounds=%@\n完整祖先链（label -> window）：\n%@",
        view.window ? NSStringFromCGRect([view convertRect:view.bounds toView:view.window]) : @"no-window",
        NSStringFromCGRect(overlay),view.window ? NSStringFromCGRect(view.window.bounds) : @"no-window",[chain componentsJoinedByString:@"\n"]];
}
static NSDictionary *DiagGate(UILabel *label) {
    LSGCState *s=objc_getAssociatedObject(label,&StateKey);
    NSString *name=[Config[@"fontName"] isKindOfClass:NSString.class] ? Config[@"fontName"] : @"";
    BOOL identity=IsStandaloneTimeLabel(label);
    BOOL fontReady=!name.length || ImportedFont!=nil || (![Config[@"fontPath"] length] && [UIFont fontWithName:name size:label.font.pointSize]!=nil);
    BOOL attached=s && s.dateHost && s.gradient && s.mask && s.dateHost.superlayer==label.layer && s.gradient.superlayer==s.dateHost && s.gradient.mask==s.mask && s.mask.contents!=nil;
    CGRect rect=attached && label.window ? [s.dateHost convertRect:s.dateHost.bounds toLayer:label.window.layer] : CGRectZero;
    BOOL onScreen=!CGRectIsEmpty(rect) && !CGRectIsInfinite(rect) && !CGRectIsNull(rect) &&
        isfinite(rect.origin.x) && isfinite(rect.origin.y) && isfinite(rect.size.width) && isfinite(rect.size.height) && CGRectIntersectsRect(rect,label.window.bounds);
    for (UIView *v=label; onScreen && v; v=v.superview) {
        if (v.clipsToBounds) { rect=CGRectIntersection(rect,[v convertRect:v.bounds toView:label.window]); onScreen=!CGRectIsEmpty(rect) && !CGRectIsNull(rect); }
    }
    CGFloat colorAlpha=0;
    for (id color in s.gradient.colors) colorAlpha=MAX(colorAlpha,CGColorGetAlpha((__bridge CGColorRef)color));
    CGFloat opacity=s.gradient.opacity*s.dateHost.opacity*colorAlpha;
    NSMutableDictionary *gate=[@{@"identity":@(identity),@"hookReady":@(Hooked && LabelHooked),@"committed":@(s.clockCommitted),
        @"enabled":@([Config[@"enabled"] boolValue]),@"fontReady":@(fontReady),@"maskHasInk":@(s.maskHasInk),@"attached":@(attached),
        @"visible":@(Visible(label)),@"onScreen":@(onScreen),@"signatureCurrent":@([s.signature isEqualToString:DateSignature(label)]),@"opacity":@(opacity)} mutableCopy];
    NSMutableArray *failed=[NSMutableArray array];
    for (NSString *key in @[@"identity",@"hookReady",@"committed",@"enabled",@"fontReady",@"maskHasInk",@"attached",@"visible",@"onScreen",@"signatureCurrent"])
        if (![gate[key] boolValue]) [failed addObject:key];
    if (!(opacity>=0.01)) [failed addObject:@"opacity"];
    gate[@"failedReasons"]=failed;
    gate[@"label"]=[NSString stringWithFormat:@"%@ %p",NSStringFromClass(label.class),label];
    gate[@"geometry"]=DiagGeometry(label,s.dateHost);
    return gate;
}
static void DiagCaptureFailure(UILabel *label, NSString *reason) {
    NSMutableDictionary *gate=[DiagGate(label) mutableCopy];
    gate[@"earlyReturn"]=reason ?: @"unknown";
    gate[@"capturedBeforeRemoval"]=@YES;
    DiagFailure=gate;
}
static void DiagCaptureMask(UIImage *image, CGSize requested, CGFloat scale) {
    size_t w=image.CGImage ? CGImageGetWidth(image.CGImage) : 0, h=image.CGImage ? CGImageGetHeight(image.CGImage) : 0;
    CGRect bbox=CGRectNull; NSString *status=@"no-image";
    // One bounded scan per rebuilt main-clock snapshot, never on layout/draw.
    if (w && h && w<=4096 && h<=4096 && w*h<=8388608) {
        unsigned char *pixels=(unsigned char *)calloc(w*h,4);
        CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx=pixels ? CGBitmapContextCreate(pixels,w,h,8,w*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big) : NULL;
        CGColorSpaceRelease(space);
        if (ctx) {
            CGContextDrawImage(ctx,CGRectMake(0,0,w,h),image.CGImage);
            size_t minX=w,minY=h,maxX=0,maxY=0; BOOL ink=NO;
            for (size_t y=0;y<h;y++) for (size_t x=0;x<w;x++) if (pixels[(y*w+x)*4+3]>8) {
                ink=YES; minX=MIN(minX,x); minY=MIN(minY,y); maxX=MAX(maxX,x); maxY=MAX(maxY,y);
            }
            if (ink) bbox=CGRectMake(minX,minY,maxX-minX+1,maxY-minY+1);
            status=ink ? @"ink" : @"empty"; CGContextRelease(ctx);
        } else status=@"allocation-failed";
        free(pixels);
    } else if (w && h) status=@"budget-exceeded";
    DiagMask=@{@"source":@"SnapshotText/main-clock",@"requestedSize":NSStringFromCGSize(requested),@"size":NSStringFromCGSize(image.size),
        @"requestedScale":@(scale),@"scale":@(image.scale),@"pixelWidth":@(w),@"pixelHeight":@(h),@"HasAlpha":@(HasAlpha(image)),
        @"maskPixelBoundingBox":NSStringFromCGRect(bbox),@"bboxCoordinates":@"bitmap pixel coordinates, alpha > 8",@"status":status};
}
static Class DiagMethodOwner(Class cls, SEL sel) {
    for (Class c=cls; c; c=class_getSuperclass(c)) {
        unsigned count=0; Method *methods=class_copyMethodList(c,&count); BOOL found=NO;
        for (unsigned i=0;i<count;i++) if (method_getName(methods[i])==sel) { found=YES; break; }
        free(methods); if (found) return c;
    }
    return Nil;
}
static NSString *DiagScope(UIView *view) {
    NSMutableArray *names=[NSMutableArray array];
    for (UIView *v=view;v;v=v.superview) [names addObject:NSStringFromClass(v.class)];
    BOOL label=[names.firstObject isEqualToString:@"_UIAnimatingLabel"],subtitle=NO; unsigned stage=0;
    for (NSUInteger i=1;i<names.count && i<64;i++) {
        NSString *n=names[i];
        if ([n isEqualToString:@"CSProminentSubtitleDateView"] || [n isEqualToString:@"BSUIRelativeDateLabel"]) subtitle=YES;
        if (stage==0 && [n isEqualToString:@"CSProminentTimeView"]) stage=1;
        else if (stage==1 && [n isEqualToString:@"CSProminentDisplayView"]) stage=2;
        else if (stage==2 && [n isEqualToString:@"SBFLockScreenDateView"]) stage=3;
    }
    BOOL identity=[view isKindOfClass:UILabel.class] && IsStandaloneTimeLabel((UILabel *)view);
    NSString *reason=!label ? @"not-exact-_UIAnimatingLabel" : (subtitle ? @"subtitle/relative-date-excluded" : (stage<3 ? @"missing-or-out-of-order-required-ancestor" : @"none"));
    NSString *category=identity ? @"main-clock-identity (not proof of draw success)" : @"other/non-main";
    for (NSString *n in names) {
        if ([n containsString:@"Subtitle"] || [n containsString:@"RelativeDate"]) { category=@"date/subtitle (never main-clock success)"; break; }
        if ([n containsString:@"Notification"] || [n hasPrefix:@"NC"]) category=@"notification-time (never main-clock success)";
        if ([n containsString:@"Charging"] || [n containsString:@"Battery"]) category=@"charging-estimate (never main-clock success)";
    }
    return [NSString stringWithFormat:@"category=%@ strictScopeRequested=%d stage0/exactLabel=%d stage1/time=%d stage2/display=%d stage3/lockDate=%d subtitleExcluded=%d identity=%d InLockScreen=%d rejectedReason=%@ scopeDepthLimit=64 ancestorCount=%lu",
        category,[Config[@"strictScope"] boolValue],label,stage>=1,stage>=2,stage>=3,subtitle,identity,InLockScreen(view),reason,(unsigned long)names.count];
}
static NSString *DiagReport(void) {
    NSMutableArray *lines=[NSMutableArray array];
    [lines addObject:@"\n\n=== RealClockDiagnostics v1 ===\n计数为进程累计；主时间 draw 排除 SnapshotText 镜像绘制及 super 链重复调用。安全门通过/附加遮罩不等于真机视觉成功。\n日期渐变、通知时间、充电预估一律不能计入主时间成功。"];
    [lines addObject:[NSString stringWithFormat:@"InstallHooks=%llu Hooked=%d LabelHooked=%d NativeClassesLoaded=%d\nhookCalls layout=%llu didMove=%llu draw=%llu\nmainClockDraw=%llu nativePass=%llu customSuppress=%llu\nSchedule=%llu lastEarlyReturn=%@\nApply=%llu lastEarlyReturn=%@",
        DiagInstall,Hooked,LabelHooked,NativeClassesLoaded,DiagLayout,DiagMove,DiagDraw,DiagMainDraw,DiagNative,DiagSuppress,DiagSchedule,DiagScheduleReturn?:@"none",DiagApply,DiagApplyReturn?:@"none"]];
    for (NSString *name in @[@"UIView",@"UILabel",@"SBFLockScreenDateView",@"CSProminentTimeView",@"CSProminentDisplayView",@"_UIAnimatingLabel"]) {
        Class cls=NSClassFromString(name);
        NSArray *selectors=[name isEqualToString:@"UIView"] ? @[@"didMoveToWindow"] : ([cls isSubclassOfClass:UILabel.class] || [name isEqualToString:@"_UIAnimatingLabel"] ? @[@"layoutSubviews",@"didMoveToWindow",@"drawTextInRect:",@"setText:",@"setAttributedText:"] : @[@"layoutSubviews",@"didMoveToWindow"]);
        for (NSString *method in selectors) {
            SEL sel=NSSelectorFromString(method); Class owner=DiagMethodOwner(cls,sel);
            NSString *key=[NSString stringWithFormat:@"%@/%@",name,method];
            NSString *ownerKey=[NSString stringWithFormat:@"%@/%@",NSStringFromClass(owner),method];
            IMP original=(IMP)[DiagOriginals[key] pointerValue], inheritedOriginal=(IMP)[DiagOriginals[ownerKey] pointerValue];
            IMP expected=(IMP)[DiagExpected[original ? key : ownerKey] pointerValue];
            Method m=cls ? class_getInstanceMethod(cls,sel) : NULL; IMP current=m ? method_getImplementation(m) : NULL;
            [lines addObject:[NSString stringWithFormat:@"hookTarget=%@ loaded=%d methodOwner=%@ originalIMPExists=%d ownerOriginalIMPExists=%d currentIMPExists=%d currentMatchesExpectedHook=%d installedKey=%d original=%p current=%p coverage=%@",
                key,cls!=Nil,owner ? NSStringFromClass(owner) : @"none",original!=NULL,inheritedOriginal!=NULL,current!=NULL,expected!=NULL && current==expected,[ClockHookKeys containsObject:key],(void *)(original ?: inheritedOriginal),(void *)current,
                original ? @"direct-recorded" : (inheritedOriginal ? @"inherited-recorded" : @"not-recorded")]];
        }
    }
    [lines addObject:[NSString stringWithFormat:@"SnapshotText last main-clock mask=%@\nfailure-before-removal last=%@",DiagMask?:@{@"status":@"never-attempted"},DiagFailure?:@{@"status":@"none-recorded"}]];
    NSMutableSet<NSValue *> *seen=[NSMutableSet set]; NSMutableArray<UIView *> *queue=[NSMutableArray array];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [queue addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) if ([scene isKindOfClass:UIWindowScene.class]) [queue addObjectsFromArray:((UIWindowScene *)scene).windows];
    NSUInteger candidates=0;
    for (NSUInteger i=0;i<queue.count;i++) {
        UIView *view=queue[i]; NSValue *key=[NSValue valueWithPointer:(__bridge const void *)view];
        if ([seen containsObject:key]) continue; [seen addObject:key];
        [queue addObjectsFromArray:view.subviews];
        BOOL candidate=[NSStringFromClass(view.class) isEqualToString:@"_UIAnimatingLabel"];
        for (UIView *v=view;!candidate && v;v=v.superview) candidate=[NSStringFromClass(v.class) isEqualToString:@"CSProminentTimeView"];
        if (!candidate) continue; candidates++;
        LSGCState *state=objc_getAssociatedObject(view,&StateKey);
        [lines addObject:[NSString stringWithFormat:@"\nCandidate #%lu %@ %p\n%@\n%@",(unsigned long)candidates,NSStringFromClass(view.class),view,DiagScope(view),DiagGeometry(view,state.dateHost)]];
        if ([view isKindOfClass:UILabel.class]) [lines addObject:[NSString stringWithFormat:@"currentGate=%@",DiagGate((UILabel *)view)]];
    }
    [lines addObject:[NSString stringWithFormat:@"allCandidateCount=%lu (on-demand scan, no persistent candidate retention)",(unsigned long)candidates]];
    NSMutableDictionary *configuration=[NSMutableDictionary dictionary];
    for (NSString *key in @[@"enabled",@"strictScope",@"opacity",@"dateGradient",@"fontName",@"fontPath",@"clockScale",@"clockWidth",@"clockHeight",@"clockOffsetX",@"clockOffsetY",@"clockSpacing",@"clockColonScale",@"clockThickness",@"clockThin",@"clockBold",@"maskMode",@"glassBlend",@"glassTint"])
        configuration[key]=Config[key] ?: @"unset";
    for (NSString *key in Config) if ([key hasPrefix:@"font"] || [key hasPrefix:@"clock"]) configuration[key]=Config[key];
    [lines addObject:[NSString stringWithFormat:@"font/clock config=%@\nfontStatus=%@ importedFont=%@\n=== End RealClockDiagnostics ===",configuration,FontStatus?:@"none",ImportedFont.fontName?:@"none"]];
    return [lines componentsJoinedByString:@"\n"];
}
