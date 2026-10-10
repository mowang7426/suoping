#!/usr/bin/env python3
from pathlib import Path
s=Path('LSGCChargingETAPill.xm').read_text()
required=['batteryMonitoringEnabled=YES','UIDeviceBatteryLevelDidChangeNotification','UIDeviceBatteryStateDidChangeNotification','removeObserver:','LSGCBatteryPercent','正在充电 · %ld%%','已充满 · 100%']
for x in required: assert x in s, x
for x in ['Timer','CADisplayLink','estimatedTime','chargingTime','valueForKey','batteryTimeRemaining']:
    assert x not in s, x
assert 'd.batteryState' in s and 'd.batteryLevel' in s
assert 'LSGCLastText' in s
print('battery static contract: PASS')
