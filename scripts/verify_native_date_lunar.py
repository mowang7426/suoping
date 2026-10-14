#!/usr/bin/env python3
import pathlib, plistlib
r=pathlib.Path(__file__).resolve().parents[1]
t=(r/'Tweak.xm').read_text(); p=plistlib.loads((r/'Preferences/Resources/Root.plist').read_bytes())
x=next(v for v in p['items'] if v.get('key')=='hideNativeDateLunar')
assert x['default'] is False and x['label']=='隐藏原生日期和农历'
assert '@"hideNativeDateLunar":@NO' in t
assert 'NativeDateLunarSuppressionEnabled' in t and 'RefreshNativeDateLunarSuppression();' in t
policy=(r/'LSGCNativeDateLunarPolicy.h').read_text()
assert 'LSGCNativeDateLunar::identify(input)' in t
assert 'CSProminentSubtitleDateView' in policy and 'CSProminentTimeView' in policy
assert 'BSUIRelativeDateLabel' in policy and 'label.tag==7001' in t
assert 'label.subviews.count!=0' in t
assert t.count('if (ShouldSuppressNativeDateLunar((UILabel *)obj)) return;')==2
assert 'ObserveNativeDateLunar(label)' in t and 'ObserveNativeDateLunar((UILabel *)obj)' in t
observe=t[t.index('static void ObserveNativeDateLunar(UILabel *label) {'):t.index('static void RefreshNativeDateLunarSuppression(void) {')]
assert 'LSGCNativeDateLunar::transition' in observe and 'label.layer.contents=nil;' in observe
assert observe.count('[label setNeedsDisplay]')==1 and 'alpha=' not in observe and 'hidden=' not in observe
assert 'NativeDateLabels.allObjects' in t and 'DateOverlayLabels.allObjects' in t
assert 'PurgeDisabledDateOverlays();' in t and 'LSGCNativeDateLunar::purgeDateOverlay(!clock' in t
for start,end in [('static void LabelDraw(', 'static void (*OrigLabelLayout)'), ('} else if ([method isEqualToString:@"drawTextInRect:"])', '} else {\n                hook=imp_implementationWithBlock')]:
    body=t[t.index(start):t.index(end,t.index(start))]
    assert 'Schedule(' not in body and 'Apply(' not in body and 'setNeedsDisplay' not in body
assert 'CADisplayLink' not in t and 'scheduledTimer' not in t
assert (r/'tests/native_date_lunar_test.cpp').exists()
print('PASS native date/lunar integration: shared production policies, real iOS17 chain, backing reset, draw purity, full registered overlay purge')
