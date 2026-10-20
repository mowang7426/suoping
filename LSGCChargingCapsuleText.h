#pragma once
#import <Foundation/Foundation.h>
NS_INLINE NSString *LSGCCapsulePresentation(int state, NSInteger percent, NSInteger seconds, NSInteger target) {
    if (state!=2 && state!=3) return nil;
    if (state==2 && percent>=0 && percent<target && seconds>0 && target>=1 && target<=100)
        return [NSString stringWithFormat:@"%ld分钟\n充至%ld%%还需",(long)((seconds+59)/60),(long)target];
    return [NSString stringWithFormat:@"%@\n%@",state==3 ? @"已充满" : @"正在充电",percent<0 ? @"电量未知" : [NSString stringWithFormat:@"当前%ld%%",(long)percent]];
}
NS_INLINE BOOL LSGCCapsuleNeedsRender(NSString *cached, NSString *desired, NSString *actualTop, NSString *actualBottom, NSString *text) {
    NSArray *lines=[text componentsSeparatedByString:@"\n"];
    return ![cached isEqualToString:desired] || ![actualTop isEqualToString:lines.firstObject] || ![actualBottom isEqualToString:lines.count>1 ? lines[1] : @""];
}
