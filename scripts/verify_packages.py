#!/usr/bin/env python3
"""Reject packages missing the settings entry, resources or executable."""
import io
import plistlib
from pathlib import Path
import subprocess
import sys
import tarfile

BUNDLE = 'Library/PreferenceBundles/LockScreenGradientClockPrefs.bundle/'
ENTRY = 'Library/PreferenceLoader/Preferences/LockScreenGradientClockPrefs.plist'

def verify(path):
    data = subprocess.check_output(['dpkg-deb', '--fsys-tarfile', str(path)])
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:') as archive:
        files = [m for m in archive.getmembers() if m.isfile()]
        def read(suffix):
            matches = [m for m in files if m.name.endswith('/' + suffix) or m.name == suffix]
            if len(matches) != 1:
                raise ValueError(f'{path}: expected one {suffix}; found {len(matches)}')
            return archive.extractfile(matches[0]).read()
        injection='Library/MobileSubstrate/DynamicLibraries/LockScreenGradientClock'
        assert plistlib.loads(read(injection+'.plist'))['Filter']['Bundles']==['com.apple.springboard']
        dylib=read(injection+'.dylib')
        assert len(dylib)>4096
        for marker in [b'_UIAnimatingLabel', b'CSProminentTimeView', b'SBFLockScreenDateView', b'[LSGC] constructor initialized', b'alpha-zero-wrapper-sibling', b'2.0.15-charging-eta-pill-ios17-compat', b'LSGC.ClockOutline', b'clockEdgeWidth', b'clockWeight', b'sibling-wrapper-alpha-not-zero', b'unsupported-host-layer-mask:']:
            assert marker in dylib, f'missing standalone entry/clock marker: {marker!r}'
        entry = plistlib.loads(read(ENTRY))['entry']
        assert entry['bundle'] == 'LockScreenGradientClockPrefs'
        assert entry['detail'] == 'LSGCRootListController'
        assert entry['isController'] is True
        info = plistlib.loads(read(BUNDLE + 'Info.plist'))
        assert info['NSPrincipalClass'] == 'LSGCRootListController'
        assert info['CFBundleExecutable'] == 'LockScreenGradientClockPrefs'
        settings={x['key']:x for x in plistlib.loads(read(BUNDLE + 'Root.plist'))['items'] if 'key' in x}
        for key in ['clockMode','clockColor','clockColor1','clockColor2','clockColor3','clockColor4']:
            assert key not in settings, f'obsolete clock palette shipped: {key}'
            assert key.encode()+b'\x00' not in dylib, f'obsolete runtime palette shipped: {key}'
        assert b'LSGC.OptionalColorEdges' not in dylib, 'obsolete date edge layer shipped'
        root=plistlib.loads(read(BUNDLE + 'Root.plist'))
        for key in ['edgeEnabled','edgePalette','edgeCore','edgeStrength','edgeWidth','edgeHighlight','edgeReveal','independentEdges','edgeColor1','edgeColor2','edgeColor3']:
            assert key not in settings, f'obsolete date edge setting shipped: {key}'
        assert all(item.get('action')!='resetEdges' for item in root['items'])
        assert '彩边' not in str(root), 'obsolete date edge explanation shipped'
        for key in ['color1','color2','color3','color4','color5','clockOpacity','clockWeight','clockEdgeColor','clockEdgeEnabled','clockEdgeWidth','clockEdgeStrength']:
            assert key in settings, f'missing shared palette/independent ink setting: {key}'
        assert subprocess.check_output(['dpkg-deb','-f',str(path),'Version'],text=True).strip()=='2.0.14'
        assert len(read(BUNDLE + info['CFBundleExecutable'])) > 0
    print(f'PASS {path}: preference entry, controller binary and resources present')

if __name__ == '__main__':
    packages = list(Path('build').glob('*.deb')) if len(sys.argv) == 1 else [Path(p) for p in sys.argv[1:]]
    if not packages:
        raise SystemExit('No packages to verify')
    for package in packages:
        verify(package)
