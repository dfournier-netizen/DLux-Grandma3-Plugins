--[[
    MATrickBuilder.lua  v2.1.1  (progress bar + confirm)
    GrandMA3 Plugin - Version compatible: 2.3.2+

    MERGED PLUGIN: combines the MATrick Sequence Builder and the
    MATrick Layout Generator into a single "Build All" workflow.

    PHASE 1 - SEQUENCES + TAGS:
        Per parameter group per MATrick (e.g. "Col FdFrX"):
          - ONE group tag, assigned to every value sequence in the group.
            MA3 tag exclusivity releases the previously-active sibling when a
            new value in the group fires - no Active/Inactive bookkeeping.
        Per value (e.g. "Col FdFrX 0p25"):
          - Sequence at index 5001+, named "{prefix} {label} {value}"
          - Cue 1 with command: Call Macro '{name}'  (macro is a single
            Set MAtricks line)
          - DK appearance on the sequence, LT appearance on Cue 1

    PHASE 2 - LAYOUTS:
        For each parameter FAMILY (Phase, Fade, Delay, Speed, Wings,
        Blocks, Groups, Width), TWO layouts are produced:
          - "MATrick {Family} - Params"  : Dim, Pos, Color, Beam, Focus
          - "MATrick {Family} - Effects" : Default, Bumps, Sweeps, Walk In
        Within each layout:
          - Two rows per MATrick (X axis row, then Y axis row)
          - Sequences grouped by axis with labeled separators
          - All chrome hidden except the element itself

    NOTE v2.0: Block/Group labels are SINGULAR everywhere - names AND the
        Set MAtricks attribute: XBlock, YBlock, XGroup, YGroup
        (this is the MA3-correct attribute spelling).

    REQUIREMENTS:
        - Macros already exist in Macro pool (with "p" for decimals,
          singular Block/Group naming)
        - CH10 icon set in Appearance pool: DK 1001-1053, LT 1054-1106
]]

local pluginName    = select(1, ...)
local componentName = select(2, ...)
local signalTable   = select(3, ...)
local myHandle      = select(4, ...)

-------------------------------------------------------------------------------
-- Shared data
-------------------------------------------------------------------------------

-- 9 MATricks. prefix matches sequence/macro naming.
local MATRICKS = {
    { name = "Color Phaser", prefix = "Col" },
    { name = "Dim Phaser",   prefix = "Dim" },
    { name = "Focus Phaser", prefix = "Foc" },
    { name = "Pos Phaser",   prefix = "Pos" },
    { name = "Sweeps",       prefix = "Swp" },
    { name = "Default",      prefix = "Def" },
    { name = "Walk In",      prefix = "Wlk" },
    { name = "Beam Phaser",  prefix = "Bm"  },
    { name = "Bumps",        prefix = "Bmp" },
}

-- Layout grouping: which MATricks belong to the "Params" vs "Effects" layout.
local LAYOUT_GROUPS = {
    {
        suffix  = "Params",
        order   = { "Dim Phaser", "Pos Phaser", "Color Phaser", "Beam Phaser", "Focus Phaser" },
    },
    {
        suffix  = "Effects",
        -- remainder, alphabetical
        order   = { "Bumps", "Default", "Sweeps", "Walk In" },
    },
}

-- Value lists
local PHASE_VALUES = {0,30,60,90,120,150,180,210,240,270,300,330,360,390,420,450,480,510,540,570,600,630,660,690,720}
local FADE_VALUES  = {0, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2}
local SPEED_VALUES = {0, 10, 20, 30, 40, 50, 60}
local WINGS_VALUES = {2,3,4,5,6,7,8,9,10,11,12,13,14,15,16}
local BLOCK_VALUES = {0,1,2,3,4,5,6,7,8}

