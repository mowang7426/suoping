#!/usr/bin/env python3
"""Source contracts complement executable Foundation production-bridge tests."""
from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
b=(r/'LSGCNotificationsAppBar.mm').read_text()
s=(r/'LSGCNotificationsAppBarRuntime.mm').read_text()
v=(r/'LSGCNotificationsAppBarView.mm').read_text()
t=(r/'Tweak.xm').read_text()
for forbidden in ['NativeFilterSemanticsVerified','return false; } // semantic','toggleFilteringForSectionIdentifier','persistentStoredListInfo','filteredNotificationRequests','allNotificationRequests =','scheduledTimer','CADisplayLink','dispatch_after','setNeedsDisplay','NSLog(']:
    assert forbidden not in b+s, forbidden
for getter in ['"content"','"bulletin"','"userNotification"','"context"']:
    assert getter not in b, 'notification body read: '+getter
assert '"insertNotificationRequest:"' in b and '"removeNotificationRequest:"' in b
assert 'native-display-restore-not-applied' in b and 'native-display-remove-not-applied' in b
assert 'method_copyArgumentType' in b+s and 'method_copyReturnType' in b+s
assert 'class_getInstanceMethod' in b+s and 'isKindOfClass' in b+s
assert 'operatingSystemVersion.majorVersion!=17' in s
assert 'origInsert(self,cmd,request);' in s and 'origWithdraw(self,cmd,request); Observe(request,YES);' in s
assert 'origDispatcherWithdraw(self,cmd,request); Observe(request,YES);' in s
assert 'LSGCNotificationProjectionDepth' in b+s and 'MutationBudget' in b
assert 'self.owned[key]=entry;' in b and b.index('self.owned[key]=entry;',b.index('- (BOOL)reconcile'))<b.index('Send(controller,"removeNotificationRequest:"')
assert '_updateNotificationListPersistentState' in s and 'self==presentationMaster' in s and 'FlushPersistence();' in s
assert 'origDestroy(self,cmd)' in s and 'sourceDestroyed' in b+s
assert 'convertRect:' in s and 'flashlightButton' in s and 'cameraButton' in s and 'LSGCChargingETAPill' in s
assert 'CGContext' not in s and 'viewDidLayoutSubviews' in s and 'dispatch_async(dispatch_get_main_queue()' in s
assert 'LetterIcon(app)' in v and 'UIAccessibilityTraitSelected' in v
assert 'LSGCNotificationsAppBarConfigure([Config[@"enabled"] boolValue] && [Config[@"notificationAppBar"] boolValue]);' in t
assert 'LSGCNotificationsAppBarDiagnostic()' in t
settings={x['key']:x for x in plistlib.loads((r/'Preferences/Resources/Root.plist').read_bytes())['items'] if 'key' in x}
assert settings['notificationAppBar']['default'] is False
for source in ['LSGCNotificationsAppBar.mm','LSGCNotificationsAppBarRuntime.mm','LSGCNotificationsAppBarView.mm']:
    assert source in (r/'Makefile').read_text()
assert 'notification_app_bar_bridge_test.mm' in (r/'.github/workflows/build.yml').read_text()
print('PASS notification bar: real native display sends, original-first sources, runtime ABI/class/lock/geometry, own-only memory restoration, no body IO/timers/master-array rewrite, default OFF, build/settings/diagnostics integration')
