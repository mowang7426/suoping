#!/usr/bin/env python3
"""Source contracts for bounded diagnostics; not evidence of device rendering."""
from pathlib import Path
import hashlib
root=Path(__file__).resolve().parents[1]
s=(root/'Tweak.xm').read_text()
d=(root/'LSGCDiagnostics.inc').read_text()
a=s.index('static BOOL ClockReplacementReady(UILabel *label) {')
b=s.index('static void Apply(UILabel *label) {',a)
assert 'ClockHostVisible(label,s)' in s[a:b], 'diagnostics reflect verified host safety gate'
assert '#include "LSGCDiagnostics.inc"' in s
assert 'report=[report stringByAppendingString:DiagReport()]' in s
for counter in ('DiagInstall','DiagLayout','DiagMove','DiagDraw','DiagMainDraw','DiagNative','DiagSuppress','DiagSchedule','DiagApply'):
    assert 'DiagInc(&'+counter+')' in s, counter
assert s.count('BOOL main=!Rendering && DiagDrawDepth==0 && IsStandaloneTimeLabel((UILabel *)obj);')==2
assert s.count('@finally { --DiagDrawDepth; }')==2
assert 'if (clock) DiagCaptureMask(image,label.bounds.size,scale)' in s
for reason in ('hook-not-ready','no-superview','mask-no-ink','readiness-rejected','invalid-bounds','empty-text','exception:'):
    assert reason in s, reason
failure=s[s.index('if (!ClockReplacementReady(label)) {'):s.index('[label setNeedsDisplay];',s.index('if (!ClockReplacementReady(label)) {'))]
assert failure.index('DiagCaptureFailure(label,DiagApplyReturn)') < min(i for i in (failure.find('RemoveOverlay(label)'), failure.find('RemoveOverlayQuiet(label)')) if i >= 0)
assert 'setNeedsDisplay' not in failure
for key in ('identity','hookReady','committed','enabled','fontReady','maskHasInk','attached','visible','onScreen','signatureCurrent','opacity','failedReasons','capturedBeforeRemoval','methodOwner','originalIMPExists','currentIMPExists','currentMatchesExpectedHook','maskPixelBoundingBox','HasAlpha','requestedScale','strictScopeRequested','rejectedReason','windowRect','overlayIntersection','font/clock config','hostSelection','hostFailureReason','hostClass','hostWindowRect'):
    assert key in d, key
assert 'tree.count<' not in d and 'candidates<' not in d, 'candidate report must not silently truncate'
assert 'for (UIView *v=view; v; v=v.superview)' in d, 'full ancestry required'
assert 'never main-clock success' in d
assert 'w*h<=8388608' in d
assert '__atomic_compare_exchange_n' in s and 'old!=~0ULL' in s
for forbidden in ('CADisplayLink','scheduledTimer','dispatch_source_create','setNeedsDisplay','RemoveOverlay(','addSublayer:','label.alpha=','label.hidden='):
    assert forbidden not in d, 'diagnostics may not mutate rendering: '+forbidden
print('OK: verified host safety gate, bounded counters/snapshots, pre-removal failures, complete candidate ancestry, real IMP coverage, main-only draw/mask, no polling or render mutations')
