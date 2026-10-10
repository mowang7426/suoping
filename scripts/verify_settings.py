#!/usr/bin/env python3
"""Static regression checks for clock settings and date isolation."""
import plistlib, re, pathlib, sys
root=pathlib.Path(__file__).resolve().parents[1]
plist=plistlib.loads((root/'Preferences/Resources/Root.plist').read_bytes())
items=plist['items']
bykey={x.get('key'): x for x in items if x.get('key')}
required={
 'clockScale':(.8,3.5), 'clockWidth':(.8,1.5), 'clockSpacing':(-10,20),
 'clockColonScale':(.5,1.5), 'clockOffsetY':(-200,200), 'clockOffsetX':(-100,100),
 'clockHeight':(.5,4.0),
}
for key,(lo,hi) in required.items():
    assert key in bykey, f'missing setting {key}'
    spec=bykey[key]
    assert spec.get('cell') == 'PSSliderCell', f'{key} is not a slider'
    assert spec.get('label'), f'{key} missing visible label'
    assert float(spec['min']) == lo and float(spec['max']) == hi, f'{key} range changed'
source=(root/'Tweak.xm').read_text()
assert 'clockHeight' in source and 'Clamp([Config[@"clockHeight"] doubleValue],0.50,4.00)' in source
# Height and offsets must only participate in the time-label transform, never date labels.
assert 'IsStandaloneTimeLabel(label) ? Clamp([Config[@"clockOffsetY"]' in source
assert 'CGFloat sy=frame.size.height/label.bounds.size.height*userScale*heightScale' in source
assert 'clockHeight' not in source[source.index('static NSString *DateSignature'):source.index('static void Apply')]
assert 'LSGCLabeledSliderCell.class' in (root/'Preferences/LSGCRootListController.m').read_text()
assert (root/'control').read_text().split('Version: ',1)[1].splitlines()[0] == '2.0.15'
assert '#define LSGCVersionString @"2.0.15-charging-eta-pill-ios17-compat"' in (root/'LSGCVersion.h').read_text()
# Event-driven clock geometry and process-local imported fonts.
font=(root/'LSGCFont.h').read_text()
prefs=(root/'Preferences/LSGCRootListController.m').read_text()
assert 'kCTFontManagerScopeProcess' in font and 'kCTFontManagerScopeUser' not in source+prefs
assert 'CTFontManagerCreateFontDescriptorsFromURL' in font
assert 'fontPath' in prefs and 'NSUUID.UUID.UUIDString' in prefs
assert 'RegisterUserFont();' in source[source.index('static void LoadConfig'):source.index('static UIColor *Color')]
assert 'CSProminentDisplayView' in source and '_UIAnimatingLabel' in source
assert 'class_getInstanceMethod(cls,sel)' in source and 'MSHookMessageEx(cls,sel,hook,&original)' in source
assert 'if (IsStandaloneTimeLabel(label)) return nil;' in source
assert 'CATransform3DScale(label.layer.transform' not in source
assert 'state.dateHost.transform=CATransform3DMakeAffineTransform' in source
assert 'UIView *dateParent=clock ? ClockOverlayParent(label,&hostReason) : DateOverlayParent(label)' in source
assert 'mirror.contentScaleFactor=MAX(1,scale)' in source
assert '4096.0*2048.0' in source and 'TextMaskScale(label)' in source
assert 'CADisplayLink' not in source and 'scheduledTimer' not in source
print(f'OK: {len(required)} labeled clock sliders, isolated date geometry, local font registration, event-driven sharp clock')
