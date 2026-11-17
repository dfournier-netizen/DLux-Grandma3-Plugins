# DLux grandMA3 Plugins

Lua plugins for grandMA3. Current builds target grandMA3 2.5.1 (onPC and console). MAgic Preset Builder, SetNShot, MATrick Builder, Layout Builder and CreateFixtureGroups were first built on onPC 2.4.2.

| Plugin | Version | What it does |
|---|---|---|
| [SeqTools](SeqTools/) | 1.3.2 | Works on many sequences at once in one window, with three modes: Settings (bulk sequence settings, masters, filters, tags), Copy & Regroup (copy, rename and remap recipe-line groups, then cook) and Cues & Recipes (bulk-edit cue, part, recipe line, MAtricks, phaser and OffCue values) |
| [Appearance Assigner](AppearanceAssigner/) | 1.2.1 | Assigns or clears appearances on many pool objects at once, with a searchable, type-filtered list and appearance thumbnails |
| [MAgic Preset Builder](MAgicPresetBuilder/) | 2.1.0 | Builds a MAgic (multi-step) preset from existing presets, with a visual preset picker |
| [SetNShot](SetNShot/) | 2.1.1 | Sets NShot, direction, measure and width on phaser recipes across ranges of sequences, cues and recipes |
| [MATrick Builder](MATrickBuilder/) | 2.1.1 | Builds the MATrick sequences, tags and layouts in one run |
| [Layout Builder](LayoutBuilder/) | 1.7.3 | Places pool objects on a layout grid with a default action; detects collisions with what's already on a layout and can match its existing grid |
| [CreateFixtureGroups](CreateFixtureGroups/) | 2.9.0 | Generates groups from the patch: odds/evens, fixture types, position zones, LX / booms / ground rows, and cell groups in the fixture's native grid |

### In development

| Plugin | Version | What it does | Status |
|---|---|---|---|
| [DLux Cookbook](DLuxCookbook/) | 1.0.0 | Converts sequences stored with hard values into recipe-based sequences (presets + groups + recipe lines), or captures the programmer into a recipe-based sequence | Not yet console-tested |
| [DLux Bridge](Dlux%20Bridge/) | 0.1.4 | Console-side feedback for the DLux FaderWing motorized fader controller | Bench spike |

Also pending console tests: SeqTools Cues & Recipes mode, and Appearance Assigner background thumbnails.

### Retired

- [SequenceEdit](SequenceEdit/) (SeqEdit 1.1.0): replaced by SeqTools Settings mode.
- [SequenceCopyRegroup](SequenceCopyRegroup/): folded into SeqTools Copy & Regroup mode. The folder only holds a diagnostic.

## Install

Each plugin is a single `.xml` with the Lua embedded. Where a folder has more than one, use the newest timestamp. Older builds are in each plugin's `Olds` folder.

1. Copy the `.xml` into the MA3 plugin library:
   - **onPC (Windows):** `C:\ProgramData\MALightingTechnology\gma3_library\datapools\plugins\`
   - **Console:** the same `gma3_library/datapools/plugins` folder, e.g. from a USB stick at `grandMA3/gma3_library/datapools/plugins/`
2. In the show, open the Plugins pool, edit an empty slot, tap **Import** and choose the `.xml`.
3. Save the show. Plugins live in the show file, so import them once per show, or keep them in a template show.

To update a plugin, import the new version into the same pool slot.

## Notes

- The dialogs leave the command line live, so console keys work while a plugin window is open.
- Every plugin logs what it does to the System Monitor.
- UI colours are stored as colour definitions in the colour theme, one group per plugin (e.g. `CFG`, `LBL`, `DCB`).