-- 24 parameter groups (SINGULAR Block/Group labels)
local PROP_GROUPS = {
    { label = "PhFrX",  values = PHASE_VALUES },
    { label = "PhToX",  values = PHASE_VALUES },
    { label = "PhFrY",  values = PHASE_VALUES },
    { label = "PhToY",  values = PHASE_VALUES },
    { label = "FdFrX",  values = FADE_VALUES  },
    { label = "FdToX",  values = FADE_VALUES  },
    { label = "FdFrY",  values = FADE_VALUES  },
    { label = "FdToY",  values = FADE_VALUES  },
    { label = "DlFrX",  values = FADE_VALUES  },
    { label = "DlToX",  values = FADE_VALUES  },
    { label = "DlFrY",  values = FADE_VALUES  },
    { label = "DlToY",  values = FADE_VALUES  },
    { label = "SpFrX",  values = SPEED_VALUES },
    { label = "SpToX",  values = SPEED_VALUES },
    { label = "SpFrY",  values = SPEED_VALUES },
    { label = "SpToY",  values = SPEED_VALUES },
    { label = "XWings", values = WINGS_VALUES },
    { label = "YWings", values = WINGS_VALUES },
    { label = "XBlock", values = BLOCK_VALUES },
    { label = "YBlock", values = BLOCK_VALUES },
    { label = "XGroup", values = BLOCK_VALUES },
    { label = "YGroup", values = BLOCK_VALUES },
    { label = "XWidth", values = BLOCK_VALUES },
    { label = "YWidth", values = BLOCK_VALUES },
}

-- Parameter families -> layout structure. axisGroups split X / Y rows.
-- (Uses SINGULAR Block/Group labels.)
local FAMILIES = {
    { name = "Phase",  axisGroups = {
        { axis="X", params={ {label="PhFrX",values=PHASE_VALUES},{label="PhToX",values=PHASE_VALUES} } },
        { axis="Y", params={ {label="PhFrY",values=PHASE_VALUES},{label="PhToY",values=PHASE_VALUES} } } } },
    { name = "Fade",   axisGroups = {
        { axis="X", params={ {label="FdFrX",values=FADE_VALUES},{label="FdToX",values=FADE_VALUES} } },
        { axis="Y", params={ {label="FdFrY",values=FADE_VALUES},{label="FdToY",values=FADE_VALUES} } } } },
    { name = "Delay",  axisGroups = {
        { axis="X", params={ {label="DlFrX",values=FADE_VALUES},{label="DlToX",values=FADE_VALUES} } },
        { axis="Y", params={ {label="DlFrY",values=FADE_VALUES},{label="DlToY",values=FADE_VALUES} } } } },
    { name = "Speed",  axisGroups = {
        { axis="X", params={ {label="SpFrX",values=SPEED_VALUES},{label="SpToX",values=SPEED_VALUES} } },
        { axis="Y", params={ {label="SpFrY",values=SPEED_VALUES},{label="SpToY",values=SPEED_VALUES} } } } },
    { name = "Wings",  axisGroups = {
        { axis="X", params={ {label="XWings",values=WINGS_VALUES} } },
        { axis="Y", params={ {label="YWings",values=WINGS_VALUES} } } } },
    { name = "Blocks", axisGroups = {
        { axis="X", params={ {label="XBlock",values=BLOCK_VALUES} } },
        { axis="Y", params={ {label="YBlock",values=BLOCK_VALUES} } } } },
    { name = "Groups", axisGroups = {
        { axis="X", params={ {label="XGroup",values=BLOCK_VALUES} } },
        { axis="Y", params={ {label="YGroup",values=BLOCK_VALUES} } } } },
    { name = "Width",  axisGroups = {
        { axis="X", params={ {label="XWidth",values=BLOCK_VALUES} } },
        { axis="Y", params={ {label="YWidth",values=BLOCK_VALUES} } } } },
}

-- Appearance icon lookup: DK 1001-1053, LT 1054-1106
local ICONS = {}
do
    local order = {"0","0p25","0p5","0p75","1","1p25","1p5","1p75","2","2p25",
        "2p5","2p75","3","4","5","6","7","8","9","10","11","12","13","14","15",
        "16","20","30","40","50","60","90","120","150","180","210","240","270",
        "300","330","360","390","420","450","480","510","540","570","600","630",
        "660","690","720"}
    for i, key in ipairs(order) do
        ICONS[key] = { dk = 1000 + i, lt = 1053 + i }
    end
end

-- Sequence / tag indices
local SEQ_START = 5001
local TAG_START = 1001

