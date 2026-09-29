# MAgic Preset Builder 2.1.0

Builds a MAgic (multi-step) preset by combining two or more existing presets from one pool, then converts it to Universal.

- **Pools:** Dimmer, Position, Gobo, Color, Beam, Focus, Control, Shapers, Video, All 1-4.
- **Fixtures:** type a range or group, or select on the console and tap **Use Selection**.
- **Steps:** type a preset per step, or tap the pick button to open a picker that shows every preset in the pool with its appearance image.

## Notes

- Appearance images are converted once to small TGA files named `mpbcache_*.tga` in the MA3 textures folder (`<install>/shared/resource/textures/`), then reused. The first open of a pool can take up to a minute on onPC; after that it's instant.
- Colour-only appearances show as a colour strip.
