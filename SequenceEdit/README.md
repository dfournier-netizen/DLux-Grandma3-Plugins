# SeqEdit

grandMA3 plugin (target 2.5.1) for changing sequence settings on many sequences at once.

- One window for the whole session; it stays open between rounds until you close it.
- Find Sequences: name contains, number range, assigned to executors (any page or one page). Pick results, then Add or Replace the selection.
- Every setting from the Sequence Settings pop-up (Label, Start, Playback, Speed, Protect, MIB) shows the shared current value or "Mixed". Tap to set a new value; only settings you change are written. Name, Scribble, Appearance and Note are not bulk-edited.
- Masters (Rate, Speed, Playback) by name, scales Div256..Mul256, Input/Output Filter (World or Filter), Tags add/remove.
- Apply shows a preview (what changes on how many sequences), then writes, reads every value back and reports failures in the System Monitor.
- Locked sequences are skipped, unless the round sets Lock Sequence = No (they are unlocked first).

## Install
Import `SeqEdit_Embedded_<timestamp>.xml` into an empty Plugins pool slot (single XML, Lua embedded).

## Status
1.0.1 -- awaiting first console run on 2.5.1. Write methods were confirmed with SeqSettingsDiag / SeqTagDiag on 2.5.1.1.
