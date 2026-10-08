#!/usr/bin/env python3
"""Image adapter integration contracts, independent of legacy text fallback."""
from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'Tweak.xm').read_text(); a=(r/'LSGCImageAdapter.inc').read_text()
assert '#include "LSGCImageAdapter.inc"' in s
assert 'if (ImageRole(label)==1 && ImageParent(label))' in s
assert 'if (ImageRole(label)==2 && ImageParent(label))' in s
assert 'ImageDateMask(label) : SnapshotText(label,TextMaskScale(label))' in s
assert 'UIView *geometry=clock ? label : ImageGlyph(label);' in s
assert 'state.mask.contentsGravity=glyph.layer.contentsGravity;' in s
assert 'state.mask.contentsRect=glyph.layer.contentsRect;' in s
assert 'LSGCImageMappedBasis(' in s and 'LSGCImageCacheReusable(' in s
assert a.index('ImageRestore(label);\n    NSMutableArray') < a.index('ImageOrigMask(layer,@selector(setMask:),lease.blank)')
assert 'lease.nativeMask=mask;' in a
assert 'LSGCImageRestoreOwnedMask(' in a
assert 'if (s) {' in a[a.index('static void ImageInvalidate'):]
for field in ['hidden','alpha','image','contents']:
    assert f'view.{field}=' not in a and f'layer.{field}=' not in a
assert 'ImageVisible(image)' in a and 'ImageVisible(host)' in a
assert 'label.hidden' not in a and 'Visible(label)' not in a
assert 'if (sources!=1 || branches!=1) return nil;' in a
assert 'if (clocks!=1) return nil;' in a
assert 'lease.source=label; lease.nativeMask=layer.mask;' in a
assert 'InstallImageHooks();' in s
assert 's.imageLeased.count==nodes.count' in a
print('PASS: real image adapter inclusion, native glyph alpha/crop/coordinates, cache gates, strict tree, latest system mask leases, independent time/date switches and native visibility untouched')
