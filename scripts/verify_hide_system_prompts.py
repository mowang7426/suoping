#!/usr/bin/env python3
"""Integration contract complements executable production-policy tests."""
from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
s=(r/'LSGCHideSystemPrompts.xm').read_text(); t=(r/'Tweak.xm').read_text()
p=plistlib.loads((r/'Preferences/Resources/Root.plist').read_bytes())
x=next(x for x in p['items'] if x.get('key')=='hideLockScreenPrompts')
assert x['default'] is False and '@"hideLockScreenPrompts":@NO' in t
assert 'LSGCPrompt::identify(PromptInput(label))' in s and 'policy.update(r,PromptEnabled,PromptHide)' in s
assert 'NSUserDefaults' not in s
assert 'LSGCHideSystemPromptsRefresh([Config[@"enabled"] boolValue],[Config[@"hideLockScreenPrompts"] boolValue])' in t
for forbidden in ['v.alpha=','v.hidden=','setAlpha:', 'setHidden:', 'MSHookMessageEx','dispatch_async','scheduledTimer','CADisplayLink']:
    assert forbidden not in s, forbidden
assert t.count('if (!Rendering && LSGCSystemPromptShouldSuppress((UILabel *)obj)) return;')==2
assert 'if (LSGCSystemPromptRecognized(label)) return nil;' in t
assert 'RemoveOverlay(label); DiagApplyReturn=@"system-prompt-not-date"' in t
assert t.count('LSGCSystemPromptObserve')>=6
assert 'LSGCSystemPromptsReport()' in (r/'LSGCDiagnostics.inc').read_text()
for f in ['LabelDraw','LSGCSystemPromptShouldSuppress']:
    src=t if f=='LabelDraw' else s
    section=src.split(f+'(',1)[1].split('\n}',1)[0]
    assert 'Schedule(' not in section and 'Observe(' not in section and 'setNeedsDisplay' not in section
print('PASS prompt integration: explicit config domain, reused label hooks, rendering bypass, date exclusion, no visibility writes/private hooks/timer, on-demand diagnostics')
