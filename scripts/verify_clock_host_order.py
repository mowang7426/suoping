#!/usr/bin/env python3
"""Regression contracts for actual UIKit entry order (not device-render proof)."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
s=(root/'Tweak.xm').read_text()
def body(start,end):
    a=s.index(start)
    return s[a:s.index(end,a)]
select=body('static UIView *ClockSelectOverlayParent(', 'static UIView *ClockOverlayParent(')
host=body('static UIView *ClockOverlayParent(', 'static BOOL ClockHostVisible(')
apply=body('static void Apply(UILabel *label) {', 'static void InstallHooks(void) {')
assert select.index('IsStandaloneTimeLabel(label)') < select.index('LSGCAllowSourceWrapper(') < select.index('UIView *host=')
assert 'wrapper.class==UIView.class' in select and 'wrapper.hidden, wrapper.alpha' in select
assert 'UIView *host=wrapper.superview;' in select
assert 'ClockSourceWrapper(label)' in select and 'return label' not in select
wrapper=body('static UIView *ClockSourceWrapper(', 'static UIView *ClockSelectOverlayParent(')
assert 'LSGCClockWrapperIndex(names,count)' in wrapper and 'views[index]' in wrapper
assert 'sibling-wrapper-alpha-not-zero' in select
assert 'native-label-host' not in select
assert 'alpha-zero-wrapper-sibling' in select
for gate in ('Visible(', 'v.alpha', 'v.layer.opacity', 'label.window'):
    assert gate not in select, 'selection must not run generic visibility: '+gate
selection=host.index('UIView *host=ClockSelectOverlayParent(label,reason)')
source=host.index('for (UIView *v=label; v && v!=host;')
visible=host.index('for (UIView *v=host; v; v=v.superview)')
assert selection < source < visible
assert 'Visible(label)' not in host.replace('// Never run Visible(label) or a label->window alpha gate before selection.','')
assert 'for (UIView *v=label; v; v=v.superview)' not in host
assert '!(bypass && v==wrapper)' in host
assert 'host.window!=label.window' in host
assert 'v.clipsToBounds || v.layer.masksToBounds' in host
assert 'effectiveOpacity<0.01' in host
assert apply.index('ClockOverlayParent(label,&hostReason)') < apply.index('!Visible(dateParent)') < apply.index('SnapshotText(label,TextMaskScale(label))')
assert apply.index('SnapshotText(label,TextMaskScale(label))') < apply.index('addSublayer:state.dateHost') < apply.index('ApplyStyle(label,state,state.dateHost') < apply.index('state.clockCommitted=YES') < apply.index('if (!ClockReplacementReady(label))')
assert 'label.alpha=' not in s and 'label.hidden=' not in s
assert 'if (IsStandaloneTimeLabel(label)) return nil;' in s
schedule=body('static void Schedule(UILabel *label) {','static CALayer *MaskOwner(')
assert 'Visible(' not in schedule and 'alpha<' not in schedule
ready=body('static BOOL ClockReplacementReady(UILabel *label) {','static BOOL DateReplacementReady(UILabel *label) {')
assert 'Visible(label)' not in ready and 'ClockHostVisible(label,s)' in ready
print('OK: strict identity -> sibling selection -> source-only checks -> true host visibility/clip -> snapshot -> mount/style -> readiness -> glyph suppression; no generic main-clock pre-gate')
