#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface LSGCRootListController : PSListController
@end
@implementation LSGCRootListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSMutableDictionary *d=[[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"com.minis.lockscreengradientclock"] mutableCopy] ?: [NSMutableDictionary dictionary];
    d[specifier.properties[@"key"]]=value;
    [[NSUserDefaults standardUserDefaults] setPersistentDomain:d forName:@"com.minis.lockscreengradientclock"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [super setPreferenceValue:value specifier:specifier];
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *d=[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"com.minis.lockscreengradientclock"];
    return d[specifier.properties[@"key"]] ?: specifier.properties[@"default"];
}
@end
