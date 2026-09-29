--[[
    CreateFixtureGroups.lua  v2.9
    GrandMA3 Plugin -- Version compatible: 2.3.2+

    PURPOSE:
        Reads all patched fixtures on a user-named stage and auto-generates
        Groups:

        SECTION B -- Per-type Odds / Evens (outside-in pairing, unchanged)
        SECTION C -- Fixture Types (one group per type)
        SECTION D -- Position zones by PHYSICAL position:
                     Lateral : SR / CS / SL   (CS = within +/- centre band of 0)
                     Depth   : US / Mid Stage / DS (rig position lines split into
                               thirds, upstage->downstage; a pipe is never split)
                     Height  : Floor / Low / Flown (fixed height limits)
                     D1 = all types combined, D2 = per type (same limits)
        SECTION F -- Sub-fixtures (cells), FID order, off by default:
                     "<Type> Cells", "<Type> Cell N", "<Type> Cells Odds/Evens",
                     "<Type> Cells Left/Middle/Right" (thirds of each fixture
                     by grid X, Left = low X), and "<zone/LX/boom> Cells" versions
                     of the Section D/E groups.
                     Cells = the DEEPEST sub-fixtures only (no parents).
                     Each parent's cells are their own set (JDC1 plate
                     401.3.x and beam 401.4.x), and cells with a different
                     name (Rayzor SparkLED vs pixels) get their own set.
        SECTION E -- Rig positions:
                     Ground Row  : fixtures below the floor limit
                     Booms       : vertical stacks -> "Boom SL 1", "Boom SR 1"
                     LX          : overhead positions clustered by depth AND
                                   height within a tolerance, numbered
                                   upstage first ("LX 1" = most upstage)

    CALL CHAIN:
        main()
          -> showSettingsUI()      Dialog 1: stage, slot, axes, zone limits
          -> collectFixtures()     world positions (parent offsets optional)
          -> buildTypeMap()        types + odds/evens
          -> showGroupOptionsUI()  Dialog 2: sections + types
          -> runSectionB/C/D/E()   build a PLAN of groups (nothing stored yet)
          -> MessageBox confirm    group count + slot range
          -> executePlan()         stores groups with a progress bar

    NOTES (v2.0):
        - v1 swapped the lateral/depth thresholds and used count percentiles;
          zones are now physical and consistent between D1 and D2.
        - v1 LX detection used a self-scaling depth gap (merged or split pipes);
          now a fixed, editable tolerance on depth + height, booms separate.
        - Nested fixtures: when "Parent offset" is on, a fixture patched under
          another fixture (truss / grouping) gets its parents' positions added.
          Parent ROTATION is not applied -- a warning is logged if found.
        - Pool slots are checked by real group number (Children() + .no).

    NOTES (v2.4):
        - Cell groups keep the fixture type's native selection grid: the
          parents are selected, "Down" exposes the cells in their grid, the
          group is stored, and unwanted cells are removed with
          "Store Group N /Remove" (all confirmed on console, GridTest v0.4).
          Groups with one cell per fixture ("Cell N") stay a simple list.
        - Left / Middle / Right thirds split by the cell's grid X position.
        - Top-level cells with different names (e.g. "[RGBW Pixel n]" and
          "[SparkLED]") become separate sets, named from the minority name.
        - Flatten = deepest cells only (Down to the deepest level).

    NOTES (v2.5):
        - Centre band AUTO (default): SR / CS / SL are three equal-width
          bands, symmetric on the stage centre, spanning to the farthest
          fixture (CS = +/- one third of that distance). MANUAL = the
          +/- value typed in dialog 1, as before.

    NOTES (v2.6):
        - "Flatten" option removed. Cells are always the deepest level only
          (sub-fixtures above it, e.g. JDC1 Beam/Plate Module, are left out
          and logged), and sets always stay separate.
        - Set names: brackets dropped ("[Single Back Plate M3]" ->
          "Single Back Plate M3"); the name split only strips a trailing
          " <number>" ("RGBW Pixel 12" -> "RGBW Pixel", "Beam Module M3"
          stays). Only a clear majority name stays unlabelled.

    NOTES (v2.7):
        - Cell-set picker: when cell groups are on and a set holds cells
          with different names, a "Cell sets" dialog lists each name per
          fixture type. Ticked = own groups, unticked = stays with the other
          cells of that fixture / sub-fixture. Default ticks only a small
          minority name (fewer than half the cells of the most common name,
          e.g. 1 SparkLED vs 19 pixels), so 3 uniquely named cells (Paladin)
          stay one set. Different parents (JDC1 plate / beam) are always
          separate sets.

    NOTES (v2.8):
        - Overwrite mode: a group whose name already exists is overwritten in
          its own slot (lowest slot if the name exists twice); every NEW group
          goes to the start slot and up, skipping occupied slots, as in
          create mode. Stores address the slot number in both cases.
        - Excluded fixtures are logged per fixture type with the reason.

    NOTES (v2.9):
        - Stage centre / centre band fields may be blank while set to AUTO.
        - Saved defaults, stored in the show file (global variables
          CFG_Defaults_Dialog1 / _Dialog2 / _CellSets): "Save as default"
          and "Reset defaults" in dialog 1, dialog 2 and the Cell sets
          picker. Reset clears that dialog's saved defaults and reopens it
          with the built-in values. Fixture type ticks are not saved.
        - UI cleanup: AUTO/MANUAL toggles sit next to their values, axis
          section header, 4-button footers, quieter System Monitor output.
--]]
-- MA3 plugin argument binding.
-- MA3 passes four arguments to every plugin chunk via varargs:
--   1: pluginName     (string)
--   2: componentName  (string)
--   3: signalTable    (table)  -- used to register UI callbacks
--   4: myHandle       (handle) -- handle to this plugin component
local pluginName    = select(1, ...)
local componentName = select(2, ...)
local signalTable   = select(3, ...)
local myHandle      = select(4, ...)

-- MA3's Printf/ErrPrintf printed %.2f floats as 0.00 (seen on 2.4.2), so all
-- messages are formatted in Lua first and passed through as a plain string.
local _MAPrintf, _MAErrPrintf = Printf, ErrPrintf
local function Printf(fmt, ...)
    if select('#', ...) > 0 then fmt = string.format(fmt, ...) end
    _MAPrintf("%s", fmt)
end
local function ErrPrintf(fmt, ...)
    if select('#', ...) > 0 then fmt = string.format(fmt, ...) end
    _MAErrPrintf("%s", fmt)
end

-- Module-level axis remapping table.
-- Maps semantic roles to MA3 axis property names (x, y, or z).
-- Updated from dialog 1 before collectFixtures runs.
-- lateral = SR/SL axis, depth = US/DS axis, height = Low/High axis
local AXIS_MAP = { lateral = 'y', depth = 'x', height = 'z', invertLateral = false, invertDepth = false, invertHeight = false }

-- Zone / rig-position limits (metres). Defaults; editable in dialog 1.
local CFG = {
    centreBand      = 1.5,   -- |lateral| <= this  -> CS (manual value)
    centreBandAuto  = true,  -- true = three equal bands, symmetric on the stage centre
    floorMax        = 0.5,   -- height <  this     -> Floor / Ground Row
    lowMax          = 3.0,   -- height <  this     -> Low, otherwise Flown
    lxTol           = 0.5,   -- depth/height tolerance for LX + boom clustering
    addParentOffset = true,  -- add parent fixture positions to nested fixtures
    centreLat       = 0,     -- lateral stage centre in MA coordinates (m)
    centreAuto      = false, -- true = midpoint of the rig's lateral extent
}
local PLUGIN_VERSION = "2.9.0"

-- UI color handles -- one per unique element, populated by initColors().
-- Technique from Pro Plugins: create Color Defs in the MA3 color theme via
-- Cmd(), assign the handle as BackColor. Always force-updates RGBA values.
local UI_BG_IDX    = 30.12  -- BaseInput bg (confirmed numeric index)
-- Axis cycle buttons
local UI_SEAFOAM   = nil    -- Lateral axis  #00D8A6 seafoam
local UI_APRICOT   = nil    -- Depth axis    #D80032 magenta-red
local UI_MAGENTA   = nil    -- Height axis   #0066CC blue
-- Footer buttons
local UI_NEXT      = nil    -- Next/Create   #00B050 green
local UI_ABORT     = nil    -- Abort         #CC2200 red
-- Invert buttons
local UI_INV_NORM  = nil    -- Invert normal #E8A901 amber
local UI_INV_ACT   = nil    -- Invert active #FF6600 bright orange
-- Title bar
local UI_TITLE     = nil    -- Title bar     #00D8A6 seafoam (matches lateral)
local UI_SAVE      = nil    -- Save default  #2F6FD6 blue
local UI_RESET     = nil    -- Reset default #6B6B6B grey

--- Parse a hex RGBA string "RRGGBBAA" into r,g,b,a numbers (0-255).
local function parseHexRGBA(hex)
    hex = hex:gsub("#", "")
    local r = tonumber(hex:sub(1,2), 16) or 255
    local g = tonumber(hex:sub(3,4), 16) or 255
    local b = tonumber(hex:sub(5,6), 16) or 255
    local a = tonumber(hex:sub(7,8), 16) or 255
    return r, g, b, a
end

--- Set color on a Color Def using BakaCowpoke's confirmed working syntax.
--- Must be called while NOT inside a cd context (from root).
local function setColorDefRGBA(name, idx, rgba)
    -- BakaCowpoke confirmed path: cd into ColorTheme group 1 subgroup 1 (Global)
    -- then set N RGBA="RRGGBBAA" /nu
    Cmd("cd root / nu")
    Cmd("cd \"ColorTheme\".1.1 / nu")
    local r = Cmd(string.format('set %d RGBA="%s" /nu', idx, rgba))
    Cmd("cd root / nu")
    Printf("  Set '%s' idx=%d RGBA=%s: %s", name, idx, rgba, tostring(r))
end

--- Create or update a Color entry in a dedicated "CFG" Color Group.
--- Uses ColorGroups structure (not ColorDefCollect) so entries are referenceable
--- as "CFG.EntryName" strings for BackColor assignment.
--- Returns the string "CFG.name" for use as BackColor value.
local function getOrCreateColorDef(name, rgba)
    -- Ensure the CFG color group exists in ColorGroups
    local colorGroups = Root().ColorTheme.ColorGroups
    if not colorGroups then
        ErrPrintf("ColorTheme.ColorGroups not found")
        return nil
    end

    -- Get or create the "CFG" group
    local cfgGroup = colorGroups["CFG"]
    if not cfgGroup then
        Printf("Creating 'CFG' color group")
        local gIdx = 1
        while colorGroups[gIdx] ~= nil do gIdx = gIdx + 1 end
        Cmd("cd root / nu")
        Cmd("cd \"ColorTheme\" / nu")
        Cmd("cd \"ColorGroups\" / nu")
        Cmd("store " .. tostring(gIdx) .. " /nu")
        Cmd("label " .. tostring(gIdx) .. " \"CFG\" /nu")
        Cmd("cd root / nu")
        cfgGroup = colorGroups["CFG"]
        if not cfgGroup then
            ErrPrintf("Failed to create CFG color group")
            return nil
        end
    end

    -- Get or create the color entry within CFG group
    local entry = cfgGroup[name]
    local entryIdx

    if entry then
        entryIdx = entry.index
    else
        entryIdx = 1
        while cfgGroup[entryIdx] ~= nil do entryIdx = entryIdx + 1 end
        Printf("Creating 'CFG.%s' at idx %d", name, entryIdx)

        -- Navigate into the CFG group and store the entry
        Cmd("cd root / nu")
        Cmd("cd \"ColorTheme\" / nu")
        Cmd("cd \"ColorGroups\" / nu")
        Cmd("cd \"CFG\" / nu")
        Cmd("store " .. tostring(entryIdx) .. " /nu")
        Cmd("label " .. tostring(entryIdx) .. " \"" .. name .. "\" /nu")
        Cmd("cd root / nu")
    end

    -- Set RGBA by navigating into the CFG group
    local gIdx = cfgGroup.index
    Cmd("cd root / nu")
    Cmd("cd \"ColorTheme\" / nu")
    Cmd("cd \"ColorGroups\" / nu")
    Cmd("cd \"CFG\" / nu")
    Cmd(string.format('set %d RGBA="%s" /nu', entryIdx, rgba))
    Cmd("cd root / nu")

    -- Return the string path "CFG.name" for use as BackColor
    return "CFG." .. name
end

--- Initialise all custom UI color handles. Call once at plugin start.
local function initColors()
    -- One Color Def per unique UI element. RGBA always force-updated.
    -- Axis cycle buttons (complementary pair + blue)
    UI_SEAFOAM  = getOrCreateColorDef("CFG_SF2",  "00D8A6FF")  -- seafoam lateral
    UI_APRICOT  = getOrCreateColorDef("CFG_MR2",   "FF69B4FF")  -- pink depth
    UI_MAGENTA  = getOrCreateColorDef("CFG_BL2",      "7404BFFF")  -- Pro Plugins purple height
    -- Footer buttons
    UI_NEXT     = getOrCreateColorDef("CFG_NG2", "00B050FF")  -- green Next/Create
    UI_ABORT    = getOrCreateColorDef("CFG_AR2",  "CC2200FF")  -- red Abort
    -- Invert toggle buttons
    UI_INV_NORM = getOrCreateColorDef("CFG_IN2", "E8A901FF")  -- amber normal
    UI_INV_ACT  = getOrCreateColorDef("CFG_IA2", "FF6600FF")  -- orange active
    -- Title bar
    UI_TITLE    = getOrCreateColorDef("CFG_TB2",  "00D8A6FF")  -- seafoam title
    -- Save / reset default buttons
    UI_SAVE     = getOrCreateColorDef("CFG_SV2",  "2F6FD6FF")  -- blue save
    UI_RESET    = getOrCreateColorDef("CFG_RS2",  "6B6B6BFF")  -- grey reset

    local allOk = UI_SEAFOAM and UI_APRICOT and UI_MAGENTA and UI_NEXT and UI_ABORT and
                  UI_INV_NORM and UI_INV_ACT and UI_TITLE and UI_SAVE and UI_RESET
    if not allOk then ErrPrintf("One or more UI colors failed -- some buttons may be grey") end
end

-------------------------------------------------------------------------------
-- LAYER 1 -- Primitive utilities
-------------------------------------------------------------------------------

local function trim(s)
    return s and s:match("^%s*(.-)%s*$") or ""
end

--- Return 1 (low), 2 (mid), or 3 (high) for a value given two cut-points.
local function classifyThird(value, lo33, hi66)
    if value <= lo33 then return 1
    elseif value <= hi66 then return 2
    else return 3
    end
end

--- Return the 33rd and 66th percentile values from a list of numbers.
local function computePercentileCuts(values)
    if #values == 0 then return 0, 0 end
    local sorted = {}
    for _, v in ipairs(values) do table.insert(sorted, v) end
    table.sort(sorted)
    local n   = #sorted
    local i33 = math.max(1, math.floor(n * 0.33 + 0.5))
    local i66 = math.max(1, math.min(n, math.floor(n * 0.66 + 0.5)))
    return sorted[i33], sorted[i66]
end

-------------------------------------------------------------------------------
-- LAYER 2 -- Pool slot management
-------------------------------------------------------------------------------

-- Used group numbers, read once per run from the real pool (Children + .no)
-- and updated as the plan assigns slots.
local usedSlots = {}
local existingByName = {}   -- group name -> lowest pool slot holding it

local function loadUsedSlots()
    usedSlots, existingByName = {}, {}
    local ok, kids = pcall(function() return DataPool().Groups:Children() end)
    if ok and kids then
        for _, g in ipairs(kids) do
            local no = tonumber(g.no)
            local nm = trim(g.name or "")
            if no and nm ~= "" then
                usedSlots[no] = true
                if not existingByName[nm] or no < existingByName[nm] then existingByName[nm] = no end
            end
        end
    end
