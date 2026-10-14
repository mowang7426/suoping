#!/usr/bin/env python3
import pathlib, plistlib
r=pathlib.Path(__file__).resolve().parents[1]
t=(r/'Tweak.xm').read_text(); p=plistlib.loads((r/'Preferences/Resources/Root.plist').read_bytes())
x=next(v for v in p['items'] if v.get('key')=='hideNativeDateLunar')
assert x['default'] is False and x['label']=='隐藏原生日期和农历'
assert '@"hideNativeDateLunar":@NO' in t
assert 'NativeDateLunarSuppressionEnabled' in t and 'RefreshNativeDateLunarSuppression();' in t
assert 'SBFLockScreenDateView' in t and 'SBFLockScreenDateSubtitleDateView' in t
assert 'SBFLockScreenAlternateDateLabel' in t and 'SBUILegibilityLabel' in t
assert 'BSUIRelativeDateLabel' in t and 'label.tag==7001' in t
assert 'label.subviews.count!=0' in t and 'label.alpha=0' not in t[t.index('IsNativeDateLunarLeaf'):t.index('static void ObserveNativeDateLunar')]
assert t.count('if (!Rendering && NativeDateLunarSuppressionEnabled() && IsNativeDateLunarLeaf(')==2
assert 'ObserveNativeDateLunar(label)' in t and 'ObserveNativeDateLunar((UILabel *)obj)' in t
assert 'CADisplayLink' not in t and 'scheduledTimer' not in t
assert (r/'tests/native_date_lunar_test.cpp').exists()
print('PASS native date/lunar: default-off strict leaf scope, exclusions, reversible draw gate, event dedupe')
