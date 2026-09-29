# SetNShot 2.1.1

Sets phaser recipe properties on every matching phaser recipe across a range of sequences, cues and recipes.

- **Sequence:** From / To (leave To blank for one sequence), or **Use Selected Sequence**.
- **Cue** and **Recipe:** From / To ranges.
- **Properties:** each can be switched on or off.
  - NShot: Unlimited (sends 0) or a custom number, e.g. 1, 0.75, 4
  - Direction: Forward / Backward / Alternate
  - Measure
  - Width: 0-100
  - Adaptive Measure / Adaptive Width

Sends `Set Sequence <n> Cue <c> Part <p>.<r> [Thru <r2>] Property "<Prop>" <value>` for every matching cue part. NShot only applies to phaser recipes with 2 or more steps.
