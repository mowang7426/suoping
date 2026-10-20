#!/usr/bin/env python3
from pathlib import Path
r=Path(__file__).parents[1]
s=(r/'LSGCJikanETAAdapter.m').read_text()
for token in ('moe.waru.jikan.estimate-status','CFPreferencesCopyValue','CoreML','JikanPowerd','SQLite','dispatch_sync','NSTimer','CADisplayLink','dlopen','startMonitoring','_refreshBatteryInfo','system("','popen('):
    assert token not in s, token
for token in ('NSClassFromString(@"TT100")','respondsToSelector','methodSignatureForSelector','methodReturnType','getArgumentTypeAtIndex','objc_msgSend','NSThread.isMainThread','@try','@catch','remainingSeconds','targetPercent','hasEstimate','estimateStatus','available','LSGCJikanFresh','auto'):
    assert token in s, token
p=(r/'LSGCChargingETAPill.xm').read_text()
assert '@"TT100BatteryInfoUpdated"' in p and 'LSGCJikanETAProducerPublished' in p
assert p.index('LSGCJikanETARefresh(d.batteryState') > p.index('dispatch_async(dispatch_get_main_queue()')
assert 'LSGCCapsuleLayout(gap,MIN(fr.size.height,cr.size.height))' in p
assert 'CGRectIntersectsRect(r,fr)||CGRectIntersectsRect(r,cr)' in p
assert 'LSGCCapsulePresentation' in p
ui=(r/'LSGCChargingCapsule.inc').read_text()
assert 'percent/100.0' in ui and 'LSGCCapsuleNeedsRender' in ui
assert '25 weight:UIFontWeightSemibold' in ui and '12 weight:UIFontWeightMedium' in ui
assert 'LSGCJikanETAReport()' in (r/'LSGCDiagnostics.inc').read_text()
print('PASS runtime-only bridge structural contract; behavioral tests compile the actual production adapter and shared policies')
