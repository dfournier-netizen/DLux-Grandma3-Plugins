# Appearance Assigner

grandMA3 plugin (target 2.5.1) for assigning or clearing appearances on many pool objects at once.

- One window for the whole session; it stays open between rounds until you close it.
- Filter by object type: Sequences, Presets (all preset pools), Groups, Macros, Layouts, Worlds, Filters, MAtricks, Timecodes, Plugins.
- Search as you type (type, number, name, preset pool, current appearance); tap rows to select, or Select all matches.
- Pick an existing appearance (searchable, with thumbnails) or create a new one by name and colour.
- Assign or Clear, with an option to skip objects that already have an appearance.
- Thumbnails build in the background and are cached in the MA textures folder (`aacache_*.tga`); the first run on a large show takes a while, later runs are instant. Non-PNG images show as a colour swatch.

## Install
Import `AppearanceAssigner_Embedded_<timestamp>.xml` into an empty Plugins pool slot (single XML, Lua embedded).

## Status
1.2.0 -- assign/clear confirmed on 2.5.1 (sequences); background thumbnails pending console test.
