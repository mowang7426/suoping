#!/usr/bin/env python3
"""Executable source/setting contracts; not UIKit or device screenshot proof."""
from pathlib import Path
import plistlib
root=Path(__file__).resolve().parents[1]
s=(root/'Tweak.xm').read_text()
def body(a,b):
    start=s.index(a)
    return s[start:s.index(b,start)]
glyph=body('static UIImage *SnapshotClockGlyphs(', 'static UIImage *SnapshotText(')
for marker in ['CTLineCreateWithAttributedString','CTRunGetPositions','CTFontCreatePathForGlyph',
               'CGPathGetPathBoundingBox','LSGCFullClockCanvas','CGPathCreateCopyByTransformingPath',
               'kCGPathFillStroke','2*weight','2*(weight+edge)','8388608','clockCanvasSize=size']:
    assert marker in glyph, marker
assert 'renderInContext' not in glyph, 'main clock must not use clipped UILabel backing store'
assert 'if (clock) return SnapshotClockGlyphs(label,mirror.attributedText,scale);' in s
style=body('static void ApplyStyle(', 'static void InstallMask(')
assert 'LSGCClockFillOpacity' in style and 'if (standaloneTime) c=[c colorWithAlphaComponent:1]' in style
assert 'Config[@"edgeEnabled"]' not in style and 'Config[@"edgeCore"]' not in style
clock=style[style.index('if (standaloneTime) {'):]
for marker in ['ClearEdges(s)','clockEdgeEnabled','clockEdgeStrength','clockEdgeColor',
               'host.masksToBounds=NO','s.gradient.masksToBounds=NO','insertSublayer:s.clockRim below:s.gradient']:
    assert marker in clock, marker
assert 'edgeCore' not in clock and 'edgeWidth' not in clock
mask=body('static void InstallMask(', 'static void RemoveOverlay(')
assert 'IsStandaloneTimeLabel(label) ? s.clockCanvasSize : label.bounds.size' in mask
apply=body('static void Apply(UILabel *label) {','static void InstallHooks(void) {')
assert 'clock ? state.clockCanvasSize : label.bounds.size' in apply
assert 'available/visible.size.width' in apply
assert 'ClearEdges(state); // Also purge legacy edges' in apply
assert 'BuildEdgeImages' not in s and 'InstallEdgeContents' not in s
ready=body('static BOOL ClockReplacementReady(UILabel *label) {','static void Apply(UILabel *label) {')
assert 'outlineReady' in ready and 's.clockRim.superlayer==s.dateHost' in ready
remove=body('static void RemoveOverlay(', '// Render at the final clock magnification')
assert '[s.clockRim removeFromSuperlayer]' in remove and 's.clockCommitted=NO' in remove
signature=body('static NSString *DateSignature(', '// Suppress only the glyph draw')
assert signature.index('if (!IsStandaloneTimeLabel(label)) return')<signature.index('Config[@"clockWeight"]')
assert 'CADisplayLink' not in s and 'scheduledTimer' not in s
prefs=plistlib.loads((root/'Preferences/Resources/Root.plist').read_bytes())['items']
settings={p['key']:p for p in prefs if 'key' in p}
for k in ['clockWeight','clockEdgeEnabled','clockEdgeWidth','clockEdgeStrength','clockEdgeColor']:
    assert k in settings and f'values[@"{k}"]' in s
assert settings['clockOpacity']['default']==1 and settings['clockOpacity']['max']==1
assert settings['clockEdgeWidth']['default']>0
print('OK: full CoreText canvas, padded fill/stroke, independent main-clock outline, solid alpha, isolated date edges, readiness fallback, cached/event-driven geometry')
