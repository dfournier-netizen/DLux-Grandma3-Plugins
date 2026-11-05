# SeqTools

grandMA3 plugin (target 2.5.1) for working on many sequences at once. Formerly SeqEdit; Copy & Regroup and Cues & Recipes folded in.

One window for the whole session; panels swap in place and it stays open between rounds until you close it. The selection is kept between runs. Switch modes at the top.

## Find Sequences (all modes)
Name contains, number range, assigned to executors (any page or one page). Pick results, then Add or Replace the selection.

## Settings mode
- Every setting from the Sequence Settings pop-up (Label, Start, Playback, Speed, Protect, MIB) shows the shared current value or "Mixed". Tap to set a new value; only settings you change are written. Name, Scribble, Appearance and Note are not bulk-edited.
- Masters (Rate, Speed, Playback) by name, scales Div256..Mul256, Input/Output Filter (World or Filter), Tags add/remove.
- Apply shows a preview, then writes, reads every value back and reports failures in the System Monitor.
- Locked sequences are skipped, unless the round sets Lock Sequence = No (they are unlocked first).

## Copy & Regroup mode
- **Copy** on: copies go to the next empty slots from "Destination from" (never overwrite). Names: prefix/suffix, find/replace, and swapping the old group name for the new one; every name can be edited in the preview. With no naming option and no typed name the copy is not renamed (MA names it "<source>#2"). A name that already exists gets "#2" from MA (flagged in the preview). Copy off: the selected sequences are regrouped in place (locked ones skipped).
- **Rules** old group -> new group (up to 8), each with its own scope: whole sequence, picked cues or picked lines, picked per sequence in its cue/line tree. Rules match the original group; the first matching rule wins.
- Each changed sequence is cooked: `Cook Sequence N /MergeLowPriority | /Merge | /Overwrite | /Remove` (pick the mode; Overwrite by default).
- Preview shows every copy/sequence and how many lines change before Apply.

## Cues & Recipes mode (1.3.0)
- Bulk-edit cue, cue part, recipe line, phaser step and OffCue values in the selected sequences.
- **Scope:** cue range (`1 thru 5 + 7.5`, blank = all cues); Parts = all parts / part 0 only / picked parts; tree picks per sequence (cues replace the range, parts for "Picked parts", lines narrow recipe edits, steps for step edits); recipe line type (all / standard / phaser) and group / values filters. Tap **Update scope** after typing a range.
- **Sections:** Cues (name, trig type/time/sound, release, assert, allow duplicates, break, MIB preference, note, lock), Cue parts (name, appearance, tags, note, in/out fade and delay, snap delay, transition, individual timing, preset-type fade/delay, sync, morph, delay to phase, speed master/scale, command, command enabled/delay, tracking distance, MIB mode/multistep/fade/delay/target, lock), Recipe lines (name, enabled, tags, selection, selection mode, values with appearance colours, filter, MAtricks), MAtricks individuals (per axis, plus a **Clear all individuals** button that sets every X/Y/Z individual to None / No and Phaser Transform to None), Phaser lines (shape, speed, measure, NShot, NShot stay, direction, adaptive measure/width/XY rotation), Phaser steps (curve, trans, width, accel, decel, absolute/relative value), OffCue (trig type/time, assert, break, note, part timing, transition, command).
- **Entry:** every value shows the shared current value or "Mixed". Times/numbers: `2.5` sets, `+1` / `-0.5` add, `x1.5` scales, `=-2` sets a negative value, or a literal such as `CueTiming` / `None`. Text: empty = unchanged, `""` = empty. The **Axis** switch (X/Y/Z) picks which axis the MAtricks / phaser speed / step rows edit.
- **Apply:** preview with counts; locked sequences / cues / parts ask "Unlock + Apply" (locked again afterwards) or "Skip locked"; every write is read back; MIB values are skipped where MIB isn't possible; sequences whose recipe lines or steps changed are cooked with the Copy & Regroup cook mode.

## Install
Import `SeqTools_Embedded_<timestamp>.xml` into an empty Plugins pool slot (single XML, Lua embedded).

## Status
1.3.1 -- Clear all individuals button. 1.3.0 -- Cues & Recipes mode (property names, enums and write paths from CueDiag 0.1/0.2 on 2.5.1.0); awaiting console run. 1.2.1 -- naming fixes after the first Copy & Regroup tests. Copy, regroup and cook confirmed on 2.5.1 (1.2.0 run, 9 copies). Settings mode confirmed on 2.5.1 (SeqEdit 1.0.1/1.1.0).
