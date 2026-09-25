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
        entry = plistlib.loads(read(ENTRY))['entry']
        assert entry['bundle'] == 'LockScreenGradientClockPrefs'
        assert entry['detail'] == 'LSGCRootListController'
        assert entry['isController'] is True
        info = plistlib.loads(read(BUNDLE + 'Info.plist'))
        assert info['NSPrincipalClass'] == 'LSGCRootListController'
        assert info['CFBundleExecutable'] == 'LockScreenGradientClockPrefs'
        assert plistlib.loads(read(BUNDLE + 'Root.plist'))['items']
        assert len(read(BUNDLE + info['CFBundleExecutable'])) > 0
    print(f'PASS {path}: preference entry, controller binary and resources present')

if __name__ == '__main__':
    packages = list(Path('build').glob('*.deb')) if len(sys.argv) == 1 else [Path(p) for p in sys.argv[1:]]
    if not packages:
        raise SystemExit('No packages to verify')
    for package in packages:
        verify(package)
