# Layout Builder 1.7.3

Places pool objects onto a layout as a grid.

- **Objects:** Sequence, Group, Macro, Executor, Fixture or SubFixture.
- **Select by:** index range (`5001 Thru 5100`), tag name, or wildcard (`Col Ph*`).
- **Layout:** a new layout (next free slot) or an existing one.
- **Elements:** size preset (Small / Medium / Large / Wide / Tall / Custom), up to 10 columns, grid origin, and a default action (Go / Toggle / Flash / Select).
- **Fill order:** Across (rows) or Down (columns).
- **Start corner:** Top-left, Bottom-left (fills upward), Top-right (right to left) or Bottom-right.

The last settings are saved in the show. A progress bar runs during the build.

## Existing layouts

- An info panel shows the layout's element count, X/Y bounds, element size and column/row spacing.
- **Placement:** Free (your own size and origin), Match: new rows below, or Match: new columns right. Match copies the existing element size and spacing and lines up with the existing grid.
- **Auto origin:** Start X/Y is pre-filled with the free space below the existing content.
- **Collision check:** the new grid is checked against the existing elements. A summary pops up before the build; on overlap it offers Move below / Move right / Build anyway / Cancel.
- Objects already on the layout are moved into the new grid, and the summary notes it.
