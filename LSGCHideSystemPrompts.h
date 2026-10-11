#pragma once
#import <UIKit/UIKit.h>
#ifdef __cplusplus
extern "C" {
#endif
void LSGCHideSystemPromptsInstall(void);
void LSGCHideSystemPromptsRefresh(BOOL enabled, BOOL hide);
void LSGCSystemPromptObserve(UILabel *label);
BOOL LSGCSystemPromptRecognized(UILabel *label);
BOOL LSGCSystemPromptShouldSuppress(UILabel *label);
NSString *LSGCSystemPromptsReport(void);
void LSGCHideSystemPromptsClear(void);
#ifdef __cplusplus
}
#endif