-- Reset appearance (icon "like the rest"): DK 1107, LT 1108.
-- Import the reset icon to these Appearance pool slots.
local RESET_APP_DK = 1107
local RESET_APP_LT = 1108

-- Reset sequences live in their own range (one per MATrick+Parameter group).
local RESET_SEQ_START = 7901   -- 9 MATricks x 24 params = 216 sequences
local RESET_TAG_START = 1601   -- 216 reset group tags (optional grouping)

-- Reset All sequences (one per parameter; reset the param across all 5
-- standard MATricks at once). 24 total, built at index 8201+ in Phase 1d.

-- Layout geometry
local ORIGIN_X = -3200
local CELL_W   = 90
local CELL_H   = 90
local CELL_GAP = 4
local SEP_W    = 70
local ROW_GAP  = 16
local SEP_GAP  = 10
local SEP_TEXT_COLOR = "FFD600FF"
local SEP_TEXT_SIZE  = 20
local SEP_APP_INDEX  = 991
local SEP_APP_NAME   = "MATrickSep"

local UI_BG_IDX = 30.12

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function trim(s) return s and s:match("^%s*(.-)%s*$") or "" end

-- Progress bar (MA3 StartProgress API). Yields every YIELD_EVERY steps so the
-- console stays responsive and the bar redraws. All calls pcall-guarded.
local YIELD_EVERY = 10
local _prog, _progN = nil, 0
local function progStart(title, total)
    local ok, h = pcall(StartProgress, title)
    _prog = ok and h or nil
    _progN = 0
    if _prog then
        pcall(SetProgressRange, _prog, 0, total)
        pcall(SetProgress, _prog, 0)
    end
end
local function progText(text)
    if _prog then pcall(SetProgressText, _prog, text) end
end
local function progStep()
    _progN = _progN + 1
    if _prog then pcall(SetProgress, _prog, _progN) end
    if _progN % YIELD_EVERY == 0 then coroutine.yield() end
end
local function progStop()
    if _prog then pcall(StopProgress, _prog) end
    _prog = nil
end

local function fmtVal(v)
    if v == math.floor(v) then return tostring(math.floor(v)) end
    return (tostring(v):gsub("%.", "p"))
end

-- Look up a MATrick prefix by name
local function prefixFor(name)
    for _, m in ipairs(MATRICKS) do
        if m.name == name then return m.prefix end
    end
    return nil
end

