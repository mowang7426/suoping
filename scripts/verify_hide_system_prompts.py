#!/usr/bin/env python3
"""Static contract for conservative iOS 17 system-prompt suppression."""
from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
s=(r/'LSGCHideSystemPrompts.xm').read_text()
t=(r/'Tweak.xm').read_text(); p=plistlib.loads((r/'Preferences/Resources/Root.plist').read_bytes())
items={x['key']:x for x in p['items'] if 'key' in x}
x=items['hideLockScreenPrompts']; assert x['cell']=='PSSwitchCell' and x['default'] is False
assert '明确' not in x['footerText'] or '严格识别' in x['footerText']
assert '@"hideLockScreenPrompts":@NO' in t
for cls in ('SBUILockScreenActionButton','SBUIUnlockLabel','SBLockScreenBatteryChargingView'):
    assert cls in s
for text in ('向上滑动解锁','swipe up to unlock','目前电量','current battery level'):
    assert text in s
for excluded in ('日期','农历','通知','充电胶囊'):
    assert excluded in x['footerText']
assert 'LSGCAncestorLockContext' in s and 'LSGCClassInChain' in s
assert 'v.window' in s and 'Exact system strings only' in s
assert 'LSGCRestore' in s and 'source' not in s
assert 'drawRect' not in s and 'CADisplayLink' not in s and 'scheduledTimer' not in s
assert 'UIView *root' not in s and 'subviews' not in s
assert 'LSGCHideSystemPromptsRefresh' in t and 'LSGCHideSystemPromptsInstall' in t
print('OK: default-off exact text/class/ancestor gate, exclusions, reversible lifecycle, no traversal/draw/timer')
