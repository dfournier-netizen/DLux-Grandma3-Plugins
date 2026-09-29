# MATrick Builder 2.1.1

One **Build All** run creates the MATrick sequences, tags and layouts for 9 MATricks: Color, Dim, Focus, Pos and Beam Phaser, Sweeps, Default, Walk In, Bumps.

- **Sequences:** one per value, from sequence 5001 up, named `{prefix} {label} {value}`. Cue 1 calls the matching macro. Each parameter group gets one group tag, so firing a value releases its siblings.
- **Layouts:** two per family (Phase, Fade, Delay, Speed, Wings, Blocks, Groups, Width): `MATrick {Family} - Params` and `MATrick {Family} - Effects`.
- A progress bar runs during the build, and there's a confirm before it starts.

## Requirements

- The MATrick macros already exist in the Macro pool, using "p" for decimals and singular Block/Group naming: XBlock, YBlock, XGroup, YGroup.
- The CH10 icon set is in the Appearance pool: DK 1001-1053, LT 1054-1106.
