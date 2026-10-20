#!/usr/bin/env python3
"""Own predictor architecture contracts; not an iOS hardware accuracy test."""
from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
s=(r/'LSGCOwnChargingETA.mm').read_text()
p=(r/'LSGCChargingETAPill.xm').read_text()
t=(r/'Tweak.xm').read_text()
for forbidden in ('dispatch_sync','NSTimer','CADisplayLink','abs(x.current)','tt100.db','CoreML','valueForKey:'):
    assert forbidden not in s, forbidden
assert 'IOServiceMatching("IOPMPowerSource")' in s
assert 'dispatch_async(Work' in s and 'IOPSNotificationCreateRunLoopSource' in s
assert '30*NSEC_PER_SEC,5*NSEC_PER_SEC' in s
assert 'dispatch_source_cancel(Timer)' in s
assert 'OwnETA::acceptGeneration' in s and 'if (Busy)' in s and 'RequestQueued' in s
assert 'NSPropertyListBinaryFormat_v1_0' in s and 'NSDataWritingAtomic' in s
assert '256*1024' in s and '[classes count]>4' in s and '[values count]>8' in s
assert 'AppleRawMaxCapacity' in s and 'AppleRawCurrentCapacity' in s
assert 'own-charge-history-v1.plist' in s and 'OwnChargingETA(source=' in s
assert 'IsCharging' in s and 'ExternalConnected' in s
assert 'IORegistry' not in p and 'dispatch_source' not in p and 'CAShapeLayer' not in p
assert 'height=30' in p and 'bolt.fill' in p and 'LSGCOwnETAText()' in p
assert 'LSGCOwnETAConfigure(NO)' in p
assert 'LSGCOwnETADiagnostic()' in t
items=plistlib.loads((r/'Preferences/Resources/Root.plist').read_bytes())['items']
settings={i['key']:i for i in items if 'key' in i}
assert settings['independentChargingETA']['default'] is False
assert settings['chargingETAPill']['default'] is False
make=(r/'Makefile').read_text()
assert 'LSGCOwnChargingETA.mm' in make and 'IOKit' in make
assert 'Jikan' not in make and 'Jikan' not in p
print('PASS: OwnETA background-only IOKit/cache, event coalescing, bounded persistence, timer cancellation, generation gate, original single-line capsule, independent default-OFF switch')
