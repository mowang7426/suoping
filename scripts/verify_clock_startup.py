#!/usr/bin/env python3
"""Startup/discovery/diagnostic source contracts alongside executable scope tests."""
from pathlib import Path
import plistlib
root=Path(__file__).resolve().parents[1]
s=(root/'Tweak.xm').read_text()
def body(start,end): return s[s.index(start):s.index(end,s.index(start))]
assert plistlib.loads((root/'LockScreenGradientClock.plist').read_bytes())['Filter']['Bundles']==['com.apple.springboard']
make=(root/'Makefile').read_text()
assert 'LockScreenGradientClock_FILES = Tweak.xm' in make
assert 'CoreText' in make and 'LIBRARIES = substrate' in make
identity=body('static BOOL IsStandaloneTimeLabel(UILabel *label) {','static UIView *DateOverlayParent')
assert 'LSGCMainClockChain(names,count)' in identity
assert 'TimeText' not in identity and 'containsString' not in identity
walk=body('static void Walk(UIView *view,NSUInteger depth) {','static void Discover(void) {')
assert 'IsStandaloneTimeLabel(label)' in walk
assert 'IsDateCandidate' not in s
assert 'ClockDateText' not in walk and 'GradientText' not in walk
install=body('static void InstallHooks(void) {','static void (*OrigViewMove)')
assert 'Hooked=LabelHooked && NativeClassesLoaded' in install
assert 'ClockHookKeys containsObject:key' in install
assert 'NSClassFromString(@"_UIAnimatingLabel")' in install
assert 'GlassClass' not in install
label=body('static void InstallLabelHooks(void) {','// Hook overrides')
assert '&& OrigLabelDraw' in label and 'OrigViewMove &&' in label
assert 'if (!OrigLabelDraw)' in label
hooks=body('static void InstallClockHooks(void) {','static void Walk(UIView *view,NSUInteger depth) {')
assert 'Walk((UIView *)obj,0)' in hooks
assert '@"SBFLockScreenDateView"' in hooks
retry=body('static void RetryDateDiscover(void) {','static void WriteDiagnostics')
assert 'DiscoverAndApply();' in retry and 'return;' not in retry
image=body('static void AddedImage','__attribute__((constructor))')
assert 'DiscoverAndApply();' in image and 'ImageRefreshPending' in image
start=s[s.index('__attribute__((constructor))'):]
assert start.index('StartupComplete=YES') < start.index('InstallHooks();') < start.index('_dyld_register_func_for_add_image')
ready=body('static BOOL ClockReplacementReadyForCommit(UILabel *label) {','static void Apply(UILabel *label) {')
assert '!Hooked || !LabelHooked' in ready
diag=body('static void WriteDiagnostics(void) {','static BOOL ColorRGB')
assert 'BOOL time=IsStandaloneTimeLabel(label)' in diag
assert 'active+=(time && ClockReplacementReady(label))' in diag
assert 'BOOL date=!time &&' in diag
assert 'NativeClassesLoaded?' in diag and 'GlassClass?' not in diag
assert '主时间扫描发现' in diag and '实际时间替换' in diag
assert 'Hooked && active' in diag
assert 'CADisplayLink' not in s and 'scheduledTimer' not in s
print('OK: injection/build entry, late class loading, local discovery, truthful hook/scan/render diagnostics, hook-off fallback')