-------------------------------------------------------------------------------
-- PHASE 1: Sequences + Tags
-------------------------------------------------------------------------------
local function buildSequences()
    Printf("=== PHASE 1: Sequences + Tags ===")
    progStart("MATrick Builder: sequences", 3080)
    progText("Clearing old sequences and tags...")

    local SEQ_END = SEQ_START + 2555   -- 2556 total
    local TAG_END = TAG_START + 431    -- over-clears (covers old 432 + new 216)

    Printf("Clearing existing sequences %d-%d and tags %d-%d...",
        SEQ_START, SEQ_END, TAG_START, TAG_END)
    Cmd(string.format("Delete Sequence %d Thru %d /nc", SEQ_START, SEQ_END))
    Cmd(string.format("Delete Tag %d Thru %d /nc", TAG_START, TAG_END))

    local seqIndex = SEQ_START
    local tagIndex = TAG_START
    local total, errors = 0, 0

    for _, mat in ipairs(MATRICKS) do
        for _, group in ipairs(PROP_GROUPS) do
            progText(string.format("Sequences: %s %s", mat.name, group.label))
            -- One tag per MATrick+Parameter group. MA3 tag exclusivity will
            -- release sibling sequences when one in the group fires.
            local groupTag = string.format("%s %s", mat.prefix, group.label)
            Cmd(string.format('Store Tag %d "%s"', tagIndex, groupTag))
            tagIndex = tagIndex + 1

            for _, v in ipairs(group.values) do
                local key     = fmtVal(v)
                local seqName = string.format("%s %s %s", mat.prefix, group.label, key)
                local icons   = ICONS[key]

                local ok, err = pcall(function()
                    Cmd(string.format('Store Sequence %d "%s"', seqIndex, seqName))
                    Cmd(string.format('Store Sequence "%s" Cue 1 /nc', seqName))
                    Cmd(string.format('Set Sequence "%s" Cue 1 Property "Command" "Call Macro \'%s\'"',
                        seqName, seqName))
                    -- Assign the group tag so this sequence belongs to the
                    -- exclusivity group.
                    Cmd(string.format('Assign Tag "%s" At Sequence "%s"', groupTag, seqName))
                    if icons then
                        Cmd(string.format('Assign Appearance %d At Sequence "%s"', icons.dk, seqName))
                        Cmd(string.format('Assign Appearance %d At Sequence "%s" Cue 1', icons.lt, seqName))
                    end
                end)
                if ok then total = total + 1 else
                    Printf("  ERROR: %s - %s", seqName, tostring(err))
                    errors = errors + 1
                end
                seqIndex = seqIndex + 1
                progStep()
            end
        end
    end

    Cmd(string.format('Set Sequence %d Thru %d Property "PreferCueAppearance" "Yes"',
        SEQ_START, seqIndex - 1))

    Printf("Phase 1a done: %d sequences, tags %d-%d, %d errors.",
        total, TAG_START, tagIndex - 1, errors)

    -- ----- Phase 1b: "All" master sequences (set value across all 5 standard
    -- MATricks at once). These live in their own index ranges to avoid clashing
    -- with the per-MATrick sequences above. -----
    Printf("Phase 1b: All-MATrick master sequences...")
    progText("All-MATrick master sequences...")
    local ALL_SEQ_START = 7601
    local ALL_TAG_START = 1501
    -- Clear prior All ranges
    Cmd(string.format("Delete Sequence %d Thru %d /nc", ALL_SEQ_START, ALL_SEQ_START + 399))
    Cmd(string.format("Delete Tag %d Thru %d /nc", ALL_TAG_START, ALL_TAG_START + 99))

    local aSeq = ALL_SEQ_START
    local aTag = ALL_TAG_START
    local aTotal = 0

    for _, group in ipairs(PROP_GROUPS) do
        local groupTag = string.format("All %s", group.label)
        Cmd(string.format('Store Tag %d "%s"', aTag, groupTag))
        aTag = aTag + 1

        for _, v in ipairs(group.values) do
            local key     = fmtVal(v)
            local seqName = string.format("All %s %s", group.label, key)
            local icons   = ICONS[key]
            local ok = pcall(function()
                Cmd(string.format('Store Sequence %d "%s"', aSeq, seqName))
                Cmd(string.format('Store Sequence "%s" Cue 1 /nc', seqName))
                Cmd(string.format('Set Sequence "%s" Cue 1 Property "Command" "Call Macro \'%s\'"',
                    seqName, seqName))
                Cmd(string.format('Assign Tag "%s" At Sequence "%s"', groupTag, seqName))
                if icons then
                    Cmd(string.format('Assign Appearance %d At Sequence "%s"', icons.dk, seqName))
                    Cmd(string.format('Assign Appearance %d At Sequence "%s" Cue 1', icons.lt, seqName))
                end
            end)
            if ok then aTotal = aTotal + 1 end
            aSeq = aSeq + 1
            progStep()
        end
    end

    Cmd(string.format('Set Sequence %d Thru %d Property "PreferCueAppearance" "Yes"',
        ALL_SEQ_START, aSeq - 1))

    Printf("Phase 1b done: %d All-master sequences (index %d-%d), tags %d-%d.",
        aTotal, ALL_SEQ_START, aSeq - 1, ALL_TAG_START, aTag - 1)

    -- ----- Phase 1c: Reset sequences (one per MATrick+Parameter group). Each
    -- calls its "{prefix} {label} Reset" macro and carries the reset icon. -----
    Printf("Phase 1c: Reset sequences...")
    progText("Reset sequences...")
    Cmd(string.format("Delete Sequence %d Thru %d /nc", RESET_SEQ_START, RESET_SEQ_START + 299))

    local rSeq = RESET_SEQ_START
    local rTotal = 0
    for _, mat in ipairs(MATRICKS) do
        for _, group in ipairs(PROP_GROUPS) do
            local seqName  = string.format("%s %s Reset", mat.prefix, group.label)
            local groupTag = string.format("%s %s", mat.prefix, group.label)
            local ok = pcall(function()
                Cmd(string.format('Store Sequence %d "%s"', rSeq, seqName))
                Cmd(string.format('Store Sequence "%s" Cue 1 /nc', seqName))
                Cmd(string.format('Set Sequence "%s" Cue 1 Property "Command" "Call Macro \'%s\'"',
                    seqName, seqName))
                -- Same group tag as the value sequences: firing the reset
                -- releases the active value via MA3 tag exclusivity.
                Cmd(string.format('Assign Tag "%s" At Sequence "%s"', groupTag, seqName))
                Cmd(string.format('Assign Appearance %d At Sequence "%s"', RESET_APP_DK, seqName))
                Cmd(string.format('Assign Appearance %d At Sequence "%s" Cue 1', RESET_APP_LT, seqName))
            end)
            if ok then rTotal = rTotal + 1 end
            rSeq = rSeq + 1
            progStep()
        end
    end
    Cmd(string.format('Set Sequence %d Thru %d Property "PreferCueAppearance" "Yes"',
        RESET_SEQ_START, rSeq - 1))

    Printf("Phase 1c done: %d Reset sequences (index %d-%d).",
        rTotal, RESET_SEQ_START, rSeq - 1)

    -- ----- Phase 1d: "Reset All" sequences (one per parameter). Each calls its
    -- "Reset All {label}" macro, which triggers the five standard MATrick reset
    -- sequences at once. Carries the reset icon, sits in the All master row. -----
    Printf("Phase 1d: Reset All sequences...")
    progText("Reset All sequences...")
    local RA_SEQ_START = 8201   -- 24 sequences
    Cmd(string.format("Delete Sequence %d Thru %d /nc", RA_SEQ_START, RA_SEQ_START + 49))

    local raSeq = RA_SEQ_START
    local raTotal = 0
    for _, group in ipairs(PROP_GROUPS) do
        local seqName  = string.format("Reset All %s", group.label)
        local groupTag = string.format("All %s", group.label)
        local ok = pcall(function()
            Cmd(string.format('Store Sequence %d "%s"', raSeq, seqName))
            Cmd(string.format('Store Sequence "%s" Cue 1 /nc', seqName))
            Cmd(string.format('Set Sequence "%s" Cue 1 Property "Command" "Call Macro \'%s\'"',
                seqName, seqName))
            -- Same tag as the All value sequences: firing Reset All releases
            -- the active All value via exclusivity.
            Cmd(string.format('Assign Tag "%s" At Sequence "%s"', groupTag, seqName))
            Cmd(string.format('Assign Appearance %d At Sequence "%s"', RESET_APP_DK, seqName))
            Cmd(string.format('Assign Appearance %d At Sequence "%s" Cue 1', RESET_APP_LT, seqName))
        end)
        if ok then raTotal = raTotal + 1 end
        raSeq = raSeq + 1
        progStep()
    end
    Cmd(string.format('Set Sequence %d Thru %d Property "PreferCueAppearance" "Yes"',
        RA_SEQ_START, raSeq - 1))

    Printf("Phase 1d done: %d Reset All sequences (index %d-%d).",
        raTotal, RA_SEQ_START, raSeq - 1)
    progStop()
