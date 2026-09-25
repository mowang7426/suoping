#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

static CFStringRef const Domain=CFSTR("com.minis.lockscreengradientclock");
static CFStringRef const Changed=CFSTR("com.minis.lockscreengradientclock/changed");
static CFStringRef const Replied=CFSTR("com.minis.lockscreengradientclock/diagnosed");
@interface LSGCRootListController : PSListController <UIColorPickerViewControllerDelegate>
@property(nonatomic,copy) NSString *colorKey;
@property(nonatomic) BOOL waiting;
@property(nonatomic) BOOL editCheckpointMade;
- (NSDictionary *)visualSchema;
- (void)checkpoint;
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
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; self.editCheckpointMade=NO;
}
- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),(__bridge void *)self,Replied,NULL);
}
- (void)save:(id)value key:(NSString *)key {
    if (!key.length || !value) return;
    if ([self visualSchema][key]) [self checkpoint];
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
    [self checkpoint];
    NSArray *keys=@[@"edgeEnabled",@"edgePalette",@"edgeCore",@"edgeStrength",@"edgeWidth",@"edgeHighlight",@"edgeReveal",@"independentEdges",@"edgeColor1",@"edgeColor2",@"edgeColor3"];
    for (NSString *key in keys) CFPreferencesSetAppValue((__bridge CFStringRef)key,NULL,Domain);
    CFPreferencesAppSynchronize(Domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),Changed,NULL,NULL,true);
    [self reloadSpecifiers];
}
// Presets contain visual options only. Global enable, scope and mask compatibility
// remain device-specific and are never overwritten when applying a palette.
- (NSDictionary *)visualSchema {
    NSString *path=[[NSBundle bundleForClass:self.class] pathForResource:@"Root" ofType:@"plist"];
    NSDictionary *root=[NSDictionary dictionaryWithContentsOfFile:path];
    NSMutableDictionary *schema=[NSMutableDictionary dictionary];
    NSSet *excluded=[NSSet setWithArray:@[@"enabled",@"strictScope",@"maskMode"]];
    for (NSDictionary *item in root[@"items"]) {
        NSString *key=item[@"key"];
        if (key && item[@"default"] && ![excluded containsObject:key]) schema[key]=item;
    }
    return schema;
}
- (NSDictionary *)validatedVisuals:(NSDictionary *)input {
    if (![input isKindOfClass:NSDictionary.class]) input=@{};
    NSDictionary *schema=[self visualSchema];
    NSMutableDictionary *output=[NSMutableDictionary dictionary];
    for (NSString *key in schema) {
        NSDictionary *item=schema[key]; id value=input[key],fallback=item[@"default"];
        if ([fallback isKindOfClass:NSNumber.class]) {
            if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue])) value=fallback;
            if ([item[@"cell"] isEqualToString:@"PSSwitchCell"]) value=@([value boolValue]);
            if (item[@"min"]) value=@(MAX([item[@"min"] doubleValue],[value doubleValue]));
            if (item[@"max"]) value=@(MIN([item[@"max"] doubleValue],[value doubleValue]));
            if (item[@"validValues"] && ![item[@"validValues"] containsObject:value]) value=fallback;
        } else if ([fallback isKindOfClass:NSString.class]) {
            if (![value isKindOfClass:NSString.class]) value=fallback;
            if ([key hasPrefix:@"color"] || [key hasPrefix:@"edgeColor"]) {
                NSPredicate *hex=[NSPredicate predicateWithFormat:@"SELF MATCHES %@",@"#[0-9A-Fa-f]{6}"];
                if (![hex evaluateWithObject:value]) value=fallback;
            }
        } else value=fallback;
        output[key]=value;
    }
    return output;
}
- (NSDictionary *)currentVisuals {
    CFPreferencesAppSynchronize(Domain);
    NSMutableDictionary *values=[NSMutableDictionary dictionary];
    for (NSString *key in [self visualSchema]) {
        id v=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,Domain));
        if (v) values[key]=v;
    }
    return [self validatedVisuals:values];
}
- (void)checkpoint {
    if (self.editCheckpointMade) return;
    NSDictionary *snapshot=[self currentVisuals];
    CFPreferencesSetAppValue(CFSTR("previousVisuals"),(__bridge CFDictionaryRef)snapshot,Domain);
    CFPreferencesAppSynchronize(Domain);
    self.editCheckpointMade=YES;
}
- (void)writeVisuals:(NSDictionary *)values {
    NSDictionary *clean=[self validatedVisuals:values];
    for (NSString *key in clean) CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFPropertyListRef)clean[key],Domain);
    CFPreferencesAppSynchronize(Domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),Changed,NULL,NULL,true);
    [self reloadSpecifiers];
}
- (void)paletteMessage:(NSString *)text {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"配色方案" message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (NSMutableArray *)savedPalettes {
    CFPreferencesAppSynchronize(Domain);
    id stored=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("savedPalettes"),Domain));
    NSMutableArray *list=[NSMutableArray array];
    if ([stored isKindOfClass:NSArray.class]) for (id item in stored) {
        if ([item isKindOfClass:NSDictionary.class] && [item[@"name"] isKindOfClass:NSString.class] &&
            [item[@"values"] isKindOfClass:NSDictionary.class] && [item[@"schema"] isEqual:@1] && list.count<20) [list addObject:item];
    }
    return list;
}
- (void)storePalettes:(NSArray *)list {
    CFPreferencesSetAppValue(CFSTR("savedPalettes"),(__bridge CFArrayRef)list,Domain);
    if (!CFPreferencesAppSynchronize(Domain)) [self paletteMessage:@"保存失败，请检查设备存储后重试。"];
}
- (void)savePalette {
    NSMutableArray *list=[self savedPalettes];
    if (list.count>=20) { [self paletteMessage:@"最多保存 20 个方案，请先删除不用的方案。"] ; return; }
    NSDictionary *snapshot=[self currentVisuals];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"保存当前效果" message:@"保存颜色、角度、位置、玻璃和彩边参数；不更改原插件。名称最多 32 字。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder=@"例如：紫色壁纸"; }];
    __weak UIAlertController *weakAlert=a;
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        NSString *name=[weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!name.length || name.length>32) { [self paletteMessage:@"请输入 1～32 字的名称。"] ; return; }
            NSMutableArray *current=[self savedPalettes];
            for (NSDictionary *entry in current) if ([entry[@"name"] isEqual:name]) { [self paletteMessage:@"已有同名方案。请换一个名称，旧方案没有被覆盖。"] ; return; }
            if (current.count>=20) { [self paletteMessage:@"方案已满，请先删除一个。"] ; return; }
            [current addObject:@{@"name":name,@"values":snapshot,@"schema":@1}];
            [self storePalettes:current];
        });
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)selectPaletteDeleting:(BOOL)deleting {
    NSArray *list=[self savedPalettes];
    if (!list.count) { [self paletteMessage:@"还没有保存的配色方案。"] ; return; }
    UIAlertController *a=[UIAlertController alertControllerWithTitle:deleting?@"删除方案":@"切换方案" message:deleting?@"仅删除保存的方案，不改变当前效果。":@"切换前会保留当前效果，可用恢复上一次设置撤销。" preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *entry in list) {
        [a addAction:[UIAlertAction actionWithTitle:entry[@"name"] style:deleting?UIAlertActionStyleDestructive:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            (void)action;
            if (deleting) {
                NSMutableArray *current=[self savedPalettes];
                NSIndexSet *indexes=[current indexesOfObjectsPassingTest:^BOOL(NSDictionary *value,NSUInteger index,BOOL *stop) {
                    (void)index; (void)stop; return [value[@"name"] isEqual:entry[@"name"]];
                }];
                [current removeObjectsAtIndexes:indexes]; [self storePalettes:current];
            } else {
                self.editCheckpointMade=NO; [self checkpoint];
                [self writeVisuals:entry[@"values"]]; self.editCheckpointMade=NO;
            }
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView=self.view;
    a.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMidY(self.view.bounds),1,1);
    [self presentViewController:a animated:YES completion:nil];
}
- (void)loadPalette { [self selectPaletteDeleting:NO]; }
- (void)deletePalette { [self selectPaletteDeleting:YES]; }
- (void)restorePrevious {
    CFPreferencesAppSynchronize(Domain);
    id previous=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("previousVisuals"),Domain));
    if (![previous isKindOfClass:NSDictionary.class]) { [self paletteMessage:@"还没有可恢复的设置。首次手动调整或切换方案前会自动保存快照。"] ; return; }
    NSDictionary *current=[self currentVisuals];
    CFPreferencesSetAppValue(CFSTR("previousVisuals"),(__bridge CFDictionaryRef)current,Domain);
    [self writeVisuals:previous]; self.editCheckpointMade=NO;
}
- (void)reversePalette {
    CFPreferencesAppSynchronize(Domain);
    id value=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("reverseColors"),Domain));
    [self save:@(![value boolValue]) key:@"reverseColors"];
    [self reloadSpecifiers];
}
- (void)resetGradientGeometry {
    [self checkpoint];
    NSArray *keys=@[@"customAngleEnabled",@"gradientAngle",@"customStopsEnabled",@"stop1",@"stop2",@"stop3",@"stop4",@"stop5",@"reverseColors"];
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
            [strong showMessage:@"SpringBoard 未响应。请确认安装的是 1.4.0，已注销，且允许本插件注入 SpringBoard。此提示不是已成功适配的证明。"];
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
