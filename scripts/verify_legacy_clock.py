#!/usr/bin/env python3
"""Source contracts supplement portable tests; neither claims device acceptance."""
from pathlib import Path
r=Path(__file__).resolve().parents[1]; s=(r/'Tweak.xm').read_text()
def body(a,b):
    start=s.index(a); return s[start:s.index(b,start)]
identity=body('static BOOL IsStandaloneTimeLabel(UILabel *label) {','// Image-backed legibility')
assert 'LSGCMainClockChain(names,count)' in identity and 'LSGCLegacyClockKind(names,count)' in identity
assert 'TimeText' not in identity and 'font' not in identity
legacy=body('static UIView *LegacyClockParent','// Select before visibility')
assert legacy.index('HasLegibilityImageBranch(source,0)') < legacy.index('LSGCCanRenderLegacy(ready)')
for marker in ['legacy-image-backed-native-fallback','ReadObject(host,@"timeLabel")','TextDrawCovered(label)','sources==1','allowed.invertedSet','owner=NO']:
    assert marker in legacy, marker
assert 'alpha' not in legacy and 'hidden' not in legacy
assert 'label.alpha=' not in s and 'label.hidden=' not in s
assert 'layer.contents=' not in legacy
install=body('static void InstallHooks(void) {','static void (*OrigViewMove)')
assert 'ProminentHooked=LabelHooked && NativeClassesLoaded' in install
assert 'LegacyHooked=LabelHooked && LegacyClassesLoaded' in install
assert 'Hooked=ProminentHooked || LegacyHooked' in install
for hook in [body('static void LabelDraw','static void (*OrigLabelLayout)'),body('static void InstallClockHooks(void) {','static void Walk(UIView *view,NSUInteger depth) {')]:
    assert 'DateReplacementReady((UILabel *)obj)' in hook
    assert 'RemoveOverlay((UILabel *)obj)' in hook
    assert hook.index('RemoveOverlay((UILabel *)obj)') < hook.index('if (main) DiagInc(&DiagNative)')
apply=body('static void Apply(UILabel *label) {','static void InstallHooks(void) {')
assert 'state.dateCommitted=YES' in apply and 'if (!DateReplacementReady(label))' in apply
assert 'TimeText(displayText) ||' not in apply
assert 'HasLegibilityImageBranch(label,0)' in body('static UIView *DateOverlayParent','static void Schedule')
assert 'state.clockCommitted || state.dateCommitted' in s
assert '设置页采样不可见不是锁屏像素证据' in s
assert 'CADisplayLink' not in s and 'scheduledTimer' not in s
print('OK: family-local installation, exact legacy candidate/verified owner, image-native fallback, no native alpha/hidden/contents writes, stale overlays removed before native glyph pass-through, date-only commit and bounded event caching')