end

local function slotIsOccupied(slotIndex)
    return usedSlots[slotIndex] == true
end

local function nextFreeSlot(slotIndex)
    while slotIsOccupied(slotIndex) do
        slotIndex = slotIndex + 1
    end
    return slotIndex
end

-------------------------------------------------------------------------------
-- Saved defaults -- stored in the show file as global variables (one string
-- per dialog: "key=value;key=value", keys/values percent-encoded).
-------------------------------------------------------------------------------
local SAVE_VARS = { d1 = "CFG_Defaults_Dialog1", d2 = "CFG_Defaults_Dialog2", cells = "CFG_Defaults_CellSets" }

-- Built-in defaults (dialog 1 values as they appear in the fields)
local BUILTIN_D1 = {
    stage = "Active Show", slot = "1",
    axLat = "Y", axDep = "X", axHt = "Z",
    invLat = false, invDep = false, invHt = false,
    origin = "0", centre = "1.5", floor = "0.5", low = "3.0", tol = "0.5",
    centreAuto = false, bandAuto = true, addParent = true,
}
-- Dialog 2 section checkboxes, in dialog order (ids = settings keys)
local SECTION_IDS = {
    "doOddsEvens", "doPosOddEven", "doTypes", "doZones", "doTypeZones",
    "doLXMixed", "doLXPerType", "doGroundMixed", "doGroundPerType",
    "cellsAll", "cellsIndex", "cellsOddEven", "cellsThirds", "cellsZones",
    "oeSimple", "overwrite",
}
local BUILTIN_D2 = {}
for i, id in ipairs(SECTION_IDS) do BUILTIN_D2[id] = (i <= 5) end

