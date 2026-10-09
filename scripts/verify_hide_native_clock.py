#!/usr/bin/env python3
import pathlib, plistlib
r=pathlib.Path(__file__).resolve().parents[1]
s=(r/'Tweak.xm').read_text(); p=plistlib.loads((r/'Preferences/Resources/Root.plist').read_bytes())
items={x['key']:x for x in p['items'] if 'key' in x}
assert 'hideNativeClock' in items
x=items['hideNativeClock']; assert x['cell']=='PSSwitchCell' and x['default'] is False
assert x['label']=='隐藏原生锁屏时间' and '自定义渲染失败时可能无时间' in x['footerText']
assert '@"hideNativeClock":@NO' in s
assert 'Config[@"enabled"] boolValue] && [Config[@"hideNativeClock"] boolValue]' in s
assert 'NativeClockSuppressionEnabled() && IsStandaloneTimeLabel' in s
assert 'label.layer.contents=nil' in s and 'label.layer setNeedsDisplay' in s
# Date/lunar labels cannot enter the suppression predicate.
assert 'if (!IsStandaloneTimeLabel(label)) continue;' in s
assert 'setHidden:' not in s and 'setAlpha:' not in s
assert (r/'LSGCHideNativeClock.h').exists() and (r/'tests/hide_native_clock_test.cpp').exists()
print('OK: default-off strict main-label suppression, reversible redraw, date isolation, no global setters')
