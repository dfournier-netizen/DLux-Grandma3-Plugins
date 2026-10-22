# SeqTools

grandMA3 plugin (target 2.5.1) for working on many sequences at once. Formerly SeqEdit; Copy & Regroup folded in.

One window for the whole session; panels swap in place and it stays open between rounds until you close it. The selection is kept between runs. Switch modes at the top.

## Find Sequences (both modes)
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

## Install
Import `SeqTools_Embedded_<timestamp>.xml` into an empty Plugins pool slot (single XML, Lua embedded).

## Status
1.2.1 -- naming fixes after the first Copy & Regroup tests (no rename unless a naming option applies or a name is typed; empty fields count as empty). Copy, regroup and cook confirmed on 2.5.1 (1.2.0 run, 9 copies). Settings mode confirmed on 2.5.1 (SeqEdit 1.0.1/1.1.0). Regroup/copy/cook commands confirmed with RecipeDiag 0.1.