end

-------------------------------------------------------------------------------
-- PHASE 2: Layouts
-------------------------------------------------------------------------------
local function ensureSeparatorAppearance()
    Cmd(string.format('Store Appearance %d "%s" /nc', SEP_APP_INDEX, SEP_APP_NAME))
    Cmd(string.format('Set Appearance %d Property "BackR" 51', SEP_APP_INDEX))
    Cmd(string.format('Set Appearance %d Property "BackG" 34', SEP_APP_INDEX))
    Cmd(string.format('Set Appearance %d Property "BackB" 0',  SEP_APP_INDEX))
    Printf("Separator appearance '%s' at slot %d.", SEP_APP_NAME, SEP_APP_INDEX)
end

local function buildSequenceIndex()
    local map = {}
    local pool = DataPool().Sequences
    for i = 1, 9999 do
        local ok, obj = pcall(function() return pool[i] end)
        if ok and obj ~= nil then
            local n = trim(obj.name)
            if n ~= "" then map[n] = i end
        end
    end
    return map
end

-- Build one layout for a family + MATrick group (Params or Effects).
local function buildOneLayout(family, group, slot, seqMap)
    local layoutName = string.format("MATrick %s - %s", family.name, group.suffix)
    Printf("  Layout \"%s\" @ slot %d", layoutName, slot)
    Cmd(string.format('Store Layout %d "%s" /nc', slot, layoutName))

    local plan = {}
    local rowY = 0

    -- Helper: lay out the X and Y rows for one prefix (a MATrick or "All").
    local function addMatrickRows(prefix, rowLabelName)
        for _, ag in ipairs(family.axisGroups) do
            local cursorX = 0
            table.insert(plan, {
                kind="sep", text = rowLabelName .. " " .. ag.axis,
                px=cursorX, py=rowY, w=SEP_W+40, h=CELL_H })
            cursorX = cursorX + SEP_W + 40 + SEP_GAP

            for _, param in ipairs(ag.params) do
                table.insert(plan, {
                    kind="sep", text=param.label,
                    px=cursorX, py=rowY, w=SEP_W, h=CELL_H })
                cursorX = cursorX + SEP_W + SEP_GAP

                -- Reset cell, placed before this parameter's value cells.
                -- Per-MATrick rows use "{prefix} {label} Reset".
                -- The "All" master row uses "Reset All {label}" instead.
                local resetName
                if prefix == "All" then
                    resetName = string.format("Reset All %s", param.label)
                else
                    resetName = string.format("%s %s Reset", prefix, param.label)
                end
                local ridx = seqMap[resetName]
                if ridx then
                    table.insert(plan, {
                        kind="seq", index=ridx,
                        px=cursorX, py=rowY, w=CELL_W, h=CELL_H })
                    cursorX = cursorX + CELL_W + CELL_GAP
                end

                for _, v in ipairs(param.values) do
                    local seqName = string.format("%s %s %s", prefix, param.label, fmtVal(v))
                    local idx = seqMap[seqName]
                    if idx then
                        table.insert(plan, {
                            kind="seq", index=idx,
                            px=cursorX, py=rowY, w=CELL_W, h=CELL_H })
                    else
                        Printf("    WARN: missing sequence %s", seqName)
                    end
                    cursorX = cursorX + CELL_W + CELL_GAP
                end
                cursorX = cursorX + SEP_GAP
            end
            rowY = rowY + CELL_H + ROW_GAP
        end
    end

    -- Params layout gets a master "All" row first (so after Y-flip it ends on top).
    if group.suffix == "Params" then
        addMatrickRows("All", "ALL")
    end

    for _, matName in ipairs(group.order) do
        addMatrickRows(prefixFor(matName), matName)
    end

    -- Invert Y so first MATrick lands at the top
    local maxPy = 0
    for _, s in ipairs(plan) do if s.py > maxPy then maxPy = s.py end end
    for _, s in ipairs(plan) do s.py = maxPy - s.py end

    -- PASS 1: create elements
    for i, spec in ipairs(plan) do
        if spec.kind == "seq" then
            Cmd(string.format('Assign Sequence %d At Layout "%s" /nc', spec.index, layoutName))
        else
            Cmd(string.format('Store Layout "%s".%d', layoutName, i))
        end
    end

    -- PASS 2a: bulk-hide chrome across whole range (one command each)
    local rangeAddr = string.format('Layout "%s".1 Thru', layoutName)
    Cmd(string.format('Set %s Property "visibilityBorder" "Hidden"', rangeAddr))
    Cmd(string.format('Set %s Property "visibilityIndicatorBar" "Hidden"', rangeAddr))
    Cmd(string.format('Set %s Property "visibilityObjectName" "Hidden"', rangeAddr))
    Cmd(string.format('Set %s Property "visibilityId" "Hidden"', rangeAddr))
    Cmd(string.format('Set %s Property "visibilityCid" "Hidden"', rangeAddr))
    Cmd(string.format('Set %s Property "visibilityValue" "Hidden"', rangeAddr))

    -- PASS 2b: position + size per element
    for i, spec in ipairs(plan) do
        local addr = string.format('Layout "%s".%d', layoutName, i)
        Cmd(string.format('Set %s Property "posX" %d',   addr, ORIGIN_X + spec.px))
        Cmd(string.format('Set %s Property "posY" %d',   addr, spec.py))
        Cmd(string.format('Set %s Property "Width" %d',  addr, spec.w))
        Cmd(string.format('Set %s Property "Height" %d', addr, spec.h))
        if i % 25 == 0 then coroutine.yield() end
    end

    -- PASS 2c: separator styling (few)
    for i, spec in ipairs(plan) do
        if spec.kind == "sep" then
            local addr = string.format('Layout "%s".%d', layoutName, i)
            Cmd(string.format('Set %s Property "customTextText" "%s"', addr, spec.text))
            Cmd(string.format('Set %s Property "customTextColor" "%s"', addr, SEP_TEXT_COLOR))
            Cmd(string.format('Set %s Property "customTextSize" %d', addr, SEP_TEXT_SIZE))
            Cmd(string.format('Set %s Property "Appearance" "%s"', addr, SEP_APP_NAME))
            Cmd(string.format('Set %s Property "visibilityElement" "Visible"', addr))
        end
    end

    Printf("    %d elements built.", #plan)
end

local function buildLayouts(startSlot)
    Printf("=== PHASE 2: Layouts ===")
    progStart("MATrick Builder: layouts", #FAMILIES * #LAYOUT_GROUPS)
    progText("Indexing sequences...")
    ensureSeparatorAppearance()
    Printf("Indexing sequences...")
    local seqMap = buildSequenceIndex()
    local cnt = 0
    for _ in pairs(seqMap) do cnt = cnt + 1 end
    Printf("Indexed %d sequences.", cnt)

    local layouts = DataPool().Layouts
    local slot = startSlot

    for _, family in ipairs(FAMILIES) do
        for _, group in ipairs(LAYOUT_GROUPS) do
            -- advance to next free slot
            while true do
                local ok, lay = pcall(function() return layouts[slot] end)
                if not ok or lay == nil or trim(lay.name) == "" then break end
                slot = slot + 1
            end
            progText(string.format("Layout: %s - %s", family.name, group.suffix))
            buildOneLayout(family, group, slot, seqMap)
            slot = slot + 1
            _progN = _progN + 1
            if _prog then pcall(SetProgress, _prog, _progN) end
            coroutine.yield()
        end
    end
    progStop()
    Printf("Phase 2 done: %d layouts (8 families x 2 groups).", #FAMILIES * 2)
end

-------------------------------------------------------------------------------
-- UI
-------------------------------------------------------------------------------
local function showUI(overlay)
    local result, done = nil, false
    local startSlot = "1"

    local base = overlay:Append('BaseInput')
    base.H = 420; base.W = 960
    base.Columns = 1; base.Rows = 3
    base[1][1].SizePolicy = 'Fixed';   base[1][1].Size = 55
    base[1][2].SizePolicy = 'Stretch'
    base[1][3].SizePolicy = 'Fixed';   base[1][3].Size = 72
    base.AutoClose = 'No'; base.CloseOnEscape = 'Yes'
    base.BackColor = UI_BG_IDX

    local tb = base:Append('TitleBar')
    tb.Columns = 2; tb.Rows = 1; tb.Anchors = '0,0'
    local ttl = tb:Append('TitleButton')
    ttl.Text = 'MATrick Builder  -  Sequences + Layouts'
    ttl.Font = 'Regular28'; ttl.Anchors = '0,0'
    local cls = tb:Append('CloseButton')
    cls.Anchors = '1,0'; cls.plugincomponent = myHandle; cls.clicked = 'onClose'

    local scroll = base:Append('ScrollBox')
    scroll.Anchors = '0,1'

    local i1 = scroll:Append('UIObject')
    i1.Text = 'Phase 1: builds 3080 sequences + 240 tags (seq 5001+, tags 1001+).'
    i1.Font = 'Regular24'; i1.TextalignmentH = 'Centre'
    i1.H = 44; i1.Anchors = '0,0,1,0'; i1.X = 0; i1.Y = 18

    local i2 = scroll:Append('UIObject')
    i2.Text = 'Phase 2: adds 16 layouts in free slots from the start slot.'
    i2.Font = 'Regular24'; i2.TextalignmentH = 'Centre'
    i2.H = 44; i2.Anchors = '0,0,1,0'; i2.X = 0; i2.Y = 66

    local i3 = scroll:Append('UIObject')
    i3.Text = 'DELETES seq 5001-7556 + 7601-8250, tags 1001-1432 + 1501-1600.'
    i3.Font = 'Regular24'; i3.TextalignmentH = 'Centre'
    i3.H = 44; i3.Anchors = '0,0,1,0'; i3.X = 0; i3.Y = 114

    local lbl = scroll:Append('UIObject')
    lbl.Text = 'Layout Start Slot'; lbl.Font = 'Regular28'
    lbl.TextalignmentH = 'Right'; lbl.W = 360; lbl.H = 78; lbl.X = 60; lbl.Y = 178
    local ed = scroll:Append('LineEdit')
    ed.Text = startSlot; ed.Font = 'Regular28'; ed.TextalignmentH = 'Centre'
    ed.W = 420; ed.H = 78; ed.X = 440; ed.Y = 178
    ed.plugincomponent = myHandle; ed.textchanged = 'onSlot'

    local g = base:Append('UILayoutGrid')
    g.Columns = 2; g.Rows = 1; g.H = 72; g.Anchors = '0,2'
    local ok = g:Append('Button')
    ok.Anchors = '0,0'; ok.Text = 'Build All'; ok.TextalignmentH = 'Centre'
    ok.HasHover = 'Yes'; ok.plugincomponent = myHandle; ok.clicked = 'onBuild'
    local cn = g:Append('Button')
    cn.Anchors = '1,0'; cn.Text = 'Cancel'; cn.TextalignmentH = 'Centre'
    cn.HasHover = 'Yes'; cn.plugincomponent = myHandle; cn.clicked = 'onClose'

    base:WaitInit(); FindBestFocus(base)

    signalTable.onSlot  = function(c) startSlot = c.content or startSlot end
    signalTable.onBuild = function()
        local sn = math.floor(tonumber(startSlot) or 0)
        if sn < 1 then ErrPrintf("Layout start slot must be >= 1."); return end
        result = { startSlot = sn }
        overlay:ClearUIChildren(); done = true
    end
    signalTable.onClose = function()
        overlay:ClearUIChildren(); done = true
    end

    repeat coroutine.yield() until done
    return result
end

-------------------------------------------------------------------------------
-- Entry point
-------------------------------------------------------------------------------
function main()
    local overlay = GetFocusDisplay().ScreenOverlay
    local cfg = showUI(overlay)
    if not cfg then Printf("MATrick Builder: cancelled."); return end

    -- Let the first dialog finish closing before opening the confirm, so the
    -- tap that closed it can't also answer the confirm.
    coroutine.yield(); coroutine.yield()

    local msg = "This DELETES and rebuilds sequences 5001-7556 and 7601-8250\n" ..
        "and tags 1001-1432 and 1501-1600, then adds 16 layouts\n" ..
        "starting at layout slot " .. tostring(cfg.startSlot) .. ".\n\nContinue?"
    local res = MessageBox({
        title    = "MATrick Builder - Build All",
        message  = msg,
        commands = { { value = 1, name = "Build All" }, { value = 0, name = "Cancel" } },
    })
    local choice = (type(res) == "table") and res.result or nil
    Printf("MATrick Builder: confirm -> result=%s", tostring(choice))
    if choice ~= 1 then Printf("MATrick Builder: cancelled at confirm -- nothing changed."); return end

    Printf("======================================")
    Printf("=== MATrick Builder - BUILD ALL ===")
    Printf("======================================")

    -- Not wrapped in pcall: the build yields for the progress bar, and
    -- yielding across pcall is not safe on every Lua version.
    buildSequences()
    buildLayouts(cfg.startSlot)
    progStop()

    Printf("======================================")
    Printf("=== MATrick Builder complete. ===")
    Printf("======================================")
end

return main
