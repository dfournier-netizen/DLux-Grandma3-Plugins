# CreateFixtureGroups 2.9.0

Reads every fixture on a stage and generates groups from the patch and 3D positions.

## Dialogs

1. **Settings**
   - Stage name and start slot.
   - Axis mapping, with an invert per axis.
   - Stage centre: AUTO (midpoint of the rig) or a manual value.
   - Centre band: AUTO (three equal bands on the stage centre) or a manual +/- value.
   - Floor limit, Low limit and LX tolerance.
2. **Group options:** which group sections to build, and which fixture types to include.
3. **Cell sets:** only appears when a fixture has cells with different names. Choose which names get their own groups, e.g. the Rayzor SparkLED separate from its pixels.

Dialogs 1 and 2 and the Cell sets dialog each have **Save as default** and **Reset defaults**. Saved defaults are stored in the show file, so save the show to keep them.

## Groups

- **Odds / Evens:** per fixture type (alternating within each rig position) and per position. The pattern is symmetric outside-in or simple 1, 3, 5.
- **Fixture types:** one group per type.
- **Position zones:** SR / CS / SL, US / Mid Stage / DS and Floor / Low / Flown, mixed and per type.
- **Rig positions:** LX 1..n (upstage first), Boom SL / SR n, and Ground Row, each mixed and per type.
- **Cells:** only the deepest sub-fixtures (no parent sub-fixtures). Each part is its own set, e.g. the JDC1 plate and beam.
  - Groups: all cells, Cell N, odds / evens, and left / middle / right thirds split by grid position.
  - Zone and position versions of the cell groups.
  - Cell groups keep the fixture type's native selection grid. "Cell N" groups are a simple row.
- **Overwrite:** existing groups with the same name are updated in their own slot. New groups start at the start slot and skip occupied slots.

## Notes

- Fixtures whose fixture type has **CanHaveChildren = Yes** are treated as grouping or truss objects and skipped, and so are Environmental objects. Skipped fixtures are logged per type. If a real fixture type is missing, check that flag in the patch.
- Nothing is stored until you confirm. The confirm shows the group count and the slot range.