local function copyT(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end

local function encVal(s)
    return (tostring(s):gsub("[%%;=%c]", function(c) return string.format("%%%02X", c:byte()) end))
end
local function decVal(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

--- Save a flat table (string / boolean values). Returns true on success.
local function saveDefaults(which, t)
    local keys, parts = {}, {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = t[k]
        if type(v) == "boolean" then v = v and "1" or "0" end
        parts[#parts + 1] = encVal(k) .. "=" .. encVal(v)
    end
    local ok = pcall(SetVar, GlobalVars(), SAVE_VARS[which], table.concat(parts, ";"))
    if not ok then ErrPrintf("Could not save defaults (%s).", SAVE_VARS[which]) end
    return ok
end

--- Load a saved table (all values as strings), or nil when nothing is saved.
local function loadDefaults(which)
    local ok, v = pcall(function() return GetVar(GlobalVars(), SAVE_VARS[which]) end)
    if not ok or type(v) ~= "string" or v == "" then return nil end
    local t = {}
    for item in v:gmatch("[^;]+") do
        local k, val = item:match("^([^=]*)=(.*)$")
        if k then t[decVal(k)] = decVal(val) end
    end
    return t
end

local function clearDefaults(which)
    pcall(SetVar, GlobalVars(), SAVE_VARS[which], "")
end

--- Built-in table with saved values laid over it (booleans restored).
local function mergeDefaults(builtin, saved)
    local out = copyT(builtin)
    if saved then
        for k, v in pairs(saved) do
            if type(builtin[k]) == "boolean" then out[k] = (v == "1")
            elseif builtin[k] ~= nil then out[k] = v end
        end
    end
    return out
end

-------------------------------------------------------------------------------
-- LAYER 2 -- User input (Overlay UI)
-- Uses GetFocusDisplay().ScreenOverlay:Append() confirmed working pattern.
-- Color palette: dark grey background, seafoam green accents.
-------------------------------------------------------------------------------

-- (color constants defined above in LAYER 2 UI section)

-- Shared UI helpers

--- Build a standard title bar with a close button on the overlay base.
--- Returns the close button so the caller can attach its callback.
local function buildTitleBar(base, titleText)
    local titleBar         = base:Append('TitleBar')
    titleBar.Columns       = 2
    titleBar.Rows          = 1
    titleBar.Anchors       = '0,0'
    -- Fix the close button column to a small square width
    titleBar[2][2].SizePolicy = 'Fixed'
    titleBar[2][2].Size       = 44

    local titleBtn         = titleBar:Append('TitleButton')
    titleBtn.Text          = titleText
    titleBtn.Font          = 'Regular28'
    titleBtn.Anchors       = '0,0'

    local closeBtn         = titleBar:Append('CloseButton')
    closeBtn.Anchors       = '1,0'
    closeBtn.plugincomponent = myHandle
    titleBar.BackColor     = UI_TITLE    -- dedicated title bar color
    return closeBtn
end

--- Build the footer: primary action + Abort, or (withDefaults) primary +
--- Save as default + Reset defaults + Abort.
--- Returns primaryBtn, abortBtn, saveBtn, resetBtn.
local function buildFooter(base, anchorRow, primaryLabel, withDefaults)
    local grid         = base:Append('UILayoutGrid')
    grid.Columns       = withDefaults and 4 or 2
    grid.Rows          = 1
    grid.H             = 70
    grid.Anchors       = '0,' .. anchorRow
    -- UIObject in grid cell for color; Button in same cell as click catcher
    local primary      = grid:Append('Button')
    primary.Anchors    = '0,0'
    primary.Text       = primaryLabel
    primary.TextalignmentH = 'Centre'
    primary.HasHover   = 'Yes'
    primary.plugincomponent = myHandle
    primary.BackColor  = UI_NEXT    -- green Next/Create button

    local save, reset
    if withDefaults then
        save               = grid:Append('Button')
        save.Anchors       = '1,0'
        save.Text          = 'Save as default'
        save.TextalignmentH = 'Centre'
        save.HasHover      = 'Yes'
        save.plugincomponent = myHandle
        save.BackColor     = UI_SAVE

        reset              = grid:Append('Button')
        reset.Anchors      = '2,0'
        reset.Text         = 'Reset defaults'
        reset.TextalignmentH = 'Centre'
        reset.HasHover     = 'Yes'
        reset.plugincomponent = myHandle
        reset.BackColor    = UI_RESET
    end

    local abort        = grid:Append('Button')
    abort.Anchors      = withDefaults and '3,0' or '1,0'
    abort.Text         = 'Abort'
    abort.TextalignmentH = 'Centre'
    abort.HasHover     = 'Yes'
    abort.plugincomponent = myHandle
    abort.BackColor    = UI_ABORT   -- red Abort button

    return primary, abort, save, reset
end

--- Dialog 1: Stage name + start slot via overlay UI.
--- Key confirmed facts from MA Lighting forum:
---   - LineEdit live value is in caller.content (not caller.Text)
---   - The event is textchanged (lowercase, not Changed)
---   - plugincomponent must be lowercase
---   - dialog:WaitInit() needed before FindBestFocus()
--- D = initial values (built-in defaults with saved defaults laid over).
--- Returns the settings table, { reopen = true } after "Reset defaults",
--- or nil on cancel/abort.
local function showSettingsUI(overlay, D)
    local result  = nil
    local done    = false

    local base          = overlay:Append('BaseInput')
    base.H              = 900
    base.W              = 1230
    base.Columns        = 1
    base.Rows           = 3
    base[1][1].SizePolicy = 'Fixed'
    base[1][1].Size     = 55
    base[1][2].SizePolicy = 'Stretch'
    base[1][3].SizePolicy = 'Fixed'
    base[1][3].Size     = 70
    base.AutoClose      = 'No'
    base.CloseOnEscape  = 'Yes'
    base.BackColor      = UI_BG_IDX

    local closeBtn      = buildTitleBar(base, 'Create Fixture Groups v' .. PLUGIN_VERSION .. '  |  Step 1 of 2')
    closeBtn.clicked    = 'onS1Close'

    local scrollBox     = base:Append('ScrollBox')
    scrollBox.Name      = 's1Content'
    scrollBox.Anchors   = '0,1'

    local scrollBarS1   = base:Append('ScrollBarV')
    scrollBarS1.ScrollTarget = scrollBox      -- direct object reference
    scrollBarS1.Anchors = '0,1'

    -- Layout scaled to match the 2x wide / 1.5x tall dialog
    -- Centered within the 1000px wide box
    local rowH   = 90    -- 60 * 1.5
    local labelW = 300   -- 150 * 2
    local inputW = 600   -- 300 * 2
    local gap    = 20
    local padX   = (1000 - labelW - inputW - gap) / 2  -- centers within original 1000px content area

    -- Stage Name row
    local lblStage          = scrollBox:Append('UIObject')
    lblStage.Text           = 'Stage Name'
    lblStage.Font           = 'Regular32'
    lblStage.TextalignmentH = 'Right'
    lblStage.W              = labelW
    lblStage.H              = rowH
    lblStage.X              = padX
    lblStage.Y              = 20

    local edStage           = scrollBox:Append('LineEdit')
    edStage.Text            = D.stage
    edStage.Font            = 'Regular32'
    edStage.TextalignmentH  = 'Centre'
    edStage.TextalignmentV  = 'Centre'
    edStage.W               = inputW
    edStage.H               = rowH
    edStage.X               = padX + labelW + gap
    edStage.Y               = 20
    edStage.plugincomponent = myHandle
    edStage.textchanged     = 'onStageChanged'

    -- Start Slot row
    local lblSlot           = scrollBox:Append('UIObject')
    lblSlot.Text            = 'Start Slot'
    lblSlot.Font            = 'Regular32'
    lblSlot.TextalignmentH  = 'Right'
    lblSlot.W               = labelW
    lblSlot.H               = rowH
    lblSlot.X               = padX
    lblSlot.Y               = 20 + rowH + 15

    local edSlot            = scrollBox:Append('LineEdit')
    edSlot.Text             = D.slot
    edSlot.Font             = 'Regular32'
    edSlot.TextalignmentH   = 'Centre'
    edSlot.TextalignmentV   = 'Centre'
    edSlot.W                = inputW
    edSlot.H                = rowH
    edSlot.X                = padX + labelW + gap
    edSlot.Y                = 20 + rowH + 15
    edSlot.plugincomponent  = myHandle
    edSlot.textchanged      = 'onSlotChanged'

    -- Track live values via textchanged -- .content holds the typed value
    local currentStage = D.stage
    local currentSlot  = D.slot

    -- ------ Axis assignment section ---------------------------------------------------------------------------------------------------------------------------------------------
    -- Three cycle buttons: tap to rotate the assigned MA3 axis (X -> Y -> Z -> X)
    -- Defaults: Lateral=Y, Depth=X, Height=Z (confirmed working convention)
    local axisAssign  = { lateral = D.axLat, depth = D.axDep, height = D.axHt }
    local axisInvert  = { lateral = D.invLat, depth = D.invDep, height = D.invHt }
    local axisOptions = { 'X', 'Y', 'Z' }

    local function nextAxis(current)
        for i, v in ipairs(axisOptions) do
            if v == current then
                return axisOptions[(i % #axisOptions) + 1]
            end
        end
        return 'X'
    end

    local function axisButtonLabel(role, axis)
        local roleNames = { lateral='Lateral (SL/SR)', depth='Depth (US/DS)', height='Height (Low/Hi)' }
        local inv = axisInvert[role] and '  [INVERTED]' or ''
        return roleNames[role] .. ':  MA3 ' .. axis .. ' axis' .. inv
    end

    local axisY  = 20 + rowH * 2 + 15 * 2 + 20  -- below the two input rows
    local axisH  = 70
    local axisW  = inputW + labelW + gap
    local axisX  = padX

    local axisHdr           = scrollBox:Append('UIObject')
    axisHdr.Text            = '-- Axis mapping (tap to change) --'
    axisHdr.Font            = 'Regular24'
    axisHdr.TextalignmentH  = 'Centre'
    axisHdr.W               = axisW + 230
    axisHdr.H               = 44
    axisHdr.X               = axisX
    axisHdr.Y               = axisY
    axisY = axisY + 54

    -- Axis button colors: confirmed integer BackColor indices
    -- Lateral=12 (seafoam), Depth=13 (apricot), Height=4.5 (magenta)
    -- UIObject: color + text display (resting state color confirmed working)
    -- Single Button per action. No Font property (Font triggers Obj.Set error).
    -- BackColor shows on hover. Text + click all on the one element.
    local btnLateral = scrollBox:Append('Button')
    btnLateral.Text  = axisButtonLabel('lateral', axisAssign.lateral)
    btnLateral.H     = axisH
    btnLateral.W     = axisW
    btnLateral.X     = axisX
    btnLateral.Y     = axisY
    btnLateral.TextalignmentH = 'Centre'
    btnLateral.HasHover = 'Yes'
    btnLateral.plugincomponent = myHandle
    btnLateral.clicked = 'onCycleLateral'
    btnLateral.BackColor = UI_SEAFOAM

    local btnInvLateral = scrollBox:Append('Button')
    btnInvLateral.Text = axisInvert.lateral and 'Lateral: INVERTED' or 'Lateral: Normal'
    btnInvLateral.H    = axisH
    btnInvLateral.W    = 220
    btnInvLateral.X    = axisX + axisW + 10
    btnInvLateral.Y    = axisY
    btnInvLateral.TextalignmentH = 'Centre'
    btnInvLateral.HasHover = 'Yes'
    btnInvLateral.plugincomponent = myHandle
    btnInvLateral.clicked = 'onInvertLateral'
    btnInvLateral.BackColor = axisInvert.lateral and UI_INV_ACT or UI_INV_NORM

    local btnDepth = scrollBox:Append('Button')
    btnDepth.Text  = axisButtonLabel('depth', axisAssign.depth)
    btnDepth.H     = axisH
    btnDepth.W     = axisW
    btnDepth.X     = axisX
    btnDepth.Y     = axisY + axisH + 10
    btnDepth.TextalignmentH = 'Centre'
    btnDepth.HasHover = 'Yes'
    btnDepth.plugincomponent = myHandle
    btnDepth.clicked = 'onCycleDepth'
    btnDepth.BackColor = UI_APRICOT

    local btnInvDepth = scrollBox:Append('Button')
    btnInvDepth.Text = axisInvert.depth and 'Depth: INVERTED' or 'Depth: Normal'
    btnInvDepth.H    = axisH
    btnInvDepth.W    = 220
    btnInvDepth.X    = axisX + axisW + 10
    btnInvDepth.Y    = axisY + axisH + 10
    btnInvDepth.TextalignmentH = 'Centre'
    btnInvDepth.HasHover = 'Yes'
    btnInvDepth.plugincomponent = myHandle
    btnInvDepth.clicked = 'onInvertDepth'
    btnInvDepth.BackColor = axisInvert.depth and UI_INV_ACT or UI_INV_NORM

    local btnHeight = scrollBox:Append('Button')
    btnHeight.Text  = axisButtonLabel('height', axisAssign.height)
    btnHeight.H     = axisH
    btnHeight.W     = axisW
    btnHeight.X     = axisX
    btnHeight.Y     = axisY + (axisH + 10) * 2
    btnHeight.TextalignmentH = 'Centre'
    btnHeight.HasHover = 'Yes'
    btnHeight.plugincomponent = myHandle
    btnHeight.clicked = 'onCycleHeight'
    btnHeight.BackColor = UI_MAGENTA

    local btnInvHeight = scrollBox:Append('Button')
    btnInvHeight.Text = axisInvert.height and 'Height: INVERTED' or 'Height: Normal'
    btnInvHeight.H    = axisH
    btnInvHeight.W    = 220
    btnInvHeight.X    = axisX + axisW + 10
    btnInvHeight.Y    = axisY + (axisH + 10) * 2
    btnInvHeight.TextalignmentH = 'Centre'
    btnInvHeight.HasHover = 'Yes'
    btnInvHeight.plugincomponent = myHandle
    btnInvHeight.clicked = 'onInvertHeight'
    btnInvHeight.BackColor = axisInvert.height and UI_INV_ACT or UI_INV_NORM

    -- ------ Zone & rig-position limits (metres) ------
    local limY = axisY + (axisH + 10) * 3 + 20
    local limHdr            = scrollBox:Append('UIObject')
    limHdr.Text             = '-- Zone & rig-position limits (metres) --'
    limHdr.Font             = 'Regular24'
    limHdr.TextalignmentH   = 'Centre'
    limHdr.W                = axisW + 230
    limHdr.H                = 44
    limHdr.X                = axisX
    limHdr.Y                = limY
    limY = limY + 54

    local limVals = {
        origin = D.origin, centre = D.centre, floor = D.floor, low = D.low, tol = D.tol,
    }
    local addParent  = D.addParent
    local centreAuto = D.centreAuto
    local bandAuto   = D.bandAuto
    local limRowH, limEdW = 70, 200
    -- One limit row: label, value field, and either a hint or an AUTO/MANUAL
    -- toggle button (toggle = { text, clicked, color }). Returns y, hint/button.
    local function limitRow(label, key, hint, y, toggle)
        local l = scrollBox:Append('UIObject')
        l.Text = label; l.Font = 'Regular28'; l.TextalignmentH = 'Right'
        l.W = labelW; l.H = limRowH; l.X = padX; l.Y = y
        local e = scrollBox:Append('LineEdit')
        e.Text = limVals[key]; e.Font = 'Regular28'; e.TextalignmentH = 'Centre'
        e.W = limEdW; e.H = limRowH; e.X = padX + labelW + gap; e.Y = y
        e.plugincomponent = myHandle; e.Name = 'cfgLim_' .. key; e.textchanged = 'onLimitChanged'
        local h
        if toggle then
            h = scrollBox:Append('Button')
            h.Text = toggle.text; h.TextalignmentH = 'Centre'; h.HasHover = 'Yes'
            h.plugincomponent = myHandle; h.clicked = toggle.clicked; h.BackColor = toggle.color
        else
            h = scrollBox:Append('UIObject')
            h.Text = hint; h.Font = 'Regular20'; h.TextalignmentH = 'Left'
        end
        h.W = 560; h.H = limRowH; h.X = padX + labelW + gap + limEdW + 16; h.Y = y
        return y + limRowH + 10, h
    end
    local function centreLabel()
        return centreAuto and 'AUTO: midpoint of the rig (value ignored)'
                           or 'MANUAL: lateral centre = value at left'
    end
    local function bandLabel()
        return bandAuto and 'AUTO: 3 equal bands on centre (value ignored)'
                         or 'MANUAL: CS = +/- value at left'
    end
    local btnCentre, btnBand
    limY, btnCentre = limitRow('Stage centre', 'origin', nil, limY,
        { text = centreLabel(), clicked = 'onToggleCentre', color = centreAuto and UI_INV_ACT or UI_INV_NORM })
    limY, btnBand = limitRow('Centre band +/-', 'centre', nil, limY,
        { text = bandLabel(), clicked = 'onToggleBand', color = bandAuto and UI_INV_ACT or UI_INV_NORM })
    limY = limitRow('Floor limit',     'floor',  'below this = Floor zone + Ground Row',      limY)
    limY = limitRow('Low limit',       'low',    'below this = Low zone, above = Flown',      limY)
    limY = limitRow('LX tolerance',    'tol',    'closer than this = same LX pipe / boom',    limY)

    local function parentLabel()
        return addParent and 'Nested fixtures: ADD parent position'
                          or 'Nested fixtures: use position as-is'
    end
    local btnParent = scrollBox:Append('Button')
    btnParent.Text  = parentLabel()
    btnParent.H     = axisH
    btnParent.W     = axisW
    btnParent.X     = axisX
    btnParent.Y     = limY
    btnParent.TextalignmentH = 'Centre'
    btnParent.HasHover = 'Yes'
    btnParent.plugincomponent = myHandle
    btnParent.clicked = 'onToggleParent'
    btnParent.BackColor = addParent and UI_INV_ACT or UI_INV_NORM

    -- Footer
    local nextBtn, abortBtn, saveBtn, resetBtn = buildFooter(base, 2, 'Next >', true)
    nextBtn.clicked         = 'onS1Next'
    abortBtn.clicked        = 'onS1Close'
    saveBtn.clicked         = 'onS1Save'
    resetBtn.clicked        = 'onS1Reset'

    base:WaitInit()
    -- No FindBestFocus: leave focus on the command line so console keys work.

    -- Callbacks registered on signalTable
    signalTable.onStageChanged = function(caller)
        currentStage = caller.content or currentStage
    end

    signalTable.onSlotChanged = function(caller)
        currentSlot = caller.content or currentSlot
    end

    signalTable.onLimitChanged = function(caller)
        local key = (caller.Name or ""):match("^cfgLim_(%w+)$")
        if key then limVals[key] = caller.content or limVals[key] end
    end
    signalTable.onToggleCentre = function(caller)
        centreAuto = not centreAuto
        btnCentre.Text = centreLabel()
        btnCentre.BackColor = centreAuto and UI_INV_ACT or UI_INV_NORM
    end
    signalTable.onToggleBand = function(caller)
        bandAuto = not bandAuto
        btnBand.Text = bandLabel()
        btnBand.BackColor = bandAuto and UI_INV_ACT or UI_INV_NORM
    end
    signalTable.onToggleParent = function(caller)
        addParent = not addParent
        btnParent.Text = parentLabel()
        btnParent.BackColor = addParent and UI_INV_ACT or UI_INV_NORM
    end

    signalTable.onCycleLateral = function(caller)
        axisAssign.lateral = nextAxis(axisAssign.lateral)
        btnLateral.Text    = axisButtonLabel('lateral', axisAssign.lateral)
    end

    signalTable.onCycleDepth = function(caller)
        axisAssign.depth = nextAxis(axisAssign.depth)
        btnDepth.Text    = axisButtonLabel('depth', axisAssign.depth)
    end

    signalTable.onCycleHeight = function(caller)
        axisAssign.height = nextAxis(axisAssign.height)
        btnHeight.Text    = axisButtonLabel('height', axisAssign.height)
    end

    signalTable.onInvertLateral = function(caller)
        axisInvert.lateral    = not axisInvert.lateral
        btnInvLateral.Text    = axisInvert.lateral and 'Lateral: INVERTED' or 'Lateral: Normal'
        btnInvLateral.BackColor = axisInvert.lateral and UI_INV_ACT or UI_INV_NORM
        btnLateral.Text       = axisButtonLabel('lateral', axisAssign.lateral)
    end

    signalTable.onInvertDepth = function(caller)
        axisInvert.depth      = not axisInvert.depth
        btnInvDepth.Text      = axisInvert.depth and 'Depth: INVERTED' or 'Depth: Normal'
        btnInvDepth.BackColor = axisInvert.depth and UI_INV_ACT or UI_INV_NORM
        btnDepth.Text         = axisButtonLabel('depth', axisAssign.depth)
    end

    signalTable.onInvertHeight = function(caller)
        axisInvert.height     = not axisInvert.height
        btnInvHeight.Text     = axisInvert.height and 'Height: INVERTED' or 'Height: Normal'
        btnInvHeight.BackColor = axisInvert.height and UI_INV_ACT or UI_INV_NORM
        btnHeight.Text        = axisButtonLabel('height', axisAssign.height)
    end

    -- Validate the dialog; returns the settings table or nil (error printed).
    local function collect()
        local stageName = trim(currentStage)
        local slotN     = math.floor(tonumber(currentSlot) or 0)
        if stageName == '' then
            ErrPrintf('Stage name cannot be empty.')
            return nil
        end
        if slotN < 1 then
            ErrPrintf('Start slot must be 1 or greater.')
            return nil
        end
        -- Warn if any two axes are assigned the same MA3 axis
        if axisAssign.lateral == axisAssign.depth or
           axisAssign.lateral == axisAssign.height or
           axisAssign.depth   == axisAssign.height then
            ErrPrintf('Warning: duplicate axis assignments detected. Check axis mapping.')
        end
        local lim = {}
        -- AUTO values may be left blank (the value is not used)
        local autoKey = { origin = centreAuto, centre = bandAuto }
        local fallback = { origin = 0, centre = tonumber(BUILTIN_D1.centre) }
        for key, label in pairs({ origin = 'Stage centre', centre = 'Centre band', floor = 'Floor limit', low = 'Low limit', tol = 'LX tolerance' }) do
            local txt = trim(limVals[key] or "")
            local v = tonumber(txt)
            if txt == "" and autoKey[key] then
                v = fallback[key]
            elseif txt == "" then
                ErrPrintf('%s is empty -- enter a value%s.', label,
                    (key == 'origin' or key == 'centre') and ' or switch it to AUTO' or '')
                return nil
            elseif v == nil or (v < 0 and key ~= 'origin') then
                ErrPrintf('%s must be a number >= 0 (got "%s").', label, tostring(limVals[key]))
                return nil
            end
            lim[key] = v
        end
        if lim.low <= lim.floor then
            ErrPrintf('Low limit must be higher than the Floor limit.')
            return nil
        end
        if lim.tol <= 0 then
            ErrPrintf('LX tolerance must be greater than 0.')
            return nil
        end
        return {
            centreBand      = lim.centre,
            floorMax        = lim.floor,
            lowMax          = lim.low,
            lxTol           = lim.tol,
            addParentOffset = addParent,
            centreLat       = lim.origin,
            centreAuto      = centreAuto,
            centreBandAuto  = bandAuto,
            stageName      = stageName,
            startSlot      = slotN,
            axisLateral    = axisAssign.lateral:lower(),
            axisDepth      = axisAssign.depth:lower(),
            axisHeight     = axisAssign.height:lower(),
            invertLateral  = axisInvert.lateral,
            invertDepth    = axisInvert.depth,
            invertHeight   = axisInvert.height,
        }
    end

    signalTable.onS1Next = function(caller)
        local r = collect()
        if not r then return end
        result = r
        overlay:ClearUIChildren()
        done = true
    end

    signalTable.onS1Save = function(caller)
        if not collect() then return end
        local ok = saveDefaults("d1", {
            stage = trim(currentStage), slot = trim(currentSlot),
            axLat = axisAssign.lateral, axDep = axisAssign.depth, axHt = axisAssign.height,
            invLat = axisInvert.lateral, invDep = axisInvert.depth, invHt = axisInvert.height,
            origin = trim(limVals.origin or ""), centre = trim(limVals.centre or ""),
            floor = trim(limVals.floor or ""), low = trim(limVals.low or ""), tol = trim(limVals.tol or ""),
            centreAuto = centreAuto, bandAuto = bandAuto, addParent = addParent,
        })
        if ok then
            saveBtn.Text = 'Saved'
            Printf("Dialog 1 defaults saved in the show (save the show file to keep them).")
        end
    end

    signalTable.onS1Reset = function(caller)
        clearDefaults("d1")
        Printf("Dialog 1 defaults reset to built-in values.")
        result = { reopen = true }
        overlay:ClearUIChildren()
        done = true
    end

    signalTable.onS1Close = function(caller)
        overlay:ClearUIChildren()
        done = true
    end

    repeat coroutine.yield() until done
    return result
end

--- Dialog 2: Section toggles + per-type fixture toggles.
--- typeOrder is the sorted list of unique type name strings from the patch.
--- Returns a settings table or nil on abort/close.
local function showGroupOptionsUI(overlay, typeOrder, D)
    local result  = nil
    local done    = false

    -- Checkbox state tables (indexed matching typeOrder and section list)
    local sectionStates = { true, true, true, true }
    local typeStates    = {}
    for i = 1, #typeOrder do typeStates[i] = true end

    -- Scale UI proportionally to fixture type count:
    --   small shows ( <=5 types):  base size, fits without scrolling
    --   medium shows (6-12 types): moderate scale
    --   large shows  (13+ types):  larger rows, scrollbar handles overflow
    -- Width scales with type count up to a cap; height caps at screen limits.
    local typeCount    = #typeOrder
    local cbH          = math.max(55, math.min(80, 44 + typeCount * 2))
    local cbFont       = (cbH >= 70) and 'Regular28' or 'Regular24'
    local divH         = math.floor(cbH * 0.55)
    local divFont      = (cbH >= 70) and 'Regular24' or 'Regular20'
    local winW         = math.max(1120, math.min(1600, 1120 + typeCount * 20))
    local numSectionCBs = 16  -- 5 sections + 4 LX/Ground + 5 cells + 2 options
    local numRows      = numSectionCBs + typeCount
    local contentH     = divH * 4 + numRows * cbH + 30  -- 4 dividers: sections, cells, options, types
    local winH         = math.min(1000, contentH + 140)

    local base          = overlay:Append('BaseInput')
    base.H              = winH
    base.W              = winW
    base.Columns        = 1
    base.Rows           = 3
    base[1][1].SizePolicy = 'Fixed'
    base[1][1].Size     = 55
    base[1][2].SizePolicy = 'Stretch'
    base[1][3].SizePolicy = 'Fixed'
    base[1][3].Size     = 70
    base.AutoClose      = 'No'
    base.CloseOnEscape  = 'Yes'
    base.BackColor      = UI_BG_IDX

    -- Title bar
    local closeBtn      = buildTitleBar(base, 'Create Fixture Groups v' .. PLUGIN_VERSION .. '  |  Step 2 of 2')
    closeBtn.clicked    = 'onS2Close'

    -- Scrollable content area with vertical scrollbar for large shows
    local scrollBox     = base:Append('ScrollBox')
    scrollBox.Name      = 'optScrollBox'
    scrollBox.Anchors   = '0,1'

    local scrollBarV    = base:Append('ScrollBarV')
    scrollBarV.ScrollTarget = scrollBox       -- direct object reference
    scrollBarV.Anchors  = '0,1'

    -- Section divider
    local yCursor        = 0
    local divSec         = scrollBox:Append('UIObject')
    divSec.Text          = '-- Group Sections --'
    divSec.Font          = divFont
    divSec.H             = divH
    divSec.X             = 10
    divSec.Y             = yCursor
    divSec.Anchors       = '0,0,1,0'
    yCursor              = yCursor + divH

    -- Section checkboxes
    local sectionLabels = {
        'Odds + Evens per Type (alternating within each position)',
        'Odds + Evens per Position (LX / Boom / Ground Row)',
        'All Fixtures per Type',
        'Position Zones (SR/CS/SL, US/Mid/DS, Floor/Low/Flown)',
        'Position Zones per Type',
        'LX + Boom Positions (Mixed)',
        'LX + Boom Positions (Per Type)',
        'Ground Row (Mixed)',
        'Ground Row (Per Type)',
        'Cells: all cells per Type',
        'Cells: by index (Cell 1, Cell 2 ...)',
        'Cells: odds / evens',
        'Cells: left / middle / right thirds (by grid position)',
        'Cells: zone, LX, boom + ground row versions',
        'Odds / Evens: simple alternate 1,3,5 (off = symmetric outside-in)',
        'Overwrite Existing Groups',
    }
    -- Initial ticks from D (built-in: first 5 on; saved defaults laid over)
    local sectionDefaults = {}
    for i, id in ipairs(SECTION_IDS) do sectionDefaults[i] = D[id] and 1 or 0 end
    local sectionDividers = { [10] = '-- Sub-fixtures (cells) --', [15] = '-- Options --' }

    local sectionCBs = {}
    for i, lbl in ipairs(sectionLabels) do
        -- Divider before the cells block and before the Overwrite checkbox
        if sectionDividers[i] then
            local divOW      = scrollBox:Append('UIObject')
            divOW.Text       = sectionDividers[i]
            divOW.Font       = divFont
            divOW.H          = divH
            divOW.X          = 10
            divOW.Y          = yCursor
            divOW.Anchors    = '0,0,1,0'
            yCursor          = yCursor + divH
        end
        local cb         = scrollBox:Append('CheckBox')
        cb.Text          = lbl
        cb.TextColor     = 'Global.Text'
        cb.Font          = cbFont
        cb.H             = cbH
        cb.Anchors       = '0,0,1,0'
        cb.State         = sectionDefaults[i] or 1
        cb.X             = 5
        cb.Y             = yCursor
        cb.plugincomponent = myHandle
        cb.clicked       = 'onSectionCBClick'
        sectionCBs[i]    = cb
        yCursor          = yCursor + cbH
    end

    -- Type divider
    local divType        = scrollBox:Append('UIObject')
    divType.Text         = '-- Fixture Types --'
    divType.Font         = divFont
    divType.H            = divH
    divType.X            = 10
    divType.Y            = yCursor
    divType.Anchors      = '0,0,1,0'
    yCursor              = yCursor + divH

    -- Per-type checkboxes
    local typeCBs        = {}
    for i, typeName in ipairs(typeOrder) do
        local cb         = scrollBox:Append('CheckBox')
        cb.Text          = typeName
        cb.TextColor     = 'Global.Text'
        cb.Font          = cbFont
        cb.H             = cbH
        cb.Anchors       = '0,0,1,0'
        cb.State         = 1
        cb.X             = 5
        cb.Y             = yCursor
        cb.plugincomponent = myHandle
        cb.clicked       = 'onTypeCBClick'
        typeCBs[i]       = cb
        yCursor          = yCursor + cbH
    end

    -- Footer buttons
    local createBtn, abortBtn, saveBtn, resetBtn = buildFooter(base, 2, 'Create >', true)
    createBtn.clicked  = 'onS2Create'
    abortBtn.clicked   = 'onS2Close'
    saveBtn.clicked    = 'onS2Save'
    resetBtn.clicked   = 'onS2Reset'

    -- Callbacks
    signalTable.onSectionCBClick = function(caller)
        caller.State = caller.State == 1 and 0 or 1
    end

    signalTable.onTypeCBClick = function(caller)
        caller.State = caller.State == 1 and 0 or 1
    end

    signalTable.onS2Create = function(caller)
        -- Read section states
        local enabledTypes = {}
        for i, typeName in ipairs(typeOrder) do
            if typeCBs[i].State == 1 then
                enabledTypes[typeName] = true
            end
        end
        result = { enabledTypes = enabledTypes }
        for i, id in ipairs(SECTION_IDS) do result[id] = (sectionCBs[i].State == 1) end
        overlay:ClearUIChildren()
        done = true
    end

    signalTable.onS2Save = function(caller)
        local t = {}
        for i, id in ipairs(SECTION_IDS) do t[id] = (sectionCBs[i].State == 1) end
        if saveDefaults("d2", t) then
            saveBtn.Text = 'Saved'
            Printf("Dialog 2 defaults saved in the show (save the show file to keep them).")
        end
    end

    signalTable.onS2Reset = function(caller)
        clearDefaults("d2")
        Printf("Dialog 2 defaults reset to built-in values.")
        result = { reopen = true }
        overlay:ClearUIChildren()
        done = true
    end

    signalTable.onS2Close = function(caller)
        overlay:ClearUIChildren()
        done = true
    end

    repeat coroutine.yield() until done
    return result
end

--- Cell-set picker: one checkbox per cell name in a set that holds cells
--- with different names. Ticked = own groups. Returns decisions
--- (row.key -> true/false), { reopen = true } after "Reset defaults",
--- or nil when closed / aborted.
local function showCellSetsUI(overlay, rows)
    local result, done = nil, false
    local cbH, divH = 60, 40
    local groups = 0
    do
        local last = nil
        for _, r in ipairs(rows) do
            local g = r.typeName .. "|" .. r.setKey
            if g ~= last then groups = groups + 1; last = g end
        end
    end
    local contentH = 90 + groups * divH + #rows * cbH + 20
    local winW     = 1200
    local winH     = math.min(1000, contentH + 140)

    local base          = overlay:Append('BaseInput')
    base.H              = winH
    base.W              = winW
    base.Columns        = 1
    base.Rows           = 3
    base[1][1].SizePolicy = 'Fixed'
    base[1][1].Size     = 55
    base[1][2].SizePolicy = 'Stretch'
    base[1][3].SizePolicy = 'Fixed'
    base[1][3].Size     = 70
    base.AutoClose      = 'No'
    base.CloseOnEscape  = 'Yes'
    base.BackColor      = UI_BG_IDX

    local closeBtn      = buildTitleBar(base, 'Create Fixture Groups v' .. PLUGIN_VERSION .. '  |  Cell sets')
    closeBtn.clicked    = 'onCSClose'

    local scrollBox     = base:Append('ScrollBox')
    scrollBox.Name      = 'csScrollBox'
    scrollBox.Anchors   = '0,1'
    local scrollBarV    = base:Append('ScrollBarV')
    scrollBarV.ScrollTarget = scrollBox
    scrollBarV.Anchors  = '0,1'

    local y = 0
    local hint = scrollBox:Append('UIObject')
    hint.Text           = 'Ticked = own groups.  Unticked = stays with the other cells of that fixture.'
    hint.Font           = 'Regular20'
    hint.TextalignmentH = 'Left'
    hint.H              = 80
    hint.X              = 10
    hint.Y              = y
    hint.Anchors        = '0,0,1,0'
    y = y + 90

    local cbs, last = {}, nil
    for i, r in ipairs(rows) do
        local g = r.typeName .. "|" .. r.setKey
        if g ~= last then
            last = g
            local d = scrollBox:Append('UIObject')
            d.Text    = '-- ' .. r.typeName .. ((r.setLabel and r.setLabel ~= "") and (': ' .. r.setLabel) or '') .. ' --'
            d.Font    = 'Regular20'
            d.H       = divH
            d.X       = 10
            d.Y       = y
            d.Anchors = '0,0,1,0'
            y = y + divH
        end
        local cb         = scrollBox:Append('CheckBox')
        cb.Text          = string.format('%s  (%d cell%s per fixture, e.g. %s)',
                              (r.name ~= "") and r.name or 'unnamed', r.count,
                              (r.count == 1) and '' or 's', tostring(r.example))
        cb.TextColor     = 'Global.Text'
        cb.Font          = 'Regular24'
        cb.H             = cbH
        cb.Anchors       = '0,0,1,0'
        cb.State         = r.state and 1 or 0
        cb.X             = 5
        cb.Y             = y
        cb.plugincomponent = myHandle
        cb.clicked       = 'onCSCheck'
        cbs[i]           = cb
        y = y + cbH
    end

    local nextBtn, abortBtn, saveBtn, resetBtn = buildFooter(base, 2, 'Continue >', true)
    nextBtn.clicked  = 'onCSNext'
    abortBtn.clicked = 'onCSClose'
    saveBtn.clicked  = 'onCSSave'
    resetBtn.clicked = 'onCSReset'

    signalTable.onCSCheck = function(caller)
        caller.State = caller.State == 1 and 0 or 1
    end
    signalTable.onCSNext = function(caller)
        result = {}
        for i, r in ipairs(rows) do result[r.key] = (cbs[i].State == 1) end
        overlay:ClearUIChildren()
        done = true
    end
    signalTable.onCSSave = function(caller)
        -- merge with choices saved for fixture types not in this show
        local t = loadDefaults("cells") or {}
        for i, r in ipairs(rows) do t[r.key] = (cbs[i].State == 1) and "1" or "0" end
        if saveDefaults("cells", t) then
            saveBtn.Text = 'Saved'
            Printf("Cell-set choices saved in the show (save the show file to keep them).")
        end
    end
    signalTable.onCSReset = function(caller)
        clearDefaults("cells")
        Printf("Cell-set choices reset to the automatic defaults.")
        result = { reopen = true }
        overlay:ClearUIChildren()
        done = true
    end
    signalTable.onCSClose = function(caller)
        overlay:ClearUIChildren()
        done = true
    end

    repeat coroutine.yield() until done
    return result
end

-------------------------------------------------------------------------------
-- LAYER 2 -- Fixture attribute resolvers
-------------------------------------------------------------------------------

--- Return the fixture type name string.
--- Return the fixture type name from fix.fixturetype.name.
local function resolveFixtureType(fix)
    local ft = fix.fixturetype
    if ft then
        local n = trim(ft.name)
        if n ~= "" then return n end
    end
    return "Unknown Type"
end

--- Return the manufacturer name from fix.fixturetype.manufacturer.
--- Confirmed working from diagnostic dump -- returns e.g. "Elation", "Generic".
local function resolveFixtureManufacturer(fix)
    local ft = fix.fixturetype
    if ft then
        local m = trim(ft.manufacturer)
        if m ~= "" then return m end
    end
    return ""
end

--- Return true if this fixture is a parent container (Grouping).
--- Strategy: check CANHAVECHILDREN on the fixture type handle, which is the
--- most reliable structural flag. The Lua accessor may return a boolean or the
--- string "Yes"/"No" depending on the build, so we test both forms.
--- As a safety net we also catch the known type names "Grouping" and "Geometry"
--- by string, since these are MA3 built-in types that will never be real
--- controllable fixtures.
local function isGroupingContainer(fix)
    local ft = fix.fixturetype
    if ft then
        -- Test CANHAVECHILDREN -- handle both boolean true and string "Yes"
        local v = ft.canhavechildren
        if v == true then return true end
        if type(v) == "string" and v:lower() == "yes" then return true end

        -- Safety net: catch built-in non-fixture type names by string
        local typeName = trim(ft.name):lower()
        if typeName == "grouping" or typeName == "geometry" then return true end
    end
    return false
end

--- Return true if this fixture should be excluded from groups.
--- Two conditions trigger exclusion:
---   1. CANHAVECHILDREN = "Yes" -- the fixture is a Grouping parent container.
---   2. Manufacturer == "environmental" (case-insensitive) -- the fixture is a
---      3D environment object (floor, truss, scenic element, camera, etc.)
---      MA3 uses this manufacturer field consistently for all such objects.
local function exclusionReason(fix)
    local ft = fix.fixturetype
    if ft then
        local v = ft.canhavechildren
        if v == true or (type(v) == "string" and v:lower() == "yes") then
            return "fixture type CanHaveChildren = Yes"
        end
        local typeName = trim(ft.name):lower()
        if typeName == "grouping" or typeName == "geometry" then return "Grouping / Geometry type" end
    end
    if resolveFixtureManufacturer(fix):lower() == "environmental" then return "manufacturer Environmental" end
    return nil
end

local function isExcluded(fix)
    return exclusionReason(fix) ~= nil
end

--- Local position of one fixture handle (numbers; nil if unreadable).
local function localPosition(h)
    local x = tonumber(h.posx)
    local y = tonumber(h.posy)
    local z = tonumber(h.posz)
    if x == nil or y == nil or z == nil then return nil end
    return x, y, z
end

--- Parent FIXTURE of a fixture handle (truss / grouping), or nil when the
--- fixture sits at the top level of the patch.
local function parentFixture(h)
    local ok, p = pcall(function() return h:Parent() end)
    if not ok or p == nil then return nil end
    local okT, ft = pcall(function() return p.fixturetype end)
    if okT and ft ~= nil then return p end
    return nil
end

-- Nesting diagnostics for the current run
local NEST = { count = 0, rotated = 0, sampleShown = false }

local function nonZeroRotation(h)
    for _, prop in ipairs({ "rotx", "roty", "rotz" }) do
        local ok, v = pcall(function() return tonumber(h[prop]) end)
        if ok and v and math.abs(v) > 0.001 then return true end
    end
    return false
end

--- World position of a fixture. With CFG.addParentOffset the positions of all
--- parent fixtures are added (translation only). Returns nil when the result
--- is 0,0,0 (treated as unpositioned) or unreadable.
local function resolveFixturePosition(fix)
    local x, y, z = localPosition(fix)
    if x == nil then return nil end
    local p = parentFixture(fix)
    if p then
        NEST.count = NEST.count + 1
        if CFG.addParentOffset then
            local depth, cur = 0, p
            while cur and depth < 10 do
                local px, py, pz = localPosition(cur)
                if px then
                    if not NEST.sampleShown then
                        NEST.sampleShown = true
                        Printf("  Nested: Fixture %s local (%.2f, %.2f, %.2f) + parent \"%s\" (%.2f, %.2f, %.2f)",
                            tostring(fix.fid), x, y, z, tostring(cur.name), px, py, pz)
                    end
                    x, y, z = x + px, y + py, z + pz
                end
                if nonZeroRotation(cur) then NEST.rotated = NEST.rotated + 1 end
                cur = parentFixture(cur)
                depth = depth + 1
            end
        end
    end
    -- 0,0,0 is the default for fixtures that were never placed
    if x == 0 and y == 0 and z == 0 then return nil end
    return x, y, z
end

-------------------------------------------------------------------------------
-- LAYER 3 -- Fixture collection and sorting
-------------------------------------------------------------------------------

-- Sub-fixture (cell) discovery. Cells are addressed by child position:
-- "<FID>.<n>", nested "<FID>.<n>.<m>" ... The first cell address (and the
-- first nested one) is checked with ObjectList; if it doesn't resolve, that
-- level is disabled for the run instead of storing wrong groups.
local CELLS = { checked = false, ok = false, nestedChecked = false, nestedOk = false,
                fixtures = 0, nestedFixtures = 0, skippedHandles = 0, splitSets = 0,
                upper = 0, upperExample = nil }

local function kidsOf(h)
    local ok, kids = pcall(function() return h:Children() end)
    if ok and kids and #kids > 0 then return kids end
    return nil
end

local function checkAddress(addr, what)
    local okO, lst = pcall(ObjectList, "Fixture " .. addr)
    local good = okO and lst ~= nil and #lst > 0
    Printf("  Sub-fixtures: %s address \"Fixture %s\" %s", what, addr, good and "resolves" or "DID NOT resolve")
    return good
end

local function cleanName(s)
    s = trim(tostring(s or "")):gsub('"', "")
    return s
end

--- Patch name without the brackets MA3 shows on default names:
--- "[Single Back Plate M3]" -> "Single Back Plate M3".
local function labelName(s)
    s = cleanName(s):gsub("^%[", ""):gsub("%]$", "")
    return trim(s)
end

--- Name of a cell without brackets and a trailing " <number>":
--- "[RGBW Pixel 12]" -> "RGBW Pixel", "[SparkLED]" -> "SparkLED",
--- "[Beam Module M3]" -> "Beam Module M3" (M3 is part of the name).
local function baseCellName(s)
    s = labelName(s):gsub("%s+%d+$", "")
    return trim(s)
end

--- Walk a fixture's sub-fixtures. Leaves directly under a node form one SET;
--- a sub-fixture that has its own children starts a new set (keyed by its
--- path, e.g. "3" or "3.2"). Only the DEEPEST level counts as cells: sets
--- above it (e.g. JDC1 401.1 / 401.2 next to 401.3.x / 401.4.x) are left
--- out. Splitting a set by cell name happens later (cellSplitRows / picker /
--- applyCellSplits); each set keeps names = base name per cell for that.
--- Returns:
---   sets : ordered list { key, name, cells = {addr...}, names = {base...},
---          parent = <addr>, downs = 1 }
---          (key "" = the fixture's own leaf sub-fixtures; parents excluded;
---           parent = address that "Down" is applied to for the native grid)
--- or nil when the fixture has no sub-fixtures.
local function scanSubFixtures(fix, fid)
    if fid <= 0 or (CELLS.checked and not CELLS.ok) then return nil end
    local kids = kidsOf(fix)
    if not kids then return nil end

    if not CELLS.checked then
        CELLS.checked = true
        local k = kids[1]
        Printf("  Sub-fixtures: Fixture %d has %d sub-fixture(s); child 1 class=%s name=%s",
            fid, #kids, tostring(select(2, pcall(function() return k:GetClass() end))),
            tostring(select(2, pcall(function() return k.name end))))
        CELLS.ok = checkAddress(tostring(fid) .. ".1", "first")
        if not CELLS.ok then
            ErrPrintf("  Cell groups disabled for this run.")
            return nil
        end
    end

    local sets, byKey = {}, {}
    local function setFor(key, name, parent)
        if not byKey[key] then
            byKey[key] = { key = key, name = name, cells = {}, names = {}, raw = {},
                           parent = parent, downs = 1, depth = 0 }
            sets[#sets + 1] = byKey[key]
        end
        return byKey[key]
    end
    local function addLeaf(key, parent, a, k, depth)
        local s = setFor(key, nil, parent)
        local nm = select(2, pcall(function() return k.name end))
        s.cells[#s.cells + 1] = a
        s.names[#s.names + 1] = baseCellName(nm)
        s.raw[#s.raw + 1] = tostring(nm)
        if depth > s.depth then s.depth = depth end
    end
    setFor("", nil, tostring(fid))   -- top-level set first

    local function walk(node, addr, key, depth)
        local ch = kidsOf(node)
        if not ch then return end
        for i, k in ipairs(ch) do
            local a = addr .. "." .. i
            local kkey = (key == "") and tostring(i) or (key .. "." .. i)
            local grand = (depth < 5) and kidsOf(k) or nil
            if grand then
                if not CELLS.nestedChecked then
                    CELLS.nestedChecked = true
                    CELLS.nestedOk = checkAddress(a .. ".1", "nested")
                    if not CELLS.nestedOk then
                        ErrPrintf("  Nested cell sets disabled -- only top-level cells will be used.")
                    end
                end
                if CELLS.nestedOk then
                    setFor(kkey, labelName(select(2, pcall(function() return k.name end))), a)
                    walk(k, a, kkey, depth + 1)
                else
                    -- nested addressing failed: use the sub-fixture itself as a cell
                    addLeaf(key, addr, a, k, depth)
                end
            else
                addLeaf(key, addr, a, k, depth)
            end
        end
    end
    walk(fix, tostring(fid), "", 1)

    -- cells = the deepest level only; sets above it are left out (logged)
    local maxDepth = 0
    for _, s in ipairs(sets) do if s.depth > maxDepth then maxDepth = s.depth end end
    local deep = {}
    for _, s in ipairs(sets) do
        if #s.cells > 0 and s.depth < maxDepth then
            CELLS.upper = CELLS.upper + #s.cells
            if not CELLS.upperExample then
                CELLS.upperExample = s.cells[1] .. " " .. (s.raw[1] or "")
            end
        elseif #s.cells > 0 then
            deep[#deep + 1] = s
        end
    end

    for _, s in ipairs(deep) do s.raw = nil end

    -- drop empty sets
    local out = {}
    for _, s in ipairs(deep) do if #s.cells > 0 then out[#out + 1] = s end end
    if #out == 0 then return nil end
    CELLS.fixtures = CELLS.fixtures + 1
    if #out > 1 or out[1].key ~= "" then CELLS.nestedFixtures = CELLS.nestedFixtures + 1 end
    return { sets = out }
end

--- Cell-set split candidates: per fixture type and cell set, the distinct
--- cell names (only sets that hold 2+ names). state = default "own groups":
--- a name with fewer than half the cells of the most common name (1
--- SparkLED vs 19 pixels). The most common name, and names about as common
--- (3 uniquely named Paladin cells), stay together by default.
--- Row: { key = "<type>|<set key>|<name>", typeName, setKey, setLabel, name,
---        count (cells per fixture), example (first address), state }
local function cellSplitRows(list)
    local rows, seen = {}, {}
    for _, f in ipairs(list) do
        if f.cellTree then
            for _, s in ipairs(f.cellTree.sets) do
                local sk = f.typeName .. "|" .. s.key
                if not seen[sk] and s.names then
                    seen[sk] = true
                    local count, order, first = {}, {}, {}
                    for i, nm in ipairs(s.names) do
                        if not count[nm] then count[nm] = 0; order[#order + 1] = nm; first[nm] = s.cells[i] end
                        count[nm] = count[nm] + 1
                    end
                    if #order > 1 then
                        local top = 0
                        for _, nm in ipairs(order) do if count[nm] > top then top = count[nm] end end
                        for _, nm in ipairs(order) do
                            rows[#rows + 1] = { key = sk .. "|" .. nm, typeName = f.typeName,
                                setKey = s.key, setLabel = s.name, name = nm, count = count[nm],
                                example = first[nm], state = (count[nm] * 2 < top) }
                        end
                    end
                end
            end
        end
    end
    return rows
end

--- Split every fixture's cell sets by the picker decisions (key -> true =
--- own set "<key>~<name>"). Returns the list of names split off, per type.
local function applyCellSplits(list, decisions)
    local splitNames, seenName = {}, {}
    for _, f in ipairs(list) do
        if f.cellTree then
            local out = {}
            for _, s in ipairs(f.cellTree.sets) do
                out[#out + 1] = s
                if s.names then
                    local keep, extra, order = {}, {}, {}
                    for i, a in ipairs(s.cells) do
                        local nm = s.names[i]
                        local k = f.typeName .. "|" .. s.key .. "|" .. nm
                        if decisions[k] then
                            if not extra[nm] then
                                local lbl = (nm ~= "") and nm or "unnamed"
                                if s.name and s.name ~= "" then lbl = s.name .. " " .. lbl end
                                extra[nm] = { key = s.key .. "~" .. nm, name = lbl, cells = {},
                                              parent = s.parent, downs = s.downs or 1 }
                                order[#order + 1] = nm
                                if not seenName[k] then
                                    seenName[k] = true
                                    splitNames[#splitNames + 1] = f.typeName .. ": " .. lbl
                                end
                            end
                            table.insert(extra[nm].cells, a)
                        else
                            keep[#keep + 1] = a
                        end
                    end
                    s.cells = keep
                    s.names = nil
                    for _, nm in ipairs(order) do out[#out + 1] = extra[nm] end
                end
            end
            local final = {}
            for _, s in ipairs(out) do if #s.cells > 0 then final[#final + 1] = s end end
            f.cellTree.sets = final
            if #final == 0 then f.cellTree = nil end
        end
    end
    return splitNames
end

--- A handle whose parent is a real (non-grouping) fixture is itself a cell.
--- Only counted for the log -- collection behaviour is unchanged.
local function isSubFixtureHandle(fix)
    local p = parentFixture(fix)
    return p ~= nil and not isGroupingContainer(p)
end

--- Map a raw x/y/z to a semantic axis value using AXIS_MAP.
local function pickAxis(axis, invert, x, y, z)
    local v = (axis == 'x' and x) or (axis == 'y' and y) or z
    if invert then v = -v end
    return v
end

--- Use ObjectList to get all fixtures, filter to stageName, skip excluded types.
--- Returns a list of plain tables:
---   { fid, name, typeName, x, y, z, lat, dep, ht }  (x/y/z nil = unpositioned)
local function collectFixtures(stageName)
    NEST.count, NEST.rotated, NEST.sampleShown = 0, 0, false
    CELLS.checked, CELLS.ok, CELLS.nestedChecked, CELLS.nestedOk = false, false, false, false
    CELLS.fixtures, CELLS.nestedFixtures, CELLS.skippedHandles, CELLS.splitSets = 0, 0, 0, 0
    CELLS.upper, CELLS.upperExample = 0, nil
    local allFixtures = ObjectList("Fixture 1 Thru 99999")
    if allFixtures == nil then
        return {}, 0
    end

    local list        = {}
    local skipped     = 0
    local targetLower = stageName:lower()
    local excluded, exclOrder = {}, {}

    for _, fix in pairs(allFixtures) do
        local fixStage = ""
        if fix.stage then
            fixStage = trim(fix.stage.name):lower()
        end

        if fixStage == targetLower then
            -- log only: cell handles returned by ObjectList are kept as before
            if isSubFixtureHandle(fix) then CELLS.skippedHandles = CELLS.skippedHandles + 1 end
            local why = exclusionReason(fix)
            if why then
                local tn = resolveFixtureType(fix) .. " -- " .. why
                if not excluded[tn] then excluded[tn] = 0; exclOrder[#exclOrder + 1] = tn end
                excluded[tn] = excluded[tn] + 1
            else
                local fid  = tonumber(fix.fid) or 0
                local name = trim(fix.name)
                if name == "" then name = "Fixture_" .. fid end
                local x, y, z = resolveFixturePosition(fix)
                local _x, _y, _z = x or 0, y or 0, z or 0
                table.insert(list, {
                    fid      = fid,
                    name     = name,
                    typeName = resolveFixtureType(fix),
                    x        = x,
                    y        = y,
                    z        = z,
                    rawLat = x and pickAxis(AXIS_MAP.lateral, false, _x, _y, _z) or nil, -- MA coordinate
                    lat = 0,  -- set below once the stage centre is known: SR(-) .. SL(+)
                    dep = pickAxis(AXIS_MAP.depth,   AXIS_MAP.invertDepth,   _x, _y, _z), -- US(-) .. DS(+)
                    ht  = pickAxis(AXIS_MAP.height,  AXIS_MAP.invertHeight,  _x, _y, _z), -- floor(0) .. flown(+)
                    cellTree = scanSubFixtures(fix, fid),
                })
            end
        else
            skipped = skipped + 1
        end
    end

    for _, tn in ipairs(exclOrder) do
        Printf("  Excluded: %d x %s", excluded[tn], tn)
    end

    -- Lateral relative to the stage centre (manual value or rig midpoint)
    local centre = CFG.centreLat
    if CFG.centreAuto then
        local lo, hi = math.huge, -math.huge
        for _, f in ipairs(list) do
            if f.rawLat then
                if f.rawLat < lo then lo = f.rawLat end
                if f.rawLat > hi then hi = f.rawLat end
            end
        end
        centre = (lo <= hi) and (lo + hi) / 2 or 0
    end
    for _, f in ipairs(list) do
        if f.rawLat then
            local v = f.rawLat - centre
            if AXIS_MAP.invertLateral then v = -v end
            f.lat = v
        end
    end
    Printf("  Stage centre (lateral %s): %.3f m%s", AXIS_MAP.lateral:upper(), centre,
        CFG.centreAuto and "  (auto: midpoint of the rig)" or "")

    if CELLS.fixtures > 0 then
        Printf("  %d fixture(s) have sub-fixtures (cells), %d with nested sub-fixtures.",
            CELLS.fixtures, CELLS.nestedFixtures)
    end
    if CELLS.upper > 0 then
        Printf("  %d sub-fixture(s) above the deepest cell level left out of cell groups (e.g. %s).",
            CELLS.upper, CELLS.upperExample or "?")
    end
    if CELLS.skippedHandles > 0 then
        Printf("  Note: ObjectList also returned %d cell handle(s) (parent is a fixture, not a grouping).", CELLS.skippedHandles)
    end
    if NEST.count > 0 then
        Printf("  %d fixture(s) are nested under a parent fixture -- parent offset %s.",
            NEST.count, CFG.addParentOffset and "ADDED" or "ignored")
        if NEST.rotated > 0 then
            ErrPrintf("  WARNING: %d parent(s) are rotated; rotation is NOT applied to child positions.", NEST.rotated)
        end
    end
    return list, skipped
end

--- Sort fixture list in-place by FID ascending.
local function sortByFID(list)
    table.sort(list, function(a, b) return a.fid < b.fid end)
end

-------------------------------------------------------------------------------
-- LAYER 3 -- Group store command
-------------------------------------------------------------------------------

--- Groups are PLANNED first (nothing stored), then confirmed and executed.
--- PLAN entries: { name, fids, slot, overwrite, grid }
---   grid (cell groups only) = { parents = {addr...}, downs = n }: store from
---   the native selection grid ("Fixture <parents>" + "Down" x n), then remove
---   the cells that are not in fids. nil = plain list selection.
local PLAN = {}

--- Add a group to the plan. Returns the next slot to use: slotIndex + 1
--- when a new slot was taken, slotIndex unchanged when an existing group is
--- overwritten (overwrite mode + name already in the pool) or the group is empty.
local function storeGroup(groupName, fidList, slotIndex, overwrite, grid)
    if #fidList == 0 then
        Printf("  (skipping empty group: %s)", groupName)
        return slotIndex
    end
    local tag = grid and "  [grid]" or ""
    local exist = overwrite and existingByName[groupName] or nil
    if exist then
        table.insert(PLAN, { name = groupName, fids = fidList, slot = exist, overwrite = true, grid = grid })
        Printf("  Plan: overwrite slot %d \"%s\"  (%d fixture(s))%s", exist, groupName, #fidList, tag)
        return slotIndex
    end
    table.insert(PLAN, { name = groupName, fids = fidList, slot = slotIndex, overwrite = false, grid = grid })
    usedSlots[slotIndex] = true
    Printf("  Plan: slot %d -> \"%s\"  (%d fixture(s))%s", slotIndex, groupName, #fidList, tag)
    return slotIndex + 1
end

--- Grid spec for a cell group from its members { parent, downs, n }
--- (n = cells of that member in the group). nil = store as a plain list:
--- no member has more than one cell (e.g. "Cell N"), or the members need a
--- different number of "Down" steps.
local function gridSpec(members)
    local parents, seen, downs, multi = {}, {}, nil, false
    for _, m in ipairs(members) do
        if m.n > 0 and m.parent then
            if downs == nil then downs = m.downs elseif downs ~= m.downs then return nil end
            if m.n > 1 then multi = true end
            if not seen[m.parent] then seen[m.parent] = true; parents[#parents + 1] = m.parent end
        end
    end
    if not multi or #parents == 0 then return nil end
    return { parents = parents, downs = downs or 1 }
end

--- Walk the current selection: map addr -> { x, y } and addrs in order.
--- Addresses come from the sub-fixture handle ("Fixture 501.1" -> "501.1").
local function readSelectionGrid()
    local map, order = {}, {}
    local okF, idx, x, y = pcall(SelectionFirst)
    local guard = 0
    while okF and idx and guard < 100000 do
        guard = guard + 1
        local okS, h = pcall(GetSubfixture, idx)
        local a = okS and h and tostring(h):match("^Fixture%s+([%d%.]+)") or nil
        if a then
            a = a:gsub("%.$", "")
            if not map[a] then order[#order + 1] = a end
            map[a] = { x = tonumber(x) or 0, y = tonumber(y) or 0 }
        end
        okF, idx, x, y = pcall(SelectionNext, idx)
    end
    return map, order
end

local SELECT_CHUNK = 1200   -- max characters of fixture addresses per command

--- Store every planned group, with a progress bar. Yields between groups so
--- the console stays responsive.
--- Select a list of addresses in chunks. Long selections are sent as
--- several "Fixture a+b+..." commands (one very long command line failed
--- with "Illegal number"); the selection accumulates until ClearAll.
local function selectChunked(addrs)
    local chunk, len = {}, 0
    local function flush()
        if #chunk > 0 then Cmd("Fixture " .. table.concat(chunk, "+")) end
        chunk, len = {}, 0
    end
    for _, a in ipairs(addrs) do
        local s = tostring(a)
        if len + #s + 1 > SELECT_CHUNK then flush() end
        chunk[#chunk + 1] = s
        len = len + #s + 1
    end
    flush()
end

local function storeCmd(g)
    if g.overwrite then return string.format('Store Group %d /o /nc', g.slot) end
    return string.format('Store Group %d "%s" /nc', g.slot, g.name)
end

--- Store a cell group from the native selection grid. Returns false (nothing
--- stored) when some planned cells are not in the "Down" selection.
local function storeGridGroup(g)
    Cmd("ClearAll")
    selectChunked(g.grid.parents)
    for _ = 1, g.grid.downs do Cmd("Down") end
    local map, order = readSelectionGrid()
    local keep, missing = {}, 0
    for _, a in ipairs(g.fids) do
        local s = tostring(a)
        keep[s] = true
        if not map[s] then missing = missing + 1 end
    end
    if missing > 0 then
        ErrPrintf("  \"%s\": %d cell(s) not in the grid selection -- stored as a plain list.", g.name, missing)
        return false
    end
    Cmd(storeCmd(g))
    local remove = {}
    for _, a in ipairs(order) do if not keep[a] then remove[#remove + 1] = a end end
    if #remove > 0 then
        Cmd("ClearAll")
        selectChunked(remove)
        Cmd(string.format('Store Group %d /Remove /nc', g.slot))
    end
    -- verify: recall the group and count
    Cmd("ClearAll")
    Cmd(string.format('Group %d', g.slot))
    local okC, cnt = pcall(SelectionCount)
    if okC and tonumber(cnt) and tonumber(cnt) ~= #g.fids then
        ErrPrintf("  \"%s\": group holds %s cell(s), expected %d -- check this group.", g.name, tostring(cnt), #g.fids)
    end
    return true
end

local function executePlan()
    local okP, prog = pcall(StartProgress, "Create Fixture Groups")
    if not okP then prog = nil end
    if prog then pcall(SetProgressRange, prog, 0, #PLAN); pcall(SetProgress, prog, 0) end
    local nGrid, nFallback = 0, 0
    for i, g in ipairs(PLAN) do
        if prog then pcall(SetProgressText, prog, g.name) end
        local done = false
        if g.grid then
            done = storeGridGroup(g)
            if done then nGrid = nGrid + 1 else nFallback = nFallback + 1 end
        end
        if not done then
            -- plain list: SelectionCount() below the address count = missing units
            Cmd("ClearAll")
            selectChunked(g.fids)
            local okC, cnt = pcall(SelectionCount)
            if okC and tonumber(cnt) and tonumber(cnt) < #g.fids then
                ErrPrintf("  \"%s\": selected %s of %d -- check this group.", g.name, tostring(cnt), #g.fids)
            end
            Cmd(storeCmd(g))
        end
        if prog then pcall(SetProgress, prog, i) end
        if i % 5 == 0 then coroutine.yield() end
    end
    Cmd("ClearAll")
    if prog then pcall(StopProgress, prog) end
    if nGrid + nFallback > 0 then
        Printf("  Cell groups stored with native grid: %d  (plain list fallback: %d)", nGrid, nFallback)
    end
end

-------------------------------------------------------------------------------
-- LAYER 4 -- Section B/C helpers
-------------------------------------------------------------------------------

--- Bucket fixtures by type name (alpha sorted), producing per-type FID lists
--- and per-type odd/even splits using outside-in Y-position pairing.
---
--- Outside-in logic:
---   1. Sort fixtures of each type by Y position (most negative = SR = outermost)
---   2. Pair them: position 1+N, 2+(N-1), 3+(N-2), ...
---   3. Odds  = first fixture of each pair (outermost)
---   4. Evens = second fixture of each pair (inner partner)
---
--- Fixtures without Y position data fall back to FID order.
--- Returns: typeOrder, typeMap, oddMap, evenMap
local function buildTypeMap(list)
    -- Build a lookup of fix data by fid for Y-position access
    local fixByFid = {}
    for _, fix in ipairs(list) do
        fixByFid[fix.fid] = fix
    end

    local typeOrder = {}
    local typeMap   = {}

    for _, fix in ipairs(list) do
        local tn = fix.typeName
        if not typeMap[tn] then
            typeMap[tn] = {}
            table.insert(typeOrder, tn)
        end
        table.insert(typeMap[tn], fix.fid)
    end

    table.sort(typeOrder)

    local oddMap  = {}
    local evenMap = {}
    for _, tn in ipairs(typeOrder) do
        oddMap[tn]  = {}
        evenMap[tn] = {}

        -- Sort this type's fixtures by Y position (SR=-ve to SL=+ve)
        -- Fixtures with no Y data sort by FID as fallback
        local fids = {}
        for _, fid in ipairs(typeMap[tn]) do
            table.insert(fids, fid)
        end
        table.sort(fids, function(a, b)
            local fa = fixByFid[a]
            local fb = fixByFid[b]
            local ya = (fa and fa.lat) or 0
            local yb = (fb and fb.lat) or 0
            if ya ~= yb then return ya < yb end  -- SR (negative) first
            return a < b                           -- FID tiebreak
        end)

        -- Outside-in pairing by physical lat position (SR to SL).
        -- fids sorted SR-first (most negative lat first).
        --
        -- Walk inward from both ends simultaneously, alternating which
        -- group each full pair belongs to:
        --   Pair 1 (positions 1+N)   -> Odds
        --   Pair 2 (positions 2+N-1) -> Evens
        --   Pair 3 (positions 3+N-2) -> Odds  ... etc.
        --
        -- Both fixtures of a pair go to the same group, SR-side first.
        -- If odd total, the lone centre fixture joins the last group used.
        --
        -- Example (10 fixtures):
        --   Pair1->Odds:  1,10  Pair2->Evens: 2,9  Pair3->Odds: 3,8
        --   Pair4->Evens: 4,7   Pair5->Odds:  5,6
        --   Odds={1,10,3,8,5,6}  Evens={2,9,4,7}
        local lo, hi    = 1, #fids
        local pairIndex = 1
        while lo <= hi do
            local targetOdd = (pairIndex % 2 == 1)
            local target = targetOdd and oddMap[tn] or evenMap[tn]
            if lo == hi then
                -- Lone centre fixture -- same group as current pair
                table.insert(target, fids[lo])
            else
                table.insert(target, fids[lo])  -- SR-side first
                table.insert(target, fids[hi])  -- SL-side second
            end
            lo = lo + 1
            hi = hi - 1
            pairIndex = pairIndex + 1
        end
    end

    -- Sort each odd/even list by physical lat position (SR to SL)
    -- so selection order is linear across the stage even though
    -- fixtures were assigned by outside-in pairing logic.
    for _, tn in ipairs(typeOrder) do
        table.sort(oddMap[tn], function(a, b)
            local la = (fixByFid[a] and fixByFid[a].lat) or 0
            local lb = (fixByFid[b] and fixByFid[b].lat) or 0
            if la ~= lb then return la < lb end
            return a < b
        end)
        table.sort(evenMap[tn], function(a, b)
            local la = (fixByFid[a] and fixByFid[a].lat) or 0
            local lb = (fixByFid[b] and fixByFid[b].lat) or 0
            if la ~= lb then return la < lb end
            return a < b
        end)
    end

    return typeOrder, typeMap, oddMap, evenMap
end

-------------------------------------------------------------------------------
-- LAYER 4 -- Section D helpers (physical position zones)
-------------------------------------------------------------------------------

--- Split list into positioned (x ~= nil) and count of unpositioned.
local function partitionByPosition(list)
    local positioned   = {}
    local unpositioned = 0
    for _, fix in ipairs(list) do
        if fix.x ~= nil then
            table.insert(positioned, fix)
        else
            unpositioned = unpositioned + 1
        end
    end
    return positioned, unpositioned
end

-- Zone labels in pool order, with the axis each belongs to.
local ZONES = {
    { label = "SR",        axis = "lat" },
    { label = "CS",        axis = "lat" },
    { label = "SL",        axis = "lat" },
    { label = "US",        axis = "dep" },
    { label = "Mid Stage", axis = "dep" },
    { label = "DS",        axis = "dep" },
    { label = "Floor",     axis = "ht"  },
    { label = "Low",       axis = "ht"  },
    { label = "Flown",     axis = "ht"  },
}

-- Fixtures this close to the centre-band edge count as centre, so mirrored
-- fixtures are never split by small placement differences.
local EDGE_EPS = 0.05

-- Forward declaration (defined in the Section E helpers below)
local components

--- Depth zones by rig POSITION LINES: fixtures within the LX tolerance in depth
--- form one line (a pipe, the ground row, a boom pair...). Lines are ordered
--- upstage -> downstage and split into thirds by line count, so a pipe is
--- never split between two zones.
--- Returns map fid -> "US" / "Mid Stage" / "DS", or nil when < 2 lines.
local function depthZoneMap(positioned)
    local lines = components(positioned, "dep", "dep", CFG.lxTol)
    if #lines < 2 then return nil, #lines end
    local means = {}
    for i, l in ipairs(lines) do
        local s = 0
        for _, f in ipairs(l) do s = s + f.dep end
        means[i] = { line = l, dep = s / #l }
    end
    table.sort(means, function(a, b) return a.dep < b.dep end)
    local n = #means
    local nEdge = math.floor(n / 3 + 0.5)
    if nEdge < 1 then nEdge = 1 end
    local map = {}
    for i, m in ipairs(means) do
        local label
        if i <= nEdge then label = "US"
        elseif i > n - nEdge then label = "DS"
        else label = "Mid Stage" end
        for _, f in ipairs(m.line) do map[f.fid] = label end
    end
    return map, n, means
end

--- Zone labels for one fixture: lateral / depth / height.
local function fixtureZones(f, depthMap)
    local lat
    if f.lat < -(CFG.centreBand + EDGE_EPS) then lat = "SR"
    elseif f.lat > CFG.centreBand + EDGE_EPS then lat = "SL"
    else lat = "CS" end

    local dep = depthMap and depthMap[f.fid] or nil

    local ht
    if f.ht < CFG.floorMax then ht = "Floor"
    elseif f.ht < CFG.lowMax then ht = "Low"
    else ht = "Flown" end

    return { lat = lat, dep = dep, ht = ht }
end

--- Order fixtures inside a group: SR -> SL, then US -> DS, then FID.
local function positionalSort(fixes)
    table.sort(fixes, function(a, b)
        if math.abs(a.lat - b.lat) > 0.001 then return a.lat < b.lat end
        if math.abs(a.dep - b.dep) > 0.001 then return a.dep < b.dep end
        return a.fid < b.fid
    end)
end

--- Classify fixtures into zone buckets. An axis whose fixtures all fall into
--- one zone is skipped (that group would just repeat the whole set).
--- Returns an ordered list of { label, fids }.
local function classifyZones(fixes, depthMap, logPrefix)
    local buckets = {}
    for _, z in ipairs(ZONES) do buckets[z.label] = {} end
    for _, f in ipairs(fixes) do
        local zs = fixtureZones(f, depthMap)
        if zs.lat then table.insert(buckets[zs.lat], f) end
        if zs.dep then table.insert(buckets[zs.dep], f) end
        if zs.ht  then table.insert(buckets[zs.ht],  f) end
    end
    -- count non-empty zones per axis
    local used = { lat = 0, dep = 0, ht = 0 }
    for _, z in ipairs(ZONES) do
        if #buckets[z.label] > 0 then used[z.axis] = used[z.axis] + 1 end
    end
    local names = { lat = "Lateral", dep = "Depth", ht = "Height" }
    for axis, n in pairs(used) do
        if n <= 1 and logPrefix then
            Printf("  %s%s: all fixtures in one zone -- skipped.", logPrefix, names[axis])
        end
    end
    local out = {}
    for _, z in ipairs(ZONES) do
        local b = buckets[z.label]
        if #b > 0 and used[z.axis] > 1 then
            positionalSort(b)
            local fids = {}
            for _, f in ipairs(b) do fids[#fids + 1] = f.fid end
            table.insert(out, { label = z.label, fids = fids })
        end
    end
    return out
end

-------------------------------------------------------------------------------
-- LAYER 4b -- Section E helpers (ground row, booms, LX positions)
-------------------------------------------------------------------------------

--- Connected components: two fixtures are linked when |a1-b1| <= tol and
--- |a2-b2| <= tol (keys k1, k2). Sweep on k1 keeps it near-linear.
--- Returns a list of components (each a list of fixtures).
components = function(fixes, k1, k2, tol)
    local n = #fixes
    if n == 0 then return {} end
    local idx = {}
    for i = 1, n do idx[i] = i end
    table.sort(idx, function(a, b) return fixes[a][k1] < fixes[b][k1] end)
    local parent = {}
    for i = 1, n do parent[i] = i end
    local function find(i)
        while parent[i] ~= i do
            parent[i] = parent[parent[i]]
            i = parent[i]
        end
        return i
    end
    for a = 1, n do
        local fa = fixes[idx[a]]
        local b = a + 1
        while b <= n and fixes[idx[b]][k1] - fa[k1] <= tol do
            local fb = fixes[idx[b]]
            if math.abs(fb[k2] - fa[k2]) <= tol then
                local ra, rb = find(idx[a]), find(idx[b])
                if ra ~= rb then parent[ra] = rb end
            end
            b = b + 1
        end
        if a % 200 == 0 then coroutine.yield() end
    end
    local byRoot, order = {}, {}
    for i = 1, n do
        local r = find(i)
        if not byRoot[r] then byRoot[r] = {}; order[#order + 1] = r end
        table.insert(byRoot[r], fixes[i])
    end
    local out = {}
    for _, r in ipairs(order) do out[#out + 1] = byRoot[r] end
    return out
end

local function extent(fixes, key)
    local lo, hi, sum = math.huge, -math.huge, 0
    for _, f in ipairs(fixes) do
        if f[key] < lo then lo = f[key] end
        if f[key] > hi then hi = f[key] end
        sum = sum + f[key]
    end
    return lo, hi, sum / #fixes
end

--- Split non-floor fixtures into booms (vertical stacks) and the rest.
--- A boom: >= 2 fixtures at the same lateral/depth spot (within tolerance),
--- spread vertically by at least the tolerance, and narrow laterally.
local function findBooms(fixes)
    local booms, rest = {}, {}
    for _, comp in ipairs(components(fixes, "lat", "dep", CFG.lxTol)) do
        local latLo, latHi = extent(comp, "lat")
        local htLo, htHi   = extent(comp, "ht")
        if #comp >= 2 and (htHi - htLo) >= CFG.lxTol and (latHi - latLo) <= CFG.lxTol * 2 then
            table.insert(booms, comp)
        else
            for _, f in ipairs(comp) do rest[#rest + 1] = f end
        end
    end
    return booms, rest
end

--- Bucket fixtures by type name; returns map and sorted type list.
local function byType(fixes)
    local map, order = {}, {}
    for _, f in ipairs(fixes) do
        if not map[f.typeName] then map[f.typeName] = {}; order[#order + 1] = f.typeName end
        table.insert(map[f.typeName], f.fid)
    end
    table.sort(order)
    return map, order
end

local function fidsOf(fixes)
    local t = {}
    for _, f in ipairs(fixes) do t[#t + 1] = f.fid end
    return t
end

--- All rig positions of a fixture list, shared by Section B (odds/evens per
--- position) and Section E (position groups):
---   floorRows : list of floor rows (height < floor limit), clustered by
---               depth + height, upstage first, each sorted SR -> SL
---   floor     : all floor fixtures, SR -> SL
---   booms     : { SL = {...}, SR = {...} } each boom sorted top unit first
---   lx        : list of LX positions, upstage first, each sorted SR -> SL
local function computeRigPositions(list)
    local positioned = partitionByPosition(list)
    local P = { floorRows = {}, floor = {}, booms = { SL = {}, SR = {} }, lx = {} }
    if #positioned == 0 then return P end

    local above = {}
    for _, f in ipairs(positioned) do
        if f.ht < CFG.floorMax then P.floor[#P.floor + 1] = f else above[#above + 1] = f end
    end
    positionalSort(P.floor)
    local function byDepthThenHeight(a, b)
        local _, _, da = extent(a, "dep"); local _, _, db = extent(b, "dep")
        if math.abs(da - db) > 0.001 then return da < db end
        local _, _, ha = extent(a, "ht"); local _, _, hb = extent(b, "ht")
        return ha < hb
    end
    P.floorRows = components(P.floor, "dep", "ht", CFG.lxTol)
    table.sort(P.floorRows, byDepthThenHeight)
    for _, r in ipairs(P.floorRows) do positionalSort(r) end

    local booms, rest = findBooms(above)
    for _, b in ipairs(booms) do
        local _, _, latMean = extent(b, "lat")
        table.insert(latMean > 0 and P.booms.SL or P.booms.SR, b)
    end
    for _, side in ipairs({ "SL", "SR" }) do
        table.sort(P.booms[side], function(a, b)
            local _, _, da = extent(a, "dep"); local _, _, db = extent(b, "dep")
            return da < db
        end)
        for _, b in ipairs(P.booms[side]) do
            table.sort(b, function(p, q)
                if math.abs(p.ht - q.ht) > 0.001 then return p.ht > q.ht end
                return p.fid < q.fid
            end)
        end
    end

    P.lx = components(rest, "dep", "ht", CFG.lxTol)
    table.sort(P.lx, byDepthThenHeight)
    for _, comp in ipairs(P.lx) do positionalSort(comp) end
    return P
end

--- Ordered list of every position: { name, fixes } (LX, booms, floor rows).
local function positionList(P)
    local out = {}
    for i, comp in ipairs(P.lx) do out[#out + 1] = { name = "LX " .. i, fixes = comp } end
    for _, side in ipairs({ "SL", "SR" }) do
        for i, b in ipairs(P.booms[side]) do
            out[#out + 1] = { name = string.format("Boom %s %d", side, i), fixes = b }
        end
    end
    for i, r in ipairs(P.floorRows) do out[#out + 1] = { name = "Ground Row " .. i, fixes = r } end
    return out
end

--- Odds/evens of an ordered fixture list.
---   simple    : 1st, 3rd, 5th ... = odds
---   symmetric : outside-in pairs alternate (1+N odds, 2+(N-1) evens, ...);
---               a lone centre unit joins the current pair's group.
--- Both results keep the list's own order.
local function oddEvenSplit(fixes, simple)
    local n = #fixes
    local isOdd = {}
    if simple then
        for i = 1, n do isOdd[i] = (i % 2 == 1) end
    else
        local lo, hi, pairIndex = 1, n, 1
        while lo <= hi do
            local odd = (pairIndex % 2 == 1)
            isOdd[lo] = odd; isOdd[hi] = odd
            lo, hi, pairIndex = lo + 1, hi - 1, pairIndex + 1
        end
    end
    local odds, evens = {}, {}
    for i = 1, n do
        if isOdd[i] then odds[#odds + 1] = fixes[i].fid else evens[#evens + 1] = fixes[i].fid end
    end
    return odds, evens
end

--- Per-type odds/evens built position by position (each LX / boom / floor
--- row alternates on its own), then joined in position order. Fixtures
--- without a position alternate among themselves in FID order.
local function computeOddEvenMaps(list, P, simple)
    local oddMap, evenMap = {}, {}
    local function add(tn, o, e)
        oddMap[tn] = oddMap[tn] or {}; evenMap[tn] = evenMap[tn] or {}
        for _, v in ipairs(o) do table.insert(oddMap[tn], v) end
        for _, v in ipairs(e) do table.insert(evenMap[tn], v) end
    end
    for _, pos in ipairs(positionList(P)) do
        local byT, order = {}, {}
        for _, f in ipairs(pos.fixes) do
            if not byT[f.typeName] then byT[f.typeName] = {}; order[#order + 1] = f.typeName end
            table.insert(byT[f.typeName], f)
        end
        for _, tn in ipairs(order) do add(tn, oddEvenSplit(byT[tn], simple)) end
    end
    local unpos, order = {}, {}
    for _, f in ipairs(list) do
        if f.x == nil then
            if not unpos[f.typeName] then unpos[f.typeName] = {}; order[#order + 1] = f.typeName end
            table.insert(unpos[f.typeName], f)
        end
    end
    for _, tn in ipairs(order) do
        table.sort(unpos[tn], function(a, b) return a.fid < b.fid end)
        add(tn, oddEvenSplit(unpos[tn], simple))
    end
    return oddMap, evenMap
end

--- Section E: Ground Row, Booms and LX positions, plus per-position
--- odds/evens (doPosOE).
local function runSectionE(P, slot, doLXMixed, doLXPerType, doGroundMixed, doGroundPerType, doPosOE, simple, overwrite)
    Printf("--- Section E: Rig positions (Ground Row / Booms / LX) ---")
    Printf("  %d floor fixture(s) (%d row(s)), %d boom(s) SL, %d boom(s) SR, %d LX position(s).",
        #P.floor, #P.floorRows, #P.booms.SL, #P.booms.SR, #P.lx)

    -- odds/evens for one position (mixed + per type). 'rows' splits the
    -- position into sub-rows that each alternate on their own (ground row).
    local function splitRows(rows, filterType)
        local O, E = {}, {}
        for _, r in ipairs(rows) do
            local sub = {}
            for _, f in ipairs(r) do
                if not filterType or f.typeName == filterType then sub[#sub + 1] = f end
            end
            local o, e = oddEvenSplit(sub, simple)
            for _, v in ipairs(o) do O[#O + 1] = v end
            for _, v in ipairs(e) do E[#E + 1] = v end
        end
        return O, E
    end
    local function posOddEven(name, fixes, rows)
        rows = rows or { fixes }
        local o, e = splitRows(rows, nil)
        slot = nextFreeSlot(slot); slot = storeGroup(name .. " Odds", o, slot, overwrite)
        slot = nextFreeSlot(slot); slot = storeGroup(name .. " Evens", e, slot, overwrite)
        local _, order = byType(fixes)
        for _, tn in ipairs(order) do
            local to, te = splitRows(rows, tn)
            slot = nextFreeSlot(slot); slot = storeGroup(name .. " " .. tn .. " Odds", to, slot, overwrite)
            slot = nextFreeSlot(slot); slot = storeGroup(name .. " " .. tn .. " Evens", te, slot, overwrite)
        end
    end

    -- one position: base groups + odds/evens
    local function position(name, fixes, doMixed, doPerType, rows)
        if doMixed then
            slot = nextFreeSlot(slot)
            slot = storeGroup(name, fidsOf(fixes), slot, overwrite)
        end
        if doPerType then
            local map, order = byType(fixes)
            for _, tn in ipairs(order) do
                slot = nextFreeSlot(slot)
                slot = storeGroup(name .. " " .. tn, map[tn], slot, overwrite)
            end
        end
        if doPosOE then posOddEven(name, fixes, rows) end
    end

    -- Ground Row (all floor fixtures); odds/evens alternate per floor row
    if #P.floor > 0 and (doGroundMixed or doGroundPerType or doPosOE) then
        position("Ground Row", P.floor, doGroundMixed, doGroundPerType, P.floorRows)
    end

    -- Booms
    for _, side in ipairs({ "SL", "SR" }) do
        for i, b in ipairs(P.booms[side]) do
            position(string.format("Boom %s %d", side, i), b, doLXMixed, doLXPerType)
        end
    end

    -- LX positions
    for i, comp in ipairs(P.lx) do
        local _, _, dm = extent(comp, "dep")
        local _, _, hm = extent(comp, "ht")
        Printf("    LX %d: %d fixture(s) at depth %s, height %s", i, #comp,
            string.format("%.2f", dm), string.format("%.2f", hm))
        position("LX " .. i, comp, doLXMixed, doLXPerType)
    end
    return slot
end

-------------------------------------------------------------------------------
-- LAYER 5 -- Section runners
-------------------------------------------------------------------------------

--- Section B: Odds and Evens group per fixture type.
local function runSectionB(typeOrder, oddMap, evenMap, slot, overwrite)
    Printf("--- Section B: Per-type Odds / Evens (alternating within each position) ---")
    for _, typeName in ipairs(typeOrder) do
        slot = nextFreeSlot(slot)
        slot = storeGroup(typeName .. " Odds",  oddMap[typeName] or {},  slot, overwrite)
        slot = nextFreeSlot(slot)
        slot = storeGroup(typeName .. " Evens", evenMap[typeName] or {}, slot, overwrite)
    end
    return slot
end

--- Section C: One group per fixture type (all fixtures of that type).
local function runSectionC(typeOrder, typeMap, slot, overwrite)
    Printf("--- Section C: Fixture type groups ---")
    for _, typeName in ipairs(typeOrder) do
        slot = nextFreeSlot(slot)
        slot = storeGroup(typeName, typeMap[typeName], slot, overwrite)
    end
    return slot
end

--- Section D: physical position zones.
--- doZones     -> D1 zone groups for all enabled types together
--- doTypeZones -> D2 "<Type> <zone>" groups (same limits as D1)
local function runSectionD(list, slot, doZones, doTypeZones, overwrite)
    Printf("--- Section D: Position zones ---")
    local positioned, unpositioned = partitionByPosition(list)
    if #positioned == 0 then
        Printf("  No fixtures have 3D position data -- skipping.")
        return slot, 0, unpositioned
    end
    if unpositioned > 0 then
        Printf("  Note: %d fixture(s) at 0,0,0 treated as unpositioned.", unpositioned)
    end

    local depthMap, nLines, lines = depthZoneMap(positioned)
    if CFG.centreBandAuto then
        -- three equal bands, symmetric on the stage centre, out to the
        -- farthest fixture: CS = +/- one third of that distance
        local far = 0
        for _, f in ipairs(positioned) do
            if math.abs(f.lat) > far then far = math.abs(f.lat) end
        end
        CFG.centreBand = far / 3
        Printf("  Lateral (auto): farthest fixture %.2f m from centre -> SR < -%.2f | CS +/-%.2f | SL > +%.2f m",
            far, CFG.centreBand, CFG.centreBand, CFG.centreBand)
    else
        Printf("  Lateral: CS = within +/-%.2f m of centre", CFG.centreBand)
    end
    if depthMap then
        local parts = {}
        for i, m in ipairs(lines) do
            parts[#parts + 1] = string.format("%.2f=%s", m.dep, depthMap[m.line[1].fid])
        end
        Printf("  Depth:   %d position line(s), upstage->downstage: %s", nLines, table.concat(parts, "  "))
    else
        Printf("  Depth:   only one position line -- US/Mid Stage/DS skipped.")
    end
    Printf("  Height:  Floor < %.2f m, Low < %.2f m, Flown above", CFG.floorMax, CFG.lowMax)

    if doZones then
        Printf("  -- D1: Zone groups --")
        for _, z in ipairs(classifyZones(positioned, depthMap, "")) do
            slot = nextFreeSlot(slot)
            slot = storeGroup(z.label, z.fids, slot, overwrite)
        end
    end

    if doTypeZones then
        Printf("  -- D2: Type + zone groups --")
        local map, order = {}, {}
        for _, f in ipairs(positioned) do
            if not map[f.typeName] then map[f.typeName] = {}; order[#order + 1] = f.typeName end
            table.insert(map[f.typeName], f)
        end
        table.sort(order)
        for _, tn in ipairs(order) do
            for _, z in ipairs(classifyZones(map[tn], depthMap, tn .. " ")) do
                slot = nextFreeSlot(slot)
                slot = storeGroup(tn .. " " .. z.label, z.fids, slot, overwrite)
            end
        end
    end

    return slot, #positioned, unpositioned
end

-------------------------------------------------------------------------------
-- LAYER 4c -- Section F: sub-fixture (cell) groups
-------------------------------------------------------------------------------

--- The cell sets of one fixture.
local function cellSetsOf(f)
    if not f.cellTree then return {} end
    return f.cellTree.sets
end

--- Numeric-aware compare of set keys ("" < "3" < "4" < "10" < "10.2")
local function keyLess(a, b)
    if a == b then return false end
    if a == "" then return true end
    if b == "" then return false end
    local pa, pb = {}, {}
    for n in a:gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in b:gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or -1, pb[i] or -1
        if x ~= y then return x < y end
    end
    return a < b
end

--- Collect sets for one type: ordered list of { key, label, fixes = { {fid, cells} } }
--- Label = patch name of the sub-fixture when set, otherwise its number.
local function typeCellSets(fixes)
    local byKey, keys = {}, {}
    table.sort(fixes, function(a, b) return a.fid < b.fid end)
    for _, f in ipairs(fixes) do
        for _, s in ipairs(cellSetsOf(f)) do
            local e = byKey[s.key]
            if not e then
                e = { key = s.key, label = nil, members = {} }
                byKey[s.key] = e
                keys[#keys + 1] = s.key
            end
            if s.key ~= "" and (e.label == nil or e.label == "") and s.name and s.name ~= "" then
                e.label = s.name
            end
            table.insert(e.members, { fid = f.fid, cells = s.cells, parent = s.parent, downs = s.downs })
        end
    end
    table.sort(keys, keyLess)
    local out = {}
    for _, k in ipairs(keys) do
        local e = byKey[k]
        if k ~= "" and (e.label == nil or e.label == "") then e.label = k end
        out[#out + 1] = e
    end
    return out
end

--- Grid X of each cell of one member, read from the native selection grid
--- ("Fixture <parent>" + "Down"). Cached per type + set + cell count and
--- reused for the other fixtures of that type; nil = grid not readable.
local GRIDX = {}
local GRIDX_READS = 0
local function cellXs(typeName, setKey, m)
    local pre = tostring(m.fid)
    local function lookup(rel)
        local xs = {}
        for i, c in ipairs(m.cells) do
            local v = rel[tostring(c):sub(#pre + 1)]
            if v == nil then return nil end
            xs[i] = v
        end
        return xs
    end
    local ck = typeName .. "|" .. setKey .. "|" .. #m.cells
    local xs = GRIDX[ck] and lookup(GRIDX[ck]) or nil
    if xs then return xs end
    if not m.parent then return nil end
    Cmd("ClearAll")
    Cmd("Fixture " .. m.parent)
    for _ = 1, (m.downs or 1) do Cmd("Down") end
    GRIDX_READS = GRIDX_READS + 1
    local map = readSelectionGrid()
    local rel = {}
    for a, p in pairs(map) do
        if a:sub(1, #pre + 1) == pre .. "." then rel[a:sub(#pre + 1)] = p.x end
    end
    xs = lookup(rel)
    if xs and not GRIDX[ck] then GRIDX[ck] = rel end
    return xs
end

--- Per-type cell groups. opts: all, index, oddEven, thirds.
local function runSectionF(list, slot, opts, overwrite)
    Printf("--- Section F: Sub-fixture (cell) groups (deepest cells, separate sets) ---")
    local map, order = {}, {}
    for _, f in ipairs(list) do
        if f.cellTree then
            if not map[f.typeName] then map[f.typeName] = {}; order[#order + 1] = f.typeName end
            table.insert(map[f.typeName], f)
        end
    end
    table.sort(order)
    if #order == 0 then
        Printf("  No fixtures with cells -- skipping.")
        return slot
    end

    for _, tn in ipairs(order) do
        for _, set in ipairs(typeCellSets(map[tn])) do
            local prefix = tn .. ((set.label and set.label ~= "") and (" " .. set.label) or "")
            local all = {}
            for _, m in ipairs(set.members) do
                for _, c in ipairs(m.cells) do all[#all + 1] = c end
            end
            Printf("  %s: %d fixture(s), %d cell(s)", prefix, #set.members, #all)
            local maxN = 0
            for _, m in ipairs(set.members) do if #m.cells > maxN then maxN = #m.cells end end

            -- grid spec for a subset: per member, how many of its cells are in 'inSet'
            local function subsetGrid(inSet)
                local mem = {}
                for _, m in ipairs(set.members) do
                    local n = 0
                    for _, c in ipairs(m.cells) do if inSet[c] then n = n + 1 end end
                    mem[#mem + 1] = { parent = m.parent, downs = m.downs, n = n }
                end
                return gridSpec(mem)
            end
            local function asSet(t) local s = {} for _, c in ipairs(t) do s[c] = true end return s end

            if opts.all then
                slot = nextFreeSlot(slot)
                slot = storeGroup(prefix .. " Cells", all, slot, overwrite, subsetGrid(asSet(all)))
            end

            -- "Cell N" stays a plain list (one cell per fixture); skipped when
            -- every fixture has a single cell (same as "<prefix> Cells")
            if opts.index and maxN > 1 then
                for n = 1, maxN do
                    local g = {}
                    for _, m in ipairs(set.members) do
                        if m.cells[n] then g[#g + 1] = m.cells[n] end
                    end
                    slot = nextFreeSlot(slot)
                    slot = storeGroup(string.format("%s Cell %d", prefix, n), g, slot, overwrite)
                end
            end

            if opts.oddEven then
                local odds, evens = {}, {}
                for i, c in ipairs(all) do
                    if i % 2 == 1 then odds[#odds + 1] = c else evens[#evens + 1] = c end
                end
                slot = nextFreeSlot(slot)
                slot = storeGroup(prefix .. " Cells Odds", odds, slot, overwrite, subsetGrid(asSet(odds)))
                slot = nextFreeSlot(slot)
                slot = storeGroup(prefix .. " Cells Evens", evens, slot, overwrite, subsetGrid(asSet(evens)))
            end

            if opts.thirds then
                -- per fixture, by grid X: the columns are split in thirds
                -- (floor(cols/3) each edge, the middle gets the rest; Left =
                -- lowest X as seen in the selection grid). Falls back to cell
                -- number when the grid can't be read.
                local L, M, R = {}, {}, {}
                local byNumber = 0
                for _, m in ipairs(set.members) do
                    local xs = cellXs(tn, set.key, m)
                    if xs then
                        local lo, hi = math.huge, -math.huge
                        for _, x in ipairs(xs) do
                            if x < lo then lo = x end
                            if x > hi then hi = x end
                        end
                        local edge = math.floor((hi - lo + 1) / 3)
                        for i, c in ipairs(m.cells) do
                            local x = xs[i]
                            if x < lo + edge then L[#L + 1] = c
                            elseif x > hi - edge then R[#R + 1] = c
                            else M[#M + 1] = c end
                        end
                    else
                        byNumber = byNumber + 1
                        local n = #m.cells
                        local edge = math.floor(n / 3)
                        for i, c in ipairs(m.cells) do
                            if i <= edge then L[#L + 1] = c
                            elseif i > n - edge then R[#R + 1] = c
                            else M[#M + 1] = c end
                        end
                    end
                end
                if byNumber > 0 then
                    ErrPrintf("  %s: grid not readable for %d fixture(s) -- thirds by cell number.", prefix, byNumber)
                end
                if #L == 0 and #R == 0 then
                    Printf("  %s: too narrow for left / middle / right -- skipped.", prefix)
                else
                    slot = nextFreeSlot(slot)
                    slot = storeGroup(prefix .. " Cells Left", L, slot, overwrite, subsetGrid(asSet(L)))
                    slot = nextFreeSlot(slot)
                    slot = storeGroup(prefix .. " Cells Middle", M, slot, overwrite, subsetGrid(asSet(M)))
                    slot = nextFreeSlot(slot)
                    slot = storeGroup(prefix .. " Cells Right", R, slot, overwrite, subsetGrid(asSet(R)))
                end
            end
        end
    end
    if GRIDX_READS > 0 then
        Cmd("ClearAll")
        Printf("  Thirds: read %d cell grid(s) from the console (selection cleared).", GRIDX_READS)
    end
    return slot
end

--- "<name> Cells" versions of already-planned groups (PLAN[fromIdx..toIdx]).
--- Each cell set gets its own version: "LX 1 Cells" (top-level cells) and
--- e.g. "LX 1 Plate Cells" for a named nested set (unnamed -> "<Type> <n>").
local function mirrorCellGroups(list, fromIdx, toIdx, slot, overwrite)
    local byFid = {}
    for _, f in ipairs(list) do if f.cellTree then byFid[f.fid] = f end end
    -- per type, resolve set labels once (same naming as Section F)
    local typeLabels = {}
    local function labelFor(f, key)
        if key == "" then return "" end
        local tl = typeLabels[f.typeName]
        if not tl then
            tl = {}
            local fixes = {}
            for _, x in ipairs(list) do if x.cellTree and x.typeName == f.typeName then fixes[#fixes + 1] = x end end
            for _, s in ipairs(typeCellSets(fixes)) do
                tl[s.key] = (s.label == s.key) and (f.typeName .. " " .. s.key) or s.label
            end
            typeLabels[f.typeName] = tl
        end
        return tl[key] or (f.typeName .. " " .. key)
    end

    local sources = {}
    for i = fromIdx, toIdx do
        local nm = PLAN[i].name
        if not (nm:match(" Odds$") or nm:match(" Evens$")) then sources[#sources + 1] = PLAN[i] end
    end
    local made = 0
    for _, g in ipairs(sources) do
        local fixes = {}
        for _, fid in ipairs(g.fids) do
            if byFid[fid] then fixes[#fixes + 1] = byFid[fid] end
        end
        table.sort(fixes, function(a, b) return a.fid < b.fid end)
        local buckets, labels, members = {}, {}, {}
        for _, f in ipairs(fixes) do
            for _, s in ipairs(cellSetsOf(f)) do
                local lbl = labelFor(f, s.key)
                if not buckets[lbl] then buckets[lbl] = {}; members[lbl] = {}; labels[#labels + 1] = lbl end
                for _, c in ipairs(s.cells) do table.insert(buckets[lbl], c) end
                table.insert(members[lbl], { parent = s.parent, downs = s.downs, n = #s.cells })
            end
        end
        for _, lbl in ipairs(labels) do
            local nm = g.name .. ((lbl ~= "") and (" " .. lbl) or "") .. " Cells"
            slot = nextFreeSlot(slot)
            slot = storeGroup(nm, buckets[lbl], slot, overwrite, gridSpec(members[lbl]))
            made = made + 1
        end
    end
    Printf("  Cell versions of zone / rig-position groups: %d", made)
    return slot
end

-------------------------------------------------------------------------------
-- LAYER 5 -- Summary printer
-------------------------------------------------------------------------------

local function printSummary(counts, posCount, unposCount)
    Printf("=== CreateFixtureGroups v%s complete. ===", PLUGIN_VERSION)
    Printf("  Section B -- Odds/Evens:        %d group(s)", counts.B)
    Printf("  Section C -- Fixture types:     %d group(s)", counts.C)
    Printf("  Section D -- Position zones:    %d group(s)  (%d positioned, %d unpositioned)",
           counts.D, posCount, unposCount)
    Printf("  Section E -- Rig positions:     %d group(s)", counts.E)
    Printf("  Section F -- Cells:             %d group(s)", counts.F)
    local lo, hi, nOver = nil, nil, 0
    for _, g in ipairs(PLAN) do
        if g.overwrite then
            nOver = nOver + 1
        else
            lo = (lo == nil or g.slot < lo) and g.slot or lo
            hi = (hi == nil or g.slot > hi) and g.slot or hi
        end
    end
    if lo then Printf("  New groups in pool slots: %d .. %d", lo, hi) end
    if nOver > 0 then Printf("  Existing groups overwritten: %d", nOver) end
end

-------------------------------------------------------------------------------
-- LAYER 6 -- Orchestration
-------------------------------------------------------------------------------

local function main()
    initColors()
    local overlay = GetFocusDisplay().ScreenOverlay

    -- Saved defaults (show file) laid over the built-in values
    local D1 = mergeDefaults(BUILTIN_D1, loadDefaults("d1"))
    local D2 = mergeDefaults(BUILTIN_D2, loadDefaults("d2"))

    -- 1. Dialog 1: stage, start slot, axes, zone limits ("Reset defaults" reopens it)
    local step1
    repeat
        step1 = showSettingsUI(overlay, D1)
        if step1 and step1.reopen then D1 = copyT(BUILTIN_D1) end
    until not (step1 and step1.reopen)
    if not step1 then
        Printf("CreateFixtureGroups: cancelled.")
        return
    end
    local stageName = step1.stageName
    local startSlot = step1.startSlot

    AXIS_MAP.lateral       = step1.axisLateral
    AXIS_MAP.depth         = step1.axisDepth
    AXIS_MAP.height        = step1.axisHeight
    AXIS_MAP.invertLateral = step1.invertLateral
    AXIS_MAP.invertDepth   = step1.invertDepth
    AXIS_MAP.invertHeight  = step1.invertHeight
    CFG.centreBand      = step1.centreBand
    CFG.floorMax        = step1.floorMax
    CFG.lowMax          = step1.lowMax
    CFG.lxTol           = step1.lxTol
    CFG.addParentOffset = step1.addParentOffset
    CFG.centreLat       = step1.centreLat
    CFG.centreAuto      = step1.centreAuto
    CFG.centreBandAuto  = step1.centreBandAuto

    Printf("=== CreateFixtureGroups v%s ===", PLUGIN_VERSION)
    Printf("Axis map: Lateral=%s%s  Depth=%s%s  Height=%s%s",
           AXIS_MAP.lateral:upper(), AXIS_MAP.invertLateral and '(inv)' or '',
           AXIS_MAP.depth:upper(),   AXIS_MAP.invertDepth   and '(inv)' or '',
           AXIS_MAP.height:upper(),  AXIS_MAP.invertHeight  and '(inv)' or '')
    Printf("Limits: stage centre %s | centre band %s | floor < %.2f m | low < %.2f m | LX tolerance %.2f m | parent offset %s",
           CFG.centreAuto and "AUTO" or string.format("%.3f m", CFG.centreLat),
           CFG.centreBandAuto and "AUTO" or string.format("+/-%.2f m", CFG.centreBand),
           CFG.floorMax, CFG.lowMax, CFG.lxTol, CFG.addParentOffset and "on" or "off")

    -- 2. Collect fixtures so dialog 2 knows which types exist
    local fixtureList, skipped = collectFixtures(stageName)
    if #fixtureList == 0 then
        ErrPrintf("No fixtures found on stage \"%s\".", stageName)
        ErrPrintf("Check the name matches what is shown in the Patch (not case-sensitive).")
        return
    end
    sortByFID(fixtureList)
    local typeOrder, typeMap, oddMap, evenMap = buildTypeMap(fixtureList)

    -- 3. Dialog 2: sections + types
    local settings
    repeat
        settings = showGroupOptionsUI(overlay, typeOrder, D2)
        if settings and settings.reopen then D2 = copyT(BUILTIN_D2) end
    until not (settings and settings.reopen)
    if not settings then
        Printf("CreateFixtureGroups: cancelled.")
        return
    end

    Printf("Stage \"%s\": %d fixture(s), %d on other stages.", stageName, #fixtureList, skipped)

    local filteredTypeOrder = {}
    for _, typeName in ipairs(typeOrder) do
        if settings.enabledTypes[typeName] then
            table.insert(filteredTypeOrder, typeName)
        else
            Printf("  Skipping type: %s", typeName)
        end
    end
    local filteredFixtures = {}
    for _, fix in ipairs(fixtureList) do
        if settings.enabledTypes[fix.typeName] then
            table.insert(filteredFixtures, fix)
        end
    end

    -- 3b. Cell sets: split cells with different names only where wanted.
    -- The picker appears only when a set holds cells with different names.
    if settings.cellsAll or settings.cellsIndex or settings.cellsOddEven
       or settings.cellsThirds or settings.cellsZones then
        local rows = cellSplitRows(filteredFixtures)
        local saved = loadDefaults("cells") or {}
        for _, r in ipairs(rows) do
            r.auto = r.state
            if saved[r.key] ~= nil then r.state = (saved[r.key] == "1") end
        end
        local decisions = {}
        for _, r in ipairs(rows) do decisions[r.key] = r.state end
        if #rows > 0 then
            coroutine.yield()
            repeat
                decisions = showCellSetsUI(overlay, rows)
                if decisions and decisions.reopen then
                    for _, r in ipairs(rows) do r.state = r.auto end
                end
            until not (decisions and decisions.reopen)
            if not decisions then
                Printf("CreateFixtureGroups: cancelled.")
                return
            end
        end
        local split = applyCellSplits(filteredFixtures, decisions)
        if #split > 0 then
            Printf("Cell sets split off by name: %s", table.concat(split, ", "))
        elseif #rows > 0 then
            Printf("Cell sets: no names split off (cells with different names kept together).")
        end
    end

    -- 4. Build the plan (nothing is stored yet)
    PLAN = {}
    loadUsedSlots()
    local overwrite = settings.overwrite
    Printf(overwrite and ("Mode: OVERWRITE (existing names updated in place, new groups from slot " .. startSlot .. ")")
                     or  ("Mode: CREATE (free pool slots from " .. startSlot .. ")"))

    local slot, posCount, unposCount = startSlot, 0, 0
    local counts = { B = 0, C = 0, D = 0, E = 0, F = 0 }
    local function mark(key, before) counts[key] = #PLAN - before end

    -- Rig positions (shared by Sections B and E) and per-position odds/evens
    local P = computeRigPositions(filteredFixtures)
    oddMap, evenMap = computeOddEvenMaps(filteredFixtures, P, settings.oeSimple)
    Printf("Odds/Evens pattern: %s", settings.oeSimple and "simple alternate" or "symmetric outside-in")

    local n0 = #PLAN
    if settings.doOddsEvens then slot = runSectionB(filteredTypeOrder, oddMap, evenMap, slot, overwrite) end
    mark("B", n0); n0 = #PLAN
    if settings.doTypes then slot = runSectionC(filteredTypeOrder, typeMap, slot, overwrite) end
    mark("C", n0); n0 = #PLAN
    if settings.doZones or settings.doTypeZones then
        slot, posCount, unposCount = runSectionD(filteredFixtures, slot, settings.doZones, settings.doTypeZones, overwrite)
    end
    mark("D", n0)
    local zoneStart = n0 + 1          -- first planned D group (for cell versions)
    n0 = #PLAN
    if settings.doLXMixed or settings.doLXPerType or settings.doGroundMixed
       or settings.doGroundPerType or settings.doPosOddEven then
        slot = runSectionE(P, slot,
            settings.doLXMixed, settings.doLXPerType,
            settings.doGroundMixed, settings.doGroundPerType,
            settings.doPosOddEven, settings.oeSimple, overwrite)
    end
    mark("E", n0); n0 = #PLAN
    local zoneEnd = #PLAN
    local anyCells = settings.cellsAll or settings.cellsIndex or settings.cellsOddEven
                     or settings.cellsThirds or settings.cellsZones
    if anyCells then
        slot = runSectionF(filteredFixtures, slot, {
            all = settings.cellsAll, index = settings.cellsIndex,
            oddEven = settings.cellsOddEven, thirds = settings.cellsThirds,
        }, overwrite)
        if settings.cellsZones and zoneEnd >= zoneStart then
            slot = mirrorCellGroups(filteredFixtures, zoneStart, zoneEnd, slot, overwrite)
        end
    end
    mark("F", n0)

    if #PLAN == 0 then
        ErrPrintf("CreateFixtureGroups: nothing to create with these settings.")
        return
    end

    -- 5. Confirm (wait for dialog 2 to finish closing first)
    coroutine.yield(); coroutine.yield()
    local slotText = ""
    do
        local lo, hi, nNew, nOver = nil, nil, 0, 0
        for _, g in ipairs(PLAN) do
            if g.overwrite then
                nOver = nOver + 1
            else
                nNew = nNew + 1
                lo = (lo == nil or g.slot < lo) and g.slot or lo
                hi = (hi == nil or g.slot > hi) and g.slot or hi
            end
        end
        if lo then slotText = string.format("\n%d new in pool slots %d - %d", nNew, lo, hi) end
        if nOver > 0 then slotText = slotText .. string.format("\n%d existing group(s) overwritten", nOver) end
    end
    local msg = string.format(
        "Create %d group(s)?%s\n\nOdds/Evens %d | Types %d | Zones %d | Rig positions %d | Cells %d\n(see System Monitor for the full list)",
        #PLAN, slotText,
        counts.B, counts.C, counts.D, counts.E, counts.F)
    local res = MessageBox({
        title    = "Create Fixture Groups",
        message  = msg,
        commands = { { value = 1, name = "Create" }, { value = 0, name = "Cancel" } },
    })
    local choice = (type(res) == "table") and res.result or nil
    if choice ~= 1 then
        Printf("CreateFixtureGroups: cancelled at confirm -- nothing stored.")
        return
    end

    -- 6. Store
    executePlan()
    printSummary(counts, posCount, unposCount)
end

return main
