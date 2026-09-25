#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>

static CFStringRef const Domain=CFSTR("com.minis.lockscreengradientclock");
static CFStringRef const Changed=CFSTR("com.minis.lockscreengradientclock/changed");
static CFStringRef const Replied=CFSTR("com.minis.lockscreengradientclock/diagnosed");
@interface LSGCRootListController : PSListController <UIColorPickerViewControllerDelegate>
@property(nonatomic,copy) NSString *colorKey;
@property(nonatomic) BOOL waiting;
- (void)receivedReport;
@end
static void Reply(CFNotificationCenterRef center, void *observer, CFStringRef name,const void *object,CFDictionaryRef userInfo) {
    (void)center; (void)name; (void)object; (void)userInfo;
    LSGCRootListController *controller=(__bridge LSGCRootListController *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{ [controller receivedReport]; });
}
@implementation LSGCRootListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers=[self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"锁屏时间渐变";
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),(__bridge void *)self,Reply,Replied,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
}
- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),(__bridge void *)self,Replied,NULL);
}
- (void)save:(id)value key:(NSString *)key {
    if (!key.length || !value) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFPropertyListRef)value,Domain);
    CFPreferencesAppSynchronize(Domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),Changed,NULL,NULL,true);
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [self save:value key:[specifier propertyForKey:@"key"]];
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    if (!key) return [specifier propertyForKey:@"default"];
    CFPreferencesAppSynchronize(Domain);
    id value=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,Domain));
    return value ?: [specifier propertyForKey:@"default"];
}
- (void)chooseColor:(PSSpecifier *)specifier {
    self.colorKey=[specifier propertyForKey:@"key"];
    NSString *hex=[self readPreferenceValue:specifier];
    unsigned value=0;
    if ([hex isKindOfClass:NSString.class]) [[NSScanner scannerWithString:[hex stringByReplacingOccurrencesOfString:@"#" withString:@""]] scanHexInt:&value];
    UIColorPickerViewController *picker=[UIColorPickerViewController new];
    picker.delegate=self; picker.supportsAlpha=NO;
    picker.selectedColor=[UIColor colorWithRed:((value>>16)&255)/255.0 green:((value>>8)&255)/255.0 blue:(value&255)/255.0 alpha:1];
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)savePickerColor:(UIColorPickerViewController *)controller {
    CGFloat r=0,g=0,b=0,a=1;
    if ([controller.selectedColor getRed:&r green:&g blue:&b alpha:&a]) {
        NSString *hex=[NSString stringWithFormat:@"#%02X%02X%02X",(unsigned)lround(r*255),(unsigned)lround(g*255),(unsigned)lround(b*255)];
        [self save:hex key:self.colorKey];
    }
}
- (void)colorPickerViewController:(UIColorPickerViewController *)controller didSelectColor:(UIColor *)color continuously:(BOOL)continuously {
    (void)color; (void)continuously; [self savePickerColor:controller];
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)controller {
    [self savePickerColor:controller];
}
- (void)showMessage:(NSString *)message {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Liquidify 兼容诊断" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; UIPasteboard.generalPasteboard.string=message; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)resetEdges {
    NSArray *keys=@[@"edgeEnabled",@"edgePalette",@"edgeCore",@"edgeStrength",@"edgeWidth",@"edgeHighlight",@"edgeReveal"];
    for (NSString *key in keys) CFPreferencesSetAppValue((__bridge CFStringRef)key,NULL,Domain);
    CFPreferencesAppSynchronize(Domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),Changed,NULL,NULL,true);
    [self reloadSpecifiers];
}
- (void)diagnose {
    if (self.waiting) return;
    self.waiting=YES;
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR("com.minis.lockscreengradientclock/diagnose"),NULL,NULL,true);
    __weak LSGCRootListController *weak=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(), ^{
        LSGCRootListController *strong=weak;
        if (strong.waiting) {
            strong.waiting=NO;
            [strong showMessage:@"SpringBoard 未响应。请确认安装的是 1.1.0，已注销，且允许本插件注入 SpringBoard。此提示不是已成功适配的证明。"];
        }
    });
}
- (void)receivedReport {
    if (!self.waiting) return; self.waiting=NO;
    CFPreferencesAppSynchronize(Domain);
    NSString *report=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("diagnosticReport"),Domain));
    [self showMessage:report ?: @"收到响应但未读取到报告，请重试。"];
}
@end
