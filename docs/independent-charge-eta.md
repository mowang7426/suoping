# Independent charging ETA 2.0.24 candidate

Base: feature/hide-native-date-lunar 7c14dd4 (2.0.21). Original 30pt, single-label bolt capsule retained; date/time/native-hide behavior untouched. No Jikan runtime/source/model/daemon/database/assets or package execution. main remains unchanged.

## Own algorithm

All arithmetic and learner state live in LSGCOwnChargingETACore.h, compiled by both the production ObjC++ sampler and portable C++ regression. Inputs use UIDevice SOC/state captured on main and IOPMPowerSource properties read on the private serial queue. No UIDevice percentage is reinterpreted as capacity.

Each complete observed p->p+1 interval contributes one monotonic-time observation to bucket p. The initial partial interval is discarded. Multi-percent jumps are discarded, not uniformly imputed; the next single boundary starts a fresh interval. Pause, net discharge, unplug, charger signature change, >95sec sample gap, SOC rollback and restart lose the timing anchor. Terminal 99->100 is learned only with a preceding trusted 99 boundary and last observation <=45sec old. Sampling itself introduces approximately one 30sec interval of quantization error; events can reduce but do not remove it.

History keeps at most four non-identifying charger negotiation classes, 100 buckets each, eight observations each. A usable bucket requires >=3 observations from >=3 uninterrupted learning segments, <=30 days old, and every value within [0.5*median,2*median]. It uses the sorted middle value (upper middle for even n). This is an independent median policy, not a claim of numerical replication of Jikan's winsorized mean. Charger class uses only available Watts/Voltage/Current/IsWireless; absent adapter fields mean unknown. Electrically indistinguishable adapters cannot be distinguished. Battery maximum capacity changing >15% clears history. Partial history cannot produce a history-only ETA.

For SOC s, target=100:

    T = sum(p=floor(s)..99) [p+1-max(p,s)] * d[p]

For missing d[p], a visibly coarse physical baseline is allowed only if raw maximum capacity is 500..15000 mAh, raw current capacity is 0..maximum, raw SOC agrees with display within 8 percentage points, current is positive 50..10000 mA (never abs/signed-wrap), >=3 samples span >=50sec, max/min current <=1.35, maximum capacity is stable within 2%, and observed raw capacity rise / integrated current is within 0.35..2.5. These are conservative plausibility gates, not proof that every private field has identical units on every OS. If inconsistent or absent, the baseline stays unavailable. Present invalid/negative InstantAmperage is not replaced with a more flattering Amperage; Amperage is considered only when InstantAmperage is absent.

    baseline seconds/percent = (rawMax-rawCurrent)/(100-s)/meanCurrent * 3600

There is no CV/thermal correction and no Apple official ETA claim. Coarse estimates can be substantially optimistic at high SOC. No guarantee optimization/thermal/charge limit permits reaching 100%. All known buckets are integrated; only missing buckets use the baseline. Example 98.5%, d98=60sec,d99=120sec ->150sec. Capacity 4000mAh-current2000mAh, net2000mA ->3600sec only under constant-current assumption.

## Scheduling, safety, storage

Optional independentChargingETA switch defaults OFF and requires the original chargingETAPill and master switch. Main handles UIDevice captures and copied strings only. Serial worker handles IOKit, computation and binary-plist load/write. One task in flight, one coalesced request, generation-gated main publication; unplug/disable clears text immediately. IOPS and battery notifications trigger updates. Only the enabled charging predictor owns a worker-queue dispatch timer at 30sec with 5sec leeway; unplug/disable cancels it. No main timer/display link/dispatch_sync/global UIView setter. Snapshots older than 95sec are not shown as ETA.

Own cache: Library/Caches/com.minis.lockscreengradientclock/own-charge-history-v1.plist under the injected process home; <=256KiB, max4*100*8 observations, async serial writes with NSDataWritingAtomic, directory0700/file0600, binary schema validation. Only history/session serial/capacity reference, no credentials or device identifiers. No anchor survives process restart. Cache availability/IOKit access on RootHide are not guaranteed by compilation.

## Original single-line texts

- Enabled, no trusted ETA: 正在学习 · XX%
- Observed pause/net discharge: 充电暂停 · XX%
- Trusted complete historical curve: 约XX分钟充满 · XX%
- Current-linear missing-bin fallback: 粗估约XX分钟充满 · XX%
- Full: 已充满 · 100%
- Unplugged: whole capsule hidden

Minutes use ceil(seconds/60), minimum1. Disabled ETA retains original 正在充电 · XX%. Diagnostics expose OwnChargingETA(source,reason,IOKit error,field availability,numeric raw/sanitized capacity/current,generation,coverage,samples,eta,coarse), no raw registry dump/IDs; accessible through existing settings diagnostic button.

## Validation and device limitations

CI compiles/runs portable production-core unit tests and architecture/static regressions before building arm64+arm64e Rootless/RootHide DEBs. Tests cover formulas/units/fractional and high SOC/missing capacity/current direction/unsigned wrapping/first interval/jumps/pauses/gaps/restarts/charger changes/terminal edge/historical reuse/generation gating/disconnect hiding. All pre-existing date/time/settings/prompt safety tests remain in the workflow.

These are code/build/package validations, not iPhone accuracy or fluidity measurements. iPhone14ProMax iOS17 relaxin RootHide hardware is not available to CI: IOKit permission/field units/lock-screen attach/wake behavior need on-device diagnostics. Need held-out full charging sessions to report median/P90 ETA absolute error and availability. No invented accuracy values or cold-start time promise. The implementation deliberately displays learning rather than fabricated minutes when evidence is inadequate.
