# DLux grandMA3 Plugins

Lua plugins for grandMA3. Tested on grandMA3 onPC 2.4.2.

| Plugin | Version | What it does |
|---|---|---|
| [MAgic Preset Builder](MAgicPresetBuilder/) | 2.1.0 | Builds a MAgic (multi-step) preset from existing presets, with a visual preset picker |
| [SetNShot](SetNShot/) | 2.1.1 | Sets NShot, direction, measure and width on phaser recipes across ranges of sequences, cues and recipes |
| [MATrick Builder](MATrickBuilder/) | 2.1.1 | Builds the MATrick sequences, tags and layouts in one run |
| [Layout Builder](LayoutBuilder/) | 1.6.0 | Places pool objects on a layout grid with a default action |
| [CreateFixtureGroups](CreateFixtureGroups/) | 2.9.0 | Generates groups from the patch: odds/evens, fixture types, position zones, LX / booms / ground rows, and cell groups in the fixture's native grid |

## Install

Each plugin folder holds one `.xml` and one `.lua`. Keep them together.

1. Copy the plugin folders into the MA3 plugin library:
   - **onPC (Windows):** `C:\ProgramData\MALightingTechnology\gma3_library\datapools\plugins\`
   - **Console:** the same `gma3_library/datapools/plugins` folder, e.g. from a USB stick at `grandMA3/gma3_library/datapools/plugins/`
2. In the show, open the Plugins pool, edit an empty slot, tap **Import** and choose the plugin's `.xml`.
3. Save the show. Plugins live in the show file, so import them once per show, or keep them in a template show.

To update a plugin, import the new version into the same pool slot.

## Notes

- The dialogs leave the command line live, so console keys work while a plugin window is open.
- Every plugin logs what it does to the System Monitor.
- UI colours are stored as colour definitions in the colour theme (groups `CFG` and `LBL`).
