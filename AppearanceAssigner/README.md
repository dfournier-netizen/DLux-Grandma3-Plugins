# Appearance Assigner

grandMA3 plugin (target 2.5.1) for assigning or clearing appearances on many pool objects at once.

- One window for the whole session; it stays open between rounds until you close it.
- Filter by object type: Sequences, Presets (all preset pools), Groups, Macros, Layouts, Worlds, Filters, MAtricks, Timecodes, Plugins.
- Search as you type (type, number, name, preset pool, current appearance); tap rows to select, or Select all matches. **Reload** re-reads the pools.
- Pick an existing appearance (searchable) or create a new one by name and colour.
- Assign or Clear, with an option to skip objects that already have an appearance.
- Thumbnails are off when the window opens; tap **Thumbs** to turn them on for the session. They build in the background and are cached in the MA textures folder (`aacache_*.tga`); the first run on a large show takes a while, later runs are instant. Non-PNG images show as a colour swatch.

## Install
Import the newest `AppearanceAssigner_Embedded_<timestamp>.xml` into an empty Plugins pool slot (single XML, Lua embedded).

## Status
1.2.1 -- fixes 1.2.0 crashing MA on open; thumbnails now off by default. A crash trace is written to `gma3_library/AppearanceAssigner_trace.txt` on each open. Assign/clear confirmed on 2.5.1 (sequences).
