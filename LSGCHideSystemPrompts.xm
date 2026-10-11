#import "LSGCHideSystemPrompts.h"
#import "LSGCPromptPolicy.h"
#import <objc/runtime.h>

static char PromptStateKey;
static BOOL PromptEnabled, PromptHide;
static NSHashTable<UILabel *> *PromptLabels;
static unsigned long long Suppressions, Restores;
@interface LSGCPromptState : NSObject { @public LSGCPrompt::State policy; }
@end
@implementation LSGCPromptState @end

static LSGCPrompt::Input PromptInput(UILabel *label) {
    LSGCPrompt::Input in;
    in.text=(label.text ?: label.attributedText.string ?: @"").UTF8String;
    in.label=[label isKindOfClass:UILabel.class]; in.leaf=label.subviews.count==0;
    in.attached=label.window!=nil;
    // Existing charging capsule label identity; no change to its drawing/content.
    in.owned=label.tag==7001;
    unsigned depth=0;
    for(UIView *v=label;v && depth<64;v=v.superview,++depth) {
        in.chain.emplace_back(class_getName(v.class));
        if([v.accessibilityIdentifier hasPrefix:@"LSGC."]) in.owned=true;
    }
    return in;
}
BOOL LSGCSystemPromptRecognized(UILabel *label) {
    return LSGCPrompt::identify(PromptInput(label)).kind!=LSGCPrompt::Kind::none;
}
BOOL LSGCSystemPromptShouldSuppress(UILabel *label) {
    // Read-only glyph gate. Never Apply, schedule, or mutate state while drawing.
    return PromptEnabled && PromptHide && LSGCSystemPromptRecognized(label);
}
void LSGCSystemPromptObserve(UILabel *label) {
    if(!NSThread.isMainThread) return;
    auto r=LSGCPrompt::identify(PromptInput(label));
    LSGCPromptState *st=objc_getAssociatedObject(label,&PromptStateKey);
    if(!st && r.kind!=LSGCPrompt::Kind::none) {
        LSGCHideSystemPromptsInstall(); st=[LSGCPromptState new];
        objc_setAssociatedObject(label,&PromptStateKey,st,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [PromptLabels addObject:label];
    }
    if(!st || !st->policy.update(r,PromptEnabled,PromptHide)) return;
    if(st->policy.suppressed) ++Suppressions; else ++Restores;
    // Do not save/restore alpha/hidden: system always owns their latest semantics.
    [label setNeedsDisplay];
}
void LSGCHideSystemPromptsInstall(void) {
    if(!PromptLabels) PromptLabels=[NSHashTable weakObjectsHashTable];
}
void LSGCHideSystemPromptsRefresh(BOOL enabled, BOOL hide) {
    PromptEnabled=enabled; PromptHide=hide;
    for(UILabel *label in PromptLabels.allObjects) LSGCSystemPromptObserve(label);
}
void LSGCHideSystemPromptsClear(void) { LSGCHideSystemPromptsRefresh(NO,NO); }
static void PromptReportWalk(UIView *view, NSMutableArray *lines, NSUInteger depth, NSUInteger *count) {
    if(depth>64) return;
    if([view isKindOfClass:UILabel.class]) {
        UILabel *label=(UILabel *)view; auto in=PromptInput(label); auto r=LSGCPrompt::identify(in);
        BOOL relevant=LSGCPrompt::charging(in.text);
        for(const auto &n:in.chain) if(n=="SBFLockScreenDateView" || n=="CSTeachableMomentsContainerView") relevant=YES;
        if(relevant && (*count)++<80) {
            NSMutableArray *chain=[NSMutableArray array]; for(const auto &n:in.chain) [chain addObject:[NSString stringWithUTF8String:n.c_str()]];
            [lines addObject:[NSString stringWithFormat:@"node=%@ %p ancestor=%@ target-kind=%s reason=%s glyphSuppressed=%d alpha=%.3f hidden=%d",NSStringFromClass(label.class),label,[chain componentsJoinedByString:@" > "],r.kind==LSGCPrompt::Kind::charging?"charging-leaf":(r.kind==LSGCPrompt::Kind::unlock?"unlock-leaf":"none"),r.reason,LSGCSystemPromptShouldSuppress(label),label.alpha,label.hidden]];
        }
    }
    for(UIView *child in view.subviews) PromptReportWalk(child,lines,depth+1,count);
}
NSString *LSGCSystemPromptsReport(void) {
    NSMutableArray *lines=[NSMutableArray arrayWithObject:[NSString stringWithFormat:@"=== SystemPromptDiagnostics v2 ===\nenabled=%d hideLockScreenPrompts=%d effective=%d strategy=leaf-draw-only suppressions=%llu restores=%llu\nSnapshotText bypass; no alpha/hidden writes; counts are state transitions, not proof of visible pixels.",PromptEnabled,PromptHide,PromptEnabled&&PromptHide,Suppressions,Restores]];
    NSMutableSet *windows=[NSMutableSet set];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) if([scene isKindOfClass:UIWindowScene.class]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    NSUInteger count=0; for(UIWindow *w in windows) PromptReportWalk(w,lines,0,&count);
    [lines addObject:[NSString stringWithFormat:@"relevantNodes=%lu (up to 80 listed; text not logged; on-demand only)\n=== End SystemPromptDiagnostics ===",(unsigned long)count]];
    return [lines componentsJoinedByString:@"\n"];
}
