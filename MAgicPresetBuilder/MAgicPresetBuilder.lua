--[[
    MAgicPresetBuilder.lua
    GrandMA3 Plugin -- Version compatible: 2.4.2+

    PURPOSE:
        Builds a MAgic (multi-step) preset by combining two or more existing
        presets from the same preset pool, then converts it to Universal.

    SCROLLBAR PATTERN (confirmed from CreateFixtureGroups.lua Dialog 2):
        - ScrollBox appended to base with Anchors = '0,1'  (named 'mpbScroll')
        - ScrollBarV appended to base (sibling, NOT child) with Anchors = '0,1'
        - ScrollBarV.ScrollTarget = ScrollBox object (direct reference)

    CLOSE BUTTON:
        - CloseButton inside TitleBar with W=55, H=55 (matches reference)
        - TitleBar column 1 (close btn col) fixed via titleBar[1][2].SizePolicy

    BACKGROUND:
        - BaseInput.BackColor = COL_BG  (fully opaque dark, RGBA 1C1C1CFF)
--]]

-------------------------------------------------------------------------------
-- Plugin argument binding
-------------------------------------------------------------------------------
local pluginName    = select(1, ...)
local componentName = select(2, ...)
local signalTable   = select(3, ...)
local myHandle      = select(4, ...)

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------
local PLUGIN_VERSION = "2.1.0"
local DIALOG_W  = 1100
local DIALOG_H  = 820

local POOL_MAP = {
    { name = "Dimmer",   index = 1  },
    { name = "Position", index = 2  },
    { name = "Gobo",     index = 3  },
    { name = "Color",    index = 4  },
    { name = "Beam",     index = 5  },
    { name = "Focus",    index = 6  },
    { name = "Control",  index = 7  },
    { name = "Shapers",  index = 8  },
    { name = "Video",    index = 9  },
    { name = "All 1",    index = 21 },
    { name = "All 2",    index = 22 },
    { name = "All 3",    index = 23 },
    { name = "All 4",    index = 24 },
}

-------------------------------------------------------------------------------
-- Color theme
-------------------------------------------------------------------------------
local COL_BG        = nil   -- #1A0A2E deep purple-black    (BaseInput bg)
local COL_TITLE     = nil   -- #2D0A4E dark purple           (title bar)
local COL_ACCENT1   = nil   -- #FF2D78 fuchsia               (section headers 1, 3, 5)
local COL_ACCENT2   = nil   -- #00E5B0 seafoam green         (section headers 2, 4 + pool btn)
local COL_ACCENT3   = nil   -- #FFB347 apricot               (options header)
local COL_OK        = nil   -- #00E5B0 seafoam (Create btn)
local COL_ABORT     = nil   -- #FF2D78 fuchsia (Abort btn)
local COL_ADD       = nil   -- #FFB347 apricot (+ Add Preset)
local COL_REMOVE    = nil   -- #FF2D78 fuchsia (x remove row)
local COL_CHECKED   = nil   -- #00E5B0 seafoam (checkbox ON)
local COL_UNCHECKED = nil   -- #3A2050 muted purple (checkbox OFF / locked x)
local COL_HINT      = nil   -- #2A0A3E dark purple (hint text bg)

local function getOrCreateColorDef(name, rgba)
    local colorGroups = Root().ColorTheme.ColorGroups
    if not colorGroups then
        ErrPrintf("[MAgicPresetBuilder] ColorTheme.ColorGroups not found")
        return nil
    end
    local cfgGroup = colorGroups["CFG"]
    if not cfgGroup then
        local gIdx = 1
        while colorGroups[gIdx] ~= nil do gIdx = gIdx + 1 end
        Cmd("cd root / nu"); Cmd("cd \"ColorTheme\" / nu")
        Cmd("cd \"ColorGroups\" / nu")
        Cmd("store " .. tostring(gIdx) .. " /nu")
        Cmd("label " .. tostring(gIdx) .. " \"CFG\" /nu")
        Cmd("cd root / nu")
        cfgGroup = colorGroups["CFG"]
        if not cfgGroup then
            ErrPrintf("[MAgicPresetBuilder] Failed to create CFG color group")
            return nil
        end
    end
    local entry = cfgGroup[name]
    local entryIdx
    if entry then
        entryIdx = entry.index
    else
        entryIdx = 1
        while cfgGroup[entryIdx] ~= nil do entryIdx = entryIdx + 1 end
        Cmd("cd root / nu"); Cmd("cd \"ColorTheme\" / nu")
        Cmd("cd \"ColorGroups\" / nu"); Cmd("cd \"CFG\" / nu")
        Cmd("store " .. tostring(entryIdx) .. " /nu")
        Cmd("label " .. tostring(entryIdx) .. " \"" .. name .. "\" /nu")
        Cmd("cd root / nu")
        entry = cfgGroup[name]
        if not entry then return nil end
        entryIdx = entry.index
    end
    Cmd("cd root / nu"); Cmd("cd \"ColorTheme\" / nu")
    Cmd("cd \"ColorGroups\" / nu"); Cmd("cd \"CFG\" / nu")
    Cmd(string.format('set %d RGBA="%s" /nu', entryIdx, rgba))
    Cmd("cd root / nu")
    return "CFG." .. name
end

local function initColors()
    COL_BG        = getOrCreateColorDef("MPB_BG",      "1A0A2EFF")
    COL_TITLE     = getOrCreateColorDef("MPB_Title",   "2D0A4EFF")
    COL_ACCENT1   = getOrCreateColorDef("MPB_Acc1",    "FF2D78FF")
    COL_ACCENT2   = getOrCreateColorDef("MPB_Acc2",    "00E5B0FF")
    COL_ACCENT3   = getOrCreateColorDef("MPB_Acc3",    "FFB347FF")
    COL_OK        = getOrCreateColorDef("MPB_OK",      "00E5B0FF")
    COL_ABORT     = getOrCreateColorDef("MPB_Abort",   "FF2D78FF")
    COL_ADD       = getOrCreateColorDef("MPB_Add",     "FFB347FF")
    COL_REMOVE    = getOrCreateColorDef("MPB_Remove",  "FF2D78FF")
    COL_CHECKED   = getOrCreateColorDef("MPB_ChkOn",   "00E5B0FF")
    COL_UNCHECKED = getOrCreateColorDef("MPB_ChkOff",  "3A2050FF")
    COL_HINT      = getOrCreateColorDef("MPB_Hint",    "2A0A3EFF")
end

-------------------------------------------------------------------------------
-- Utility
-------------------------------------------------------------------------------
local function trim(s) return (s or ""):match("^%s*(.-)%s*$") end

local function getPresetPool(poolIndex)
    local pp = DataPool().PresetPools
    return pp and pp[poolIndex] or nil
end

local function getPresetInPool(pool, slotNum)
    return pool and pool[slotNum] or nil
end

-- Search a pool for a preset whose name matches (case-insensitive).
-- Returns the slot number, or nil if not found.
local function findPresetByName(pool, searchName)
    if not pool or trim(searchName) == "" then return nil end
    local lower = searchName:lower()
    local i = 1
    while pool[i] ~= nil do
        local p = pool[i]
        if p.name and p.name:lower() == lower then
            return i
        end
        i = i + 1
    end
    return nil
end

local function nextFreePresetSlot(pool)
    if not pool then return 1 end
    local i = 1
    while pool[i] ~= nil do i = i + 1 end
    return i
end

-- Read the current programmer selection (in selection order) and return a
-- fixture expression like "Fixture 11+12+15". Returns nil + reason on failure.
-- Lets the user build the selection with console keys (Fixture 1 Thru 20)
-- instead of typing into the LineEdit.
local function selectionToFixtureExpr(verbose)
    local function dbg(fmt, ...)
        if verbose then Printf("[MPB sel] " .. fmt, ...) end
    end
    local okC, count = pcall(SelectionCount)
    dbg("SelectionCount ok=%s value=%s", tostring(okC), tostring(count))
    if not okC then return nil, "SelectionCount() error: " .. tostring(count) end
    count = tonumber(count) or 0
    if count == 0 then return nil, "No fixtures selected (SelectionCount = 0)." end

    local ids, seen = {}, {}
    local okF, idx = pcall(SelectionFirst)
    dbg("SelectionFirst ok=%s value=%s", tostring(okF), tostring(idx))
    if not okF then return nil, "SelectionFirst() error: " .. tostring(idx) end
    local guard = 0
    while idx and guard < 10000 do
        guard = guard + 1
        local okS, sf = pcall(GetSubfixture, idx)
        local fid = nil
        if okS and sf then
            local okP, v = pcall(function() return sf.fid end)
            fid = okP and v or nil
        end
        if guard <= 3 then
            local nm = (okS and sf) and tostring(sf.name) or "?"
            dbg("  idx=%s GetSubfixture ok=%s handle=%s name=%s fid=%s",
                tostring(idx), tostring(okS), tostring(sf), nm, tostring(fid))
        end
        if fid ~= nil and tostring(fid) ~= "" and not seen[tostring(fid)] then
            seen[tostring(fid)] = true
            table.insert(ids, tostring(fid))
        end
        local okN, nxt = pcall(SelectionNext, idx)
        if not okN then dbg("SelectionNext error: %s", tostring(nxt)); break end
        idx = nxt
    end
    dbg("collected %d fixture IDs", #ids)
    if #ids == 0 then
        return nil, "Selection read but no fixture IDs found -- see [MPB sel] lines."
    end
    return "Fixture " .. table.concat(ids, "+"), #ids
end

-------------------------------------------------------------------------------
-- UI helpers
-------------------------------------------------------------------------------
local function buildTitleBar(base, titleText)
    local titleBar              = base:Append('TitleBar')
    titleBar.Columns            = 2
    titleBar.Rows               = 1
    titleBar.Anchors            = '0,0'
    titleBar.BackColor          = COL_TITLE

    local titleBtn              = titleBar:Append('TitleButton')
    titleBtn.Text               = titleText
    titleBtn.Font               = 'Regular28'
    titleBtn.Anchors            = '0,0'

    -- CloseButton: let TitleBar size it naturally -- no W/H override needed.
    -- The TitleBar layout engine constrains it correctly on its own.
    local closeBtn              = titleBar:Append('CloseButton')
    closeBtn.Anchors            = '1,0'
    closeBtn.plugincomponent    = myHandle
    return closeBtn
end

local function buildFooter(base, anchorRow, primaryLabel)
    local grid                  = base:Append('UILayoutGrid')
    grid.Columns                = 2
    grid.Rows                   = 1
    grid.H                      = 70
    grid.Anchors                = '0,' .. anchorRow

    local primary               = grid:Append('Button')
    primary.Anchors             = '0,0'
    primary.Text                = primaryLabel
    primary.TextalignmentH      = 'Centre'
    primary.HasHover            = 'Yes'
    primary.plugincomponent     = myHandle
    primary.BackColor           = COL_OK

    local abort                 = grid:Append('Button')
    abort.Anchors               = '1,0'
    abort.Text                  = 'Abort'
    abort.TextalignmentH        = 'Centre'
    abort.HasHover              = 'Yes'
    abort.plugincomponent       = myHandle
    abort.BackColor             = COL_ABORT

    return primary, abort
end

-------------------------------------------------------------------------------
-- Main UI
-------------------------------------------------------------------------------
local function showMainUI(overlay, seeds)
    local result        = nil
    local done          = false

    -- Seed state from a prior rebuild, or start fresh
    local s             = seeds or {}
    local outputName    = s._name    or ""
    local outputSlot    = s._slot    or ""
    local fixtureExpr   = s._fix     or ""
    if fixtureExpr == "" then
        Printf("[MAgicPresetBuilder] Checking selection at launch...")
        local expr, info = selectionToFixtureExpr(true)
        if expr then fixtureExpr = expr
        else Printf("[MAgicPresetBuilder] Launch selection: %s", tostring(info)) end
    end
    local poolIdx       = s._poolIdx or 1
    local embedPresets  = s._embed   or false
    -- inputMode: "slot" | "name" | "hardvalue"
    local inputMode     = s._inputMode or "slot"

    local presetRows    = {}
    local _seedRows     = s._rows or s.rows or {}   -- rows from prior rebuild to pre-fill
    local addBtn        = nil
    local hdrOpts       = nil
    local chkEmbed      = nil
    local embedNote     = nil

    local labelW  = 260
    local inputW  = 540   -- slightly narrower to leave room for scrollbar column
    local rowH    = 72
    local gap     = 16
    local padX    = 30
    local sectionY = 0

    local function poolName() return POOL_MAP[poolIdx].name end
    local function currentPoolLabel()
        return "Pool:  " .. poolName() .. "   (tap to cycle)"
    end

    -- ?? Base container ????????????????????????????????????????????????????????
    -- base.Columns stays at 1; the ScrollBarV with Anchors='1,1' will implicitly
    -- create a second column and size itself to its own width.
    local base                  = overlay:Append('BaseInput')
    base.H                      = DIALOG_H
    base.W                      = DIALOG_W
    base.Columns                = 1
    base.Rows                   = 3
    base[1][1].SizePolicy       = 'Fixed'
    base[1][1].Size             = 55       -- title bar
    base[1][2].SizePolicy       = 'Stretch'
    base[1][3].SizePolicy       = 'Fixed'
    base[1][3].Size             = 70       -- footer
    base.AutoClose              = 'No'
    base.CloseOnEscape          = 'Yes'
    base.BackColor              = COL_BG   -- fully opaque dark background

    local closeBtn = buildTitleBar(base, 'MAgic Preset Builder  v' .. PLUGIN_VERSION)
    closeBtn.clicked = 'mpbClose'

    -- ?? ScrollBox + ScrollBarV (confirmed pattern from CreateFixtureGroups) ???
    -- Both are children of base (siblings, NOT parent/child).
    -- ScrollBox occupies column 0, row 1 (the stretch row).
    -- ScrollBarV occupies column 1, row 1 -- creates a narrow auto-width column.
    -- ScrollTarget uses a relative path: ../  = up to base,  then named child.
    local sc                    = base:Append('ScrollBox')
    sc.Name                     = 'mpbScroll'
    sc.Anchors                  = '0,1'

    local scrollBarV            = base:Append('ScrollBarV')
    scrollBarV.ScrollTarget     = sc      -- direct object reference, not a path string
    scrollBarV.Anchors          = '0,1'  -- same column/row as ScrollBox; MA3 overlays it on the right edge

    -- ?? Layout helpers ????????????????????????????????????????????????????????
    -- Accent colors rotate: fuchsia ? seafoam ? apricot ? fuchsia ?
    local _accentCycle = { COL_ACCENT1, COL_ACCENT2, COL_ACCENT3 }
    local _accentIdx   = 0
    local function nextAccent()
        _accentIdx = (_accentIdx % 3) + 1
        return _accentCycle[_accentIdx]
    end

    local function sectionHeader(text)
        local hdr               = sc:Append('UIObject')
        hdr.Text                = text
        hdr.Font                = 'Regular24'
        hdr.TextalignmentH      = 'Left'
        hdr.W                   = DIALOG_W - 80   -- leave room for scrollbar
        hdr.H                   = 42
        hdr.X                   = padX
        hdr.Y                   = sectionY + 10
        hdr.BackColor           = nextAccent()
        sectionY                = sectionY + 58
        return hdr
    end

    local function hintLabel(text, x, y, w)
        local lbl               = sc:Append('UIObject')
        lbl.Text                = text
        lbl.Font                = 'Regular20'
        lbl.TextalignmentH      = 'Left'
        lbl.W                   = w or inputW
        lbl.H                   = 26
        lbl.X                   = x
        lbl.Y                   = y
        lbl.BackColor           = COL_HINT
        return lbl
    end

    local function labelCell(text, y)
        local lbl               = sc:Append('UIObject')
        lbl.Text                = text
        lbl.Font                = 'Regular28'
        lbl.TextalignmentH      = 'Right'
        lbl.W                   = labelW
        lbl.H                   = rowH
        lbl.X                   = padX
        lbl.Y                   = y
        return lbl
    end

    -- ?? Output Preset ?????????????????????????????????????????????????????????
    sectionHeader('Output Preset')

    labelCell('Preset Name', sectionY)
    local edName                = sc:Append('LineEdit')
    edName.Text                 = outputName
    edName.Font                 = 'Regular28'
    edName.TextalignmentH       = 'Left'
    edName.W                    = inputW
    edName.H                    = rowH
    edName.X                    = padX + labelW + gap
    edName.Y                    = sectionY
    edName.plugincomponent      = myHandle
    edName.textchanged          = 'mpbOnNameChanged'
    hintLabel('Leave blank -> auto-name from source presets',
        padX + labelW + gap, sectionY + rowH)
    sectionY = sectionY + rowH + 32

    labelCell('Target Slot #', sectionY)
    local edSlot                = sc:Append('LineEdit')
    edSlot.Text                 = tostring(outputSlot)
    edSlot.Font                 = 'Regular28'
    edSlot.TextalignmentH       = 'Left'
    edSlot.W                    = inputW
    edSlot.H                    = rowH
    edSlot.X                    = padX + labelW + gap
    edSlot.Y                    = sectionY
    edSlot.plugincomponent      = myHandle
    edSlot.textchanged          = 'mpbOnSlotChanged'
    hintLabel('Leave blank -> next free slot in selected pool',
        padX + labelW + gap, sectionY + rowH)
    sectionY = sectionY + rowH + 32

    -- ?? Preset Pool ???????????????????????????????????????????????????????????
    sectionHeader('Preset Pool')

    local btnPool               = sc:Append('Button')
    btnPool.Text                = currentPoolLabel()
    btnPool.Font                = 'Regular28'
    btnPool.TextalignmentH      = 'Centre'
    btnPool.W                   = labelW + inputW + gap
    btnPool.H                   = rowH
    btnPool.X                   = padX
    btnPool.Y                   = sectionY
    btnPool.plugincomponent     = myHandle
    btnPool.clicked             = 'mpbCyclePool'
    btnPool.HasHover            = 'Yes'
    btnPool.BackColor           = COL_ACCENT2
    sectionY = sectionY + rowH + 16

    -- ?? Source Fixtures ???????????????????????????????????????????????????????
    sectionHeader('Source Fixtures')

    labelCell('Fixture Selection', sectionY)
    local edFix                 = sc:Append('LineEdit')
    edFix.Text                  = fixtureExpr
    edFix.Font                  = 'Regular28'
    edFix.TextalignmentH        = 'Left'
    edFix.W                     = inputW - 200
    edFix.H                     = rowH
    edFix.X                     = padX + labelW + gap
    edFix.Y                     = sectionY
    edFix.plugincomponent       = myHandle
    edFix.textchanged           = 'mpbOnFixChanged'

    local btnGrab               = sc:Append('Button')
    btnGrab.Text                = 'Use Selection'
    btnGrab.Font                = 'Regular24'
    btnGrab.TextalignmentH      = 'Centre'
    btnGrab.W                   = 190
    btnGrab.H                   = rowH
    btnGrab.X                   = padX + labelW + gap + inputW - 190
    btnGrab.Y                   = sectionY
    btnGrab.BackColor           = COL_ACCENT2
    btnGrab.HasHover            = 'Yes'
    btnGrab.plugincomponent     = myHandle
    btnGrab.clicked             = 'mpbGrabSelection'
    hintLabel('Select on console (Fixture 1 Thru 20) then tap Use Selection -- or type a range / Group 1',
        padX + labelW + gap, sectionY + rowH, inputW + 40)
    sectionY = sectionY + rowH + 32

    -- ?? Source Presets ????????????????????????????????????????????????????????
    sectionHeader('Source Presets (in playback order)')

    -- Column header label (changes with mode)
    local chSlot                = sc:Append('UIObject')
    chSlot.Font                 = 'Regular20'
    chSlot.TextalignmentH       = 'Centre'
    chSlot.W                    = 130
    chSlot.H                    = 34
    chSlot.X                    = padX + 50
    chSlot.Y                    = sectionY

    -- Second column header (shown in hard value mode for "Value")
    local chVal                 = sc:Append('UIObject')
    chVal.Font                  = 'Regular20'
    chVal.TextalignmentH        = 'Centre'
    chVal.W                     = 100
    chVal.H                     = 34
    chVal.X                     = padX + 190
    chVal.Y                     = sectionY

    local chLbl                 = sc:Append('UIObject')
    chLbl.Font                  = 'Regular20'
    chLbl.TextalignmentH        = 'Left'
    chLbl.W                     = inputW - 160
    chLbl.H                     = 34
    chLbl.X                     = padX + 300
    chLbl.Y                     = sectionY

    -- Mode toggle button (3-way cycle)
    local btnModeToggle = nil
    local modeColors  = { slot = COL_ACCENT2, name = COL_ACCENT3, hardvalue = COL_ACCENT1 }
    local modeLabels  = { slot = 'Mode: Slot #', name = 'Mode: Name', hardvalue = 'Mode: Hard Value' }
    local function refreshModeHeader()
        btnModeToggle.Text      = modeLabels[inputMode]
        btnModeToggle.BackColor = modeColors[inputMode]
        if inputMode == "slot" then
            chSlot.Text = 'Slot #'
            chVal.Text  = ''
            chLbl.Text  = 'Preset Name (live preview)'
        elseif inputMode == "name" then
            chSlot.Text = 'Preset Name'
            chVal.Text  = ''
            chLbl.Text  = 'Resolved Slot (live preview)'
        else
            chSlot.Text = 'Attribute'
            chVal.Text  = 'Value'
            chLbl.Text  = 'Preview'
        end
    end

    btnModeToggle               = sc:Append('Button')
    btnModeToggle.Font          = 'Regular20'
    btnModeToggle.TextalignmentH = 'Centre'
    btnModeToggle.W             = 200
    btnModeToggle.H             = 34
    btnModeToggle.X             = padX + 300 + (inputW - 160) + 10
    btnModeToggle.Y             = sectionY
    btnModeToggle.HasHover      = 'Yes'
    btnModeToggle.plugincomponent = myHandle
    btnModeToggle.clicked       = 'mpbToggleInputMode'

    sectionY = sectionY + 40

    local rowBaseY  = sectionY
    local ROW_H     = 70
    local ROW_GAP   = 8

    -- Row geometry constants per mode
    local function rowGeom()
        if inputMode == "hardvalue" then
            -- [idx 40] [attr 200] [value 110] [preview ...] [x 56]
            return { attrW = 200, valW = 110, attrX = padX + 50, valX = padX + 260,
                     lblX = padX + 380, lblW = inputW - 220 }
        elseif inputMode == "name" then
            -- [idx 40] [name 280] [preview ...] [x 56]
            return { attrW = 280, valW = 0, attrX = padX + 50, valX = 0,
                     lblX = padX + 340, lblW = inputW - 120 }
        else
            -- slot: [idx 40] [slot 120] [preview ...] [x 56]
            return { attrW = 120, valW = 0, attrX = padX + 50, valX = 0,
                     lblX = padX + 190, lblW = inputW - 60 }
        end
    end

    -- Live preview label logic per mode
    local function refreshRowLabel(rowIdx)
        local row = presetRows[rowIdx]
        if not row or not row.labelObj then return end
        local pool = getPresetPool(POOL_MAP[poolIdx].index)
        if inputMode == "hardvalue" then
            local a = trim(row.attr  or "")
            local v = trim(row.value or "")
            if a == "" and v == "" then
                row.labelObj.Text      = '--'
                row.labelObj.BackColor = COL_HINT
            elseif a ~= "" and v ~= "" then
                row.labelObj.Text      = a .. ' @ ' .. v
                row.labelObj.BackColor = COL_HINT
            else
                row.labelObj.Text      = '(fill both fields)'
                row.labelObj.BackColor = COL_ABORT
            end
        elseif inputMode == "name" then
            local search = trim(row.slot or "")
            if search == "" then row.labelObj.Text = '--'; row.labelObj.BackColor = COL_HINT; return end
            local found = findPresetByName(pool, search)
            if found then
                row.labelObj.Text      = 'Slot ' .. tostring(found)
                row.labelObj.BackColor = COL_HINT
            else
                row.labelObj.Text      = '(no match)'
                row.labelObj.BackColor = COL_ABORT
            end
        else
            local slotN = tonumber(trim(row.slot or ""))
            if not slotN then row.labelObj.Text = '--'; row.labelObj.BackColor = COL_HINT; return end
            local p = getPresetInPool(pool, slotN)
            if p and p.name and trim(p.name) ~= "" then
                row.labelObj.Text      = p.name
                row.labelObj.BackColor = COL_HINT
            else
                row.labelObj.Text      = '(empty slot)'
                row.labelObj.BackColor = COL_HINT
            end
        end
    end

    local function refreshAllLabels()
        for i = 1, #presetRows do refreshRowLabel(i) end
    end

    local function addRowBtnY()
        return rowBaseY + #presetRows * (ROW_H + ROW_GAP) + 10
    end

    local function repositionFloating()
        local btnY  = addRowBtnY()
        local optY  = btnY + 72
        addBtn.Y    = btnY
        hdrOpts.Y   = optY
        chkEmbed.Y  = optY + 52
        embedNote.Y = optY + 52 + rowH + 4
    end

    local function addPresetRow(seedSlot, seedAttr, seedValue)
        local rowIdx = #presetRows + 1
        local rowY   = rowBaseY + (rowIdx - 1) * (ROW_H + ROW_GAP)
        local g      = rowGeom()

        -- Row index label
        local idxLbl            = sc:Append('UIObject')
        idxLbl.Text             = tostring(rowIdx) .. '.'
        idxLbl.Font             = 'Regular28'
        idxLbl.TextalignmentH   = 'Right'
        idxLbl.W                = 40
        idxLbl.H                = ROW_H
        idxLbl.X                = padX
        idxLbl.Y                = rowY

        -- Primary edit field: slot# / preset name / attribute name
        local ed                = sc:Append('LineEdit')
        ed.Text                 = (inputMode == "hardvalue") and (seedAttr or '') or (seedSlot or '')
        ed.Font                 = 'Regular28'
        ed.TextalignmentH       = (inputMode == "slot") and 'Centre' or 'Left'
        ed.W                    = g.attrW
        ed.H                    = ROW_H
        ed.X                    = g.attrX
        ed.Y                    = rowY
        ed.plugincomponent      = myHandle
        ed.Name                 = 'mpbPresetSlot_' .. tostring(rowIdx)
        ed.textchanged          = 'mpbOnPresetSlotChanged'

        -- Value edit field (hard value mode only -- zero width otherwise)
        local edVal             = sc:Append('LineEdit')
        edVal.Text              = seedValue or ''
        edVal.Font              = 'Regular28'
        edVal.TextalignmentH    = 'Centre'
        edVal.W                 = (inputMode == "hardvalue") and g.valW or 0
        edVal.H                 = (inputMode == "hardvalue") and ROW_H or 0
        edVal.X                 = g.valX
        edVal.Y                 = (inputMode == "hardvalue") and rowY or -200
        edVal.plugincomponent   = myHandle
        edVal.Name              = 'mpbPresetValue_' .. tostring(rowIdx)
        edVal.textchanged       = 'mpbOnPresetValueChanged'

        -- Live preview label
        local lbl               = sc:Append('UIObject')
        lbl.Text                = '--'
        lbl.Font                = 'Regular28'
        lbl.TextalignmentH      = 'Left'
        lbl.W                   = g.lblW
        lbl.H                   = ROW_H
        lbl.X                   = g.lblX
        lbl.Y                   = rowY
        lbl.BackColor           = COL_HINT

        -- Remove button
        local removeBtn         = sc:Append('Button')
        removeBtn.Text          = 'x'
        removeBtn.Font          = 'Regular28'
        removeBtn.TextalignmentH = 'Centre'
        removeBtn.W             = 56
        removeBtn.H             = ROW_H
        removeBtn.X             = g.lblX + g.lblW + 10
        removeBtn.Y             = rowY
        removeBtn.BackColor     = (rowIdx <= 2) and COL_UNCHECKED or COL_REMOVE
        removeBtn.HasHover      = 'Yes'
        removeBtn.plugincomponent = myHandle
        removeBtn.Name          = 'mpbRemoveRow_' .. tostring(rowIdx)
        removeBtn.clicked       = 'mpbOnRemoveRow'

        -- Pick button: opens the built-in preset picker for this step
        local pickBtn = nil
        if inputMode ~= "hardvalue" then
            pickBtn                 = sc:Append('Button')
            pickBtn.Text            = 'Pick'
            pickBtn.Font            = 'Regular24'
            pickBtn.TextalignmentH  = 'Centre'
            pickBtn.W               = 110
            pickBtn.H               = ROW_H
            pickBtn.X               = g.lblX + g.lblW + 76
            pickBtn.Y               = rowY
            pickBtn.BackColor       = COL_ACCENT2
            pickBtn.HasHover        = 'Yes'
            pickBtn.plugincomponent = myHandle
            pickBtn.Name            = 'mpbPickRow_' .. tostring(rowIdx)
            pickBtn.clicked         = 'mpbOnPickRow'
        end

        local rowData = {
            slot      = (inputMode ~= "hardvalue") and (seedSlot or '') or '',
            attr      = (inputMode == "hardvalue") and (seedAttr or '') or '',
            value     = seedValue or '',
            slotEdit  = ed,
            valueEdit = edVal,
            labelObj  = lbl,
            idxLabel  = idxLbl,
            removeBtn = removeBtn,
        }
        presetRows[rowIdx] = rowData
        refreshRowLabel(rowIdx)
        return rowData
    end

    -- Seed rows from prior rebuild, or default two empty rows
    local seedCount = #_seedRows
    if seedCount >= 2 then
        for _, sr in ipairs(_seedRows) do
            addPresetRow(sr.slot, sr.attr, sr.value)
        end
    else
        addPresetRow("", "", "")
        addPresetRow("", "", "")
    end

    -- Apply initial mode header text now that btnModeToggle exists
    refreshModeHeader()

    -- ?? Add-row button ????????????????????????????????????????????????????????
    addBtn                      = sc:Append('Button')
    addBtn.Text                 = '+ Add Preset'
    addBtn.Font                 = 'Regular28'
    addBtn.TextalignmentH       = 'Centre'
    addBtn.W                    = 260
    addBtn.H                    = 58
    addBtn.X                    = padX
    addBtn.Y                    = addRowBtnY()
    addBtn.BackColor            = COL_ADD
    addBtn.HasHover             = 'Yes'
    addBtn.plugincomponent      = myHandle
    addBtn.clicked              = 'mpbAddRow'

    -- ?? Options ???????????????????????????????????????????????????????????????
    local optY0 = addRowBtnY() + 72

    hdrOpts                     = sc:Append('UIObject')
    hdrOpts.Text                = 'Options'
    hdrOpts.Font                = 'Regular24'
    hdrOpts.TextalignmentH      = 'Left'
    hdrOpts.W                   = DIALOG_W - 80
    hdrOpts.H                   = 42
    hdrOpts.X                   = padX
    hdrOpts.Y                   = optY0
    hdrOpts.BackColor           = COL_ACCENT3

    chkEmbed                    = sc:Append('Button')
    chkEmbed.Text               = embedPresets
        and '[X]  Embed source presets in MAgic preset'
        or  '[  ]  Embed source presets in MAgic preset'
    chkEmbed.Font               = 'Regular28'
    chkEmbed.TextalignmentH     = 'Left'
    chkEmbed.W                  = labelW + inputW + gap
    chkEmbed.H                  = rowH
    chkEmbed.X                  = padX
    chkEmbed.Y                  = optY0 + 52
    chkEmbed.BackColor          = embedPresets and COL_CHECKED or COL_UNCHECKED
    chkEmbed.HasHover           = 'Yes'
    chkEmbed.plugincomponent    = myHandle
    chkEmbed.clicked            = 'mpbToggleEmbed'

    embedNote                   = sc:Append('UIObject')
    embedNote.Text              = 'When checked, stores with /embed -- source preset values are baked into the output.'
    embedNote.Font              = 'Regular20'
    embedNote.TextalignmentH    = 'Left'
    embedNote.W                 = labelW + inputW + gap
    embedNote.H                 = 28
    embedNote.X                 = padX
    embedNote.Y                 = optY0 + 52 + rowH + 4
    embedNote.BackColor         = COL_HINT

    -- ?? Footer ????????????????????????????????????????????????????????????????
    local createBtn, abortBtn = buildFooter(base, 2, 'Create MAgic Preset')
    createBtn.clicked = 'mpbCreate'
    abortBtn.clicked  = 'mpbClose'

    base:WaitInit()
    -- No FindBestFocus: leave keyboard focus on the command line so console
    -- keys keep working while the dialog is open.

    ---------------------------------------------------------------------------
    -- Callbacks
    ---------------------------------------------------------------------------
    signalTable.mpbClose = function(caller)
        overlay:ClearUIChildren()
        done = true
    end

    signalTable.mpbOnNameChanged = function(caller)
        outputName = caller.content or ""
    end

    signalTable.mpbOnSlotChanged = function(caller)
        outputSlot = caller.content or ""
    end

    signalTable.mpbOnFixChanged = function(caller)
        fixtureExpr = caller.content or fixtureExpr
    end

    signalTable.mpbGrabSelection = function(caller)
        Printf("[MAgicPresetBuilder] Use Selection pressed")
        local expr, info = selectionToFixtureExpr(true)
        if not expr then
            ErrPrintf("[MAgicPresetBuilder] " .. tostring(info))
            return
        end
        fixtureExpr = expr
        edFix.Text  = expr
        Printf("[MAgicPresetBuilder] Using selection: %s (%d fixtures)", expr, info)
    end

    signalTable.mpbCyclePool = function(caller)
        poolIdx = (poolIdx % #POOL_MAP) + 1
        btnPool.Text = currentPoolLabel()
        refreshAllLabels()
    end

    -- 3-way mode toggle -- always triggers a full UI rebuild to swap row widgets
    signalTable.mpbToggleInputMode = function(caller)
        if inputMode == "slot" then inputMode = "name"
        elseif inputMode == "name" then inputMode = "hardvalue"
        else inputMode = "slot" end
        -- Save full row state before clearing
        local savedRows = {}
        for _, r in ipairs(presetRows) do
            table.insert(savedRows, { slot = r.slot, attr = r.attr, value = r.value })
        end
        result = {
            _rebuild   = true,
            rows       = savedRows,
            _inputMode = inputMode,
            _name      = outputName,
            _slot      = outputSlot,
            _fix       = fixtureExpr,
            _poolIdx   = poolIdx,
            _embed     = embedPresets,
        }
        overlay:ClearUIChildren()
        done = true
    end

    signalTable.mpbOnPresetSlotChanged = function(caller)
        local nm  = caller.Name or ""
        local idx = tonumber(nm:match("_(%d+)$"))
        if not idx or not presetRows[idx] then return end
        if inputMode == "hardvalue" then
            presetRows[idx].attr = caller.content or ""
        else
            presetRows[idx].slot = caller.content or ""
        end
        refreshRowLabel(idx)
    end

    signalTable.mpbOnPresetValueChanged = function(caller)
        local nm  = caller.Name or ""
        local idx = tonumber(nm:match("_(%d+)$"))
        if idx and presetRows[idx] then
            presetRows[idx].value = caller.content or ""
            refreshRowLabel(idx)
        end
    end

    signalTable.mpbOnPickRow = function(caller)
        local nm  = caller.Name or ""
        local idx = tonumber(nm:match("_(%d+)$"))
        if not idx or not presetRows[idx] then return end
        local savedRows = {}
        for _, r in ipairs(presetRows) do
            table.insert(savedRows, { slot = r.slot, attr = r.attr, value = r.value })
        end
        result = {
            _rebuild   = true,
            _pickFor   = idx,
            rows       = savedRows,
            _inputMode = inputMode,
            _name      = outputName,
            _slot      = outputSlot,
            _fix       = fixtureExpr,
            _poolIdx   = poolIdx,
            _embed     = embedPresets,
        }
        overlay:ClearUIChildren()
        done = true
    end

    signalTable.mpbAddRow = function(caller)
        addPresetRow("", "", "")
        repositionFloating()
    end

    signalTable.mpbOnRemoveRow = function(caller)
        local nm  = caller.Name or ""
        local idx = tonumber(nm:match("_(%d+)$"))
        if not idx then return end
        if idx <= 2 then
            ErrPrintf("[MAgicPresetBuilder] The first two preset rows cannot be removed.")
            return
        end
        local savedRows = {}
        for _, r in ipairs(presetRows) do
            table.insert(savedRows, { slot = r.slot, attr = r.attr, value = r.value })
        end
        table.remove(savedRows, idx)
        result = {
            _rebuild   = true,
            rows       = savedRows,
            _inputMode = inputMode,
            _name      = outputName,
            _slot      = outputSlot,
            _fix       = fixtureExpr,
            _poolIdx   = poolIdx,
            _embed     = embedPresets,
        }
        overlay:ClearUIChildren()
        done = true
    end

    signalTable.mpbToggleEmbed = function(caller)
        embedPresets        = not embedPresets
        chkEmbed.Text       = embedPresets
            and '[X]  Embed source presets in MAgic preset'
            or  '[  ]  Embed source presets in MAgic preset'
        chkEmbed.BackColor  = embedPresets and COL_CHECKED or COL_UNCHECKED
    end

    signalTable.mpbCreate = function(caller)
        local chosenPool = POOL_MAP[poolIdx]
        local pool       = getPresetPool(chosenPool.index)
        if not pool then
            ErrPrintf("[MAgicPresetBuilder] Could not access pool: " .. chosenPool.name)
            return
        end

        if trim(fixtureExpr) == "" then
            ErrPrintf("[MAgicPresetBuilder] Fixture selection cannot be empty.")
            return
        end

        -- Auto-slot (shared by all modes)
        local resolvedSlot = tonumber(trim(outputSlot))
        if not resolvedSlot or resolvedSlot < 1 then
            resolvedSlot = nextFreePresetSlot(pool)
            Printf("[MAgicPresetBuilder] Auto-slot: %d", resolvedSlot)
        end

        -----------------------------------------------------------------------
        -- Hard Value mode
        -----------------------------------------------------------------------
        if inputMode == "hardvalue" then
            local hardValues = {}
            local hvNames    = {}
            for i, row in ipairs(presetRows) do
                local a = trim(row.attr  or "")
                local v = trim(row.value or "")
                if a == "" then
                    ErrPrintf(string.format(
                        "[MAgicPresetBuilder] Row %d: attribute name cannot be empty.", i))
                    return
                end
                if v == "" then
                    ErrPrintf(string.format(
                        "[MAgicPresetBuilder] Row %d: value cannot be empty.", i))
                    return
                end
                -- Value must be numeric
                if tonumber(v) == nil then
                    ErrPrintf(string.format(
                        "[MAgicPresetBuilder] Row %d: value \"%s\" is not a number.", i, v))
                    return
                end
                table.insert(hardValues, { attr = a, value = v })
                table.insert(hvNames, a .. "=" .. v)
            end

            if #hardValues < 2 then
                ErrPrintf("[MAgicPresetBuilder] At least two steps are required.")
                return
            end

            local resolvedName = trim(outputName)
            if resolvedName == "" then
                resolvedName = table.concat(hvNames, " -> ")
                Printf("[MAgicPresetBuilder] Auto-name: \"%s\"", resolvedName)
            end

            result = {
                outputName   = resolvedName,
                outputSlot   = resolvedSlot,
                fixtureExpr  = trim(fixtureExpr),
                poolName     = chosenPool.name,
                poolIndex    = chosenPool.index,
                hardValues   = hardValues,
                embedPresets = embedPresets,
            }
            overlay:ClearUIChildren()
            done = true
            return
        end

        -----------------------------------------------------------------------
        -- Slot # / Name mode -- resolve source presets
        -----------------------------------------------------------------------
        local validSlots  = {}
        local sourceNames = {}
        for i, row in ipairs(presetRows) do
            local s
            if inputMode == "name" then
                local search = trim(row.slot or "")
                if search == "" then
                    ErrPrintf(string.format(
                        "[MAgicPresetBuilder] Row %d: preset name cannot be empty.", i))
                    return
                end
                s = findPresetByName(pool, search)
                if not s then
                    ErrPrintf(string.format(
                        "[MAgicPresetBuilder] Row %d: no preset named \"%s\" found in %s pool.",
                        i, search, chosenPool.name))
                    return
                end
            else
                s = tonumber(trim(row.slot or ""))
                if not s or s < 1 then
                    ErrPrintf(string.format(
                        "[MAgicPresetBuilder] Row %d: slot must be a positive integer.", i))
                    return
                end
                if not getPresetInPool(pool, s) then
                    ErrPrintf(string.format(
                        "[MAgicPresetBuilder] Row %d: Preset %s[%d] does not exist.",
                        i, chosenPool.name, s))
                    return
                end
            end
            local p = getPresetInPool(pool, s)
            table.insert(validSlots, s)
            local pname = (p and p.name and trim(p.name) ~= "")
                and p.name or (chosenPool.name .. "[" .. s .. "]")
            table.insert(sourceNames, pname)
        end

        if #validSlots < 2 then
            ErrPrintf("[MAgicPresetBuilder] At least two source presets are required.")
            return
        end

        local resolvedName = trim(outputName)
        if resolvedName == "" then
            resolvedName = table.concat(sourceNames, " -> ")
            Printf("[MAgicPresetBuilder] Auto-name: \"%s\"", resolvedName)
        end

        result = {
            outputName   = resolvedName,
            outputSlot   = resolvedSlot,
            fixtureExpr  = trim(fixtureExpr),
            poolName     = chosenPool.name,
            poolIndex    = chosenPool.index,
            presetSlots  = validSlots,
            embedPresets = embedPresets,
        }
        overlay:ClearUIChildren()
        done = true
    end

    repeat coroutine.yield() until done
    return result
end

local function safeProp(h, prop)
    local ok, v = pcall(function() return h[prop] end)
    if ok then return v end
    return nil
end
-------------------------------------------------------------------------------
-- Pure-Lua PNG decoder + downscaler + TGA writer
-- No bitwise operators (runs on Lua 5.1 - 5.4). ASCII only.
-- decodePNG(data, tick) -> w, h, px   (px = flat RGBA byte table, 1-based)
--   tick: optional function called periodically (for coroutine.yield)
-- fitRGBA(w, h, px, maxDim) -> w2, h2, px2   (area-average downscale)
-- encodeTGA(w, h, px) -> string (32-bit BGRA, top-left origin)
-------------------------------------------------------------------------------
local MPBImg = {}

local floor, char, byte, concat = math.floor, string.char, string.byte, table.concat

---------------------------------------------------------------- inflate (RFC1951)
local POW2 = {}
do local v = 1; for i = 0, 31 do POW2[i] = v; v = v * 2 end end

local LEN_BASE  = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
local LEN_EXTRA = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
local DST_BASE  = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
local DST_EXTRA = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
local CL_ORDER  = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}

-- Build a canonical Huffman decode table: map[len][code] = symbol
local function buildHuff(lengths, n)
    local blCount, maxLen = {}, 0
    for i = 0, 15 do blCount[i] = 0 end
    for s = 0, n - 1 do
        local l = lengths[s] or 0
        blCount[l] = blCount[l] + 1
        if l > maxLen then maxLen = l end
    end
    blCount[0] = 0
    local nextCode, code = {}, 0
    for bits = 1, maxLen do
        code = (code + blCount[bits - 1]) * 2
        nextCode[bits] = code
    end
    local map = {}
    for l = 1, maxLen do map[l] = {} end
    for s = 0, n - 1 do
        local l = lengths[s] or 0
        if l > 0 then
            map[l][nextCode[l]] = s
            nextCode[l] = nextCode[l] + 1
        end
    end
    -- fast lookup: every maxLen-bit LSB-first pattern whose low 'l' bits are
    -- the bit-reversed code maps to {symbol, length}
    local flen, fsym = {}, {}
    for l = 1, maxLen do
        for code, s in pairs(map[l]) do
            local rev, c = 0, code
            for _ = 1, l do rev = rev * 2 + c % 2; c = floor(c / 2) end
            local step = POW2[l]
            for k = rev, POW2[maxLen] - 1, step do flen[k] = l; fsym[k] = s end
        end
    end
    if maxLen == 0 then maxLen = 1 end
    return { maxLen = maxLen, flen = flen, fsym = fsym }
end

local function inflate(src, pos, tick)
    local bitBuf, bitCnt = 0, 0
    local srcLen = #src
    local out, outN = {}, 0
    local P2 = POW2

    local function bits(n)
        if n == 0 then return 0 end
        while bitCnt < n do
            if pos > srcLen then error("inflate: unexpected end of data") end
            bitBuf = bitBuf + byte(src, pos) * P2[bitCnt]
            pos = pos + 1
            bitCnt = bitCnt + 8
        end
        local p = P2[n]
        local v = bitBuf % p
        bitBuf = (bitBuf - v) / p
        bitCnt = bitCnt - n
        return v
    end
    local function decodeSym(h)
        local ml = h.maxLen
        while bitCnt < ml do
            bitBuf = bitBuf + (byte(src, pos) or 0) * P2[bitCnt]
            pos = pos + 1
            bitCnt = bitCnt + 8
        end
        local k = bitBuf % P2[ml]
        local l = h.flen[k]
        if not l or l > bitCnt then error("inflate: bad huffman code") end
        local p = P2[l]
        bitBuf = (bitBuf - bitBuf % p) / p
        bitCnt = bitCnt - l
        return h.fsym[k]
    end

    local fixedLit, fixedDst
    local blocks = 0
    repeat
        local final = bits(1)
        local btype = bits(2)
        if btype == 0 then
            -- drop partial byte; return whole unread bytes to the stream
            local drop = bitCnt % 8
            bits(drop)
            pos = pos - bitCnt / 8
            bitBuf, bitCnt = 0, 0
            if pos + 3 > srcLen then error("inflate: truncated stored block") end
            local len = byte(src, pos) + byte(src, pos + 1) * 256
            pos = pos + 4
            for i = 0, len - 1 do out[outN + 1 + i] = byte(src, pos + i) end
            outN = outN + len
            pos = pos + len
        elseif btype == 1 or btype == 2 then
            local lit, dst
            if btype == 1 then
                if not fixedLit then
                    local l = {}
                    for i = 0, 143 do l[i] = 8 end
                    for i = 144, 255 do l[i] = 9 end
                    for i = 256, 279 do l[i] = 7 end
                    for i = 280, 287 do l[i] = 8 end
                    fixedLit = buildHuff(l, 288)
                    local d = {}
                    for i = 0, 29 do d[i] = 5 end
                    fixedDst = buildHuff(d, 30)
                end
                lit, dst = fixedLit, fixedDst
            else
                local hlit  = bits(5) + 257
                local hdist = bits(5) + 1
                local hclen = bits(4) + 4
                local cl = {}
                for i = 0, 18 do cl[i] = 0 end
                for i = 1, hclen do cl[CL_ORDER[i]] = bits(3) end
                local clh = buildHuff(cl, 19)
                local lens, n = {}, 0
                while n < hlit + hdist do
                    local s = decodeSym(clh)
                    if s < 16 then
                        lens[n] = s; n = n + 1
                    elseif s == 16 then
                        if n == 0 then error("inflate: repeat with no previous length") end
                        local prev = lens[n - 1]
                        for _ = 1, 3 + bits(2) do lens[n] = prev; n = n + 1 end
                    elseif s == 17 then
                        for _ = 1, 3 + bits(3) do lens[n] = 0; n = n + 1 end
                    else
                        for _ = 1, 11 + bits(7) do lens[n] = 0; n = n + 1 end
                    end
                end
                local ll, dl = {}, {}
                for i = 0, hlit - 1 do ll[i] = lens[i] end
                for i = 0, hdist - 1 do dl[i] = lens[hlit + i] end
                lit = buildHuff(ll, hlit)
                dst = buildHuff(dl, hdist)
            end

            -- hot loop: literal/length symbols decoded inline
            local lml, lmask = lit.maxLen, P2[lit.maxLen]
            local lflen, lfsym = lit.flen, lit.fsym
            while true do
                while bitCnt < lml do
                    bitBuf = bitBuf + (byte(src, pos) or 0) * P2[bitCnt]
                    pos = pos + 1
                    bitCnt = bitCnt + 8
                end
                local k = bitBuf % lmask
                local l = lflen[k]
                if not l or l > bitCnt then error("inflate: bad huffman code") end
                local p = P2[l]
                bitBuf = (bitBuf - bitBuf % p) / p
                bitCnt = bitCnt - l
                local s = lfsym[k]
                if s < 256 then
                    outN = outN + 1
                    out[outN] = s
                elseif s == 256 then
                    break
                else
                    local li = s - 256
                    local len = LEN_BASE[li] + bits(LEN_EXTRA[li])
                    local di = decodeSym(dst) + 1
                    local dist = DST_BASE[di] + bits(DST_EXTRA[di])
                    local from = outN - dist
                    if from < 0 then error("inflate: distance too far back") end
                    for i = 1, len do out[outN + i] = out[from + i] end
                    outN = outN + len
                end
            end
        else
            error("inflate: invalid block type")
        end
        blocks = blocks + 1
        if tick and blocks % 4 == 0 then tick() end
    until final == 1
    return out, outN
end

MPBImg._inflate = inflate

---------------------------------------------------------------- PNG
local function be32(s, i)
    local a, b, c, d = byte(s, i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
end

local CHANNELS = { [0] = 1, [2] = 3, [3] = 1, [4] = 2, [6] = 4 }

local ADAM7 = {  -- xStart, yStart, xStep, yStep
    {0, 0, 8, 8}, {4, 0, 8, 8}, {0, 4, 4, 8}, {2, 0, 4, 4},
    {0, 2, 2, 4}, {1, 0, 2, 2}, {0, 1, 1, 2},
}

function MPBImg.decodePNG(data, tick)
    if #data < 33 or data:sub(1, 8) ~= "\137PNG\r\n\26\n" then
        error("not a PNG file")
    end
    local pos = 9
    local w, h, depth, ctype, interlace
    local idat, palette, trns = {}, nil, nil
    while pos + 8 <= #data do
        local len  = be32(data, pos)
        local typ  = data:sub(pos + 4, pos + 7)
        local body = pos + 8
        if typ == "IHDR" then
            w, h = be32(data, body), be32(data, body + 4)
            depth, ctype = byte(data, body + 8), byte(data, body + 9)
            interlace = byte(data, body + 12)
        elseif typ == "PLTE" then
            palette = {}
            for i = 0, floor(len / 3) - 1 do
                palette[i] = { byte(data, body + i * 3, body + i * 3 + 2) }
            end
        elseif typ == "tRNS" then
            trns = { byte(data, body, body + len - 1) }
        elseif typ == "IDAT" then
            idat[#idat + 1] = data:sub(body, body + len - 1)
        elseif typ == "IEND" then
            break
        end
        pos = body + len + 4
    end
    if not w or not CHANNELS[ctype] then error("unsupported PNG header") end
    if w * h > 4194304 then error("image too large (" .. w .. "x" .. h .. ")") end

    local z = concat(idat)
    -- zlib header: 2 bytes; skip preset dictionary not supported
    local flg = byte(z, 2)
    if flg % 64 >= 32 then error("zlib preset dictionary not supported") end
    local raw = inflate(z, 3, tick)

    local chans  = CHANNELS[ctype]
    local bitsPP = chans * depth
    local bpp    = math.max(1, floor(bitsPP / 8))  -- filter byte distance
    local px     = {}  -- RGBA output, 1-based
    local maxV   = POW2[depth] - 1

    -- transparent colour key for types 0 / 2
    local keyG, keyR, keyGr, keyB
    if trns and ctype == 0 and #trns >= 2 then keyG = trns[1] * 256 + trns[2] end
    if trns and ctype == 2 and #trns >= 6 then
        keyR, keyGr, keyB = trns[1] * 256 + trns[2], trns[3] * 256 + trns[4], trns[5] * 256 + trns[6]
    end

    local rp = 1  -- read pointer into raw
    local function processPass(pw, ph, x0, y0, dx, dy)
        if pw == 0 or ph == 0 then return end
        local rowBytes = floor((pw * bitsPP + 7) / 8)
        local prev = {}
        for i = 1, rowBytes do prev[i] = 0 end
        for py = 0, ph - 1 do
            local ft = raw[rp]; rp = rp + 1
            if ft == nil then error("PNG data truncated") end
            local cur = {}
            for i = 1, rowBytes do
                local x = raw[rp + i - 1] or 0
                local a = (i > bpp) and cur[i - bpp] or 0
                local b = prev[i]
                local v
                if ft == 0 then v = x
                elseif ft == 1 then v = x + a
                elseif ft == 2 then v = x + b
                elseif ft == 3 then v = x + floor((a + b) / 2)
                elseif ft == 4 then
                    local c = (i > bpp) and prev[i - bpp] or 0
                    local p = a + b - c
                    local pa, pb, pc = p - a, p - b, p - c
                    if pa < 0 then pa = -pa end
                    if pb < 0 then pb = -pb end
                    if pc < 0 then pc = -pc end
                    if pa <= pb and pa <= pc then v = x + a
                    elseif pb <= pc then v = x + b
                    else v = x + c end
                else
                    error("bad PNG filter type " .. tostring(ft))
                end
                cur[i] = v % 256
            end
            rp = rp + rowBytes

            -- unpack samples
            local y = y0 + py * dy
            if depth == 8 and interlace ~= 1 and (ctype == 6 or (ctype == 2 and not keyR)) then
                -- fast path: 8-bit RGBA / RGB, non-interlaced
                local o = y * w * 4
                if ctype == 6 then
                    for i = 1, pw * 4 do px[o + i] = cur[i] end
                else
                    local ci = 1
                    for pxI = 0, pw - 1 do
                        local q = o + pxI * 4
                        px[q + 1], px[q + 2], px[q + 3], px[q + 4] = cur[ci], cur[ci + 1], cur[ci + 2], 255
                        ci = ci + 3
                    end
                end
            else
            for pxI = 0, pw - 1 do
                local x = x0 + pxI * dx
                local s = {}
                if depth == 8 then
                    local o = pxI * chans
                    for c = 1, chans do s[c] = cur[o + c] end
                elseif depth == 16 then
                    local o = pxI * chans * 2
                    for c = 1, chans do s[c] = cur[o + c * 2 - 1] * 256 + cur[o + c * 2] end
                else  -- 1, 2, 4 bit (single channel)
                    local bitPos = pxI * depth
                    local bi = floor(bitPos / 8) + 1
                    local shift = 8 - depth - (bitPos % 8)
                    s[1] = floor(cur[bi] / POW2[shift]) % POW2[depth]
                end

                local r, g, b, al
                if ctype == 3 then
                    local e = palette and palette[s[1]] or { 0, 0, 0 }
                    r, g, b = e[1], e[2], e[3]
                    al = (trns and trns[s[1] + 1]) or 255
                else
                    local function to8(v) return floor(v * 255 / maxV + 0.5) end
                    if ctype == 0 then
                        r = to8(s[1]); g, b, al = r, r, 255
                        if keyG and s[1] == keyG then al = 0 end
                    elseif ctype == 4 then
                        r = to8(s[1]); g, b = r, r; al = to8(s[2])
                    elseif ctype == 2 then
                        r, g, b, al = to8(s[1]), to8(s[2]), to8(s[3]), 255
                        if keyR and s[1] == keyR and s[2] == keyGr and s[3] == keyB then al = 0 end
                    else
                        r, g, b, al = to8(s[1]), to8(s[2]), to8(s[3]), to8(s[4])
                    end
                end
                local o = (y * w + x) * 4
                px[o + 1], px[o + 2], px[o + 3], px[o + 4] = r, g, b, al
            end
            end
            prev = cur
            if tick and py % 32 == 31 then tick() end
        end
    end

    if interlace == 1 then
        for _, a in ipairs(ADAM7) do
            local pw = floor((w - a[1] + a[3] - 1) / a[3])
            local ph = floor((h - a[2] + a[4] - 1) / a[4])
            if w <= a[1] then pw = 0 end
            if h <= a[2] then ph = 0 end
            processPass(pw, ph, a[1], a[2], a[3], a[4])
        end
    else
        processPass(w, h, 0, 0, 1, 1)
    end
    return w, h, px
end

---------------------------------------------------------------- resize
-- Area-average downscale so the larger side = maxDim (never upscales).
-- Colour is alpha-weighted so transparent edges don't go dark.
function MPBImg.fitRGBA(w, h, px, maxDim, tick)
    local scale = math.max(w, h) / maxDim
    if scale <= 1 then return w, h, px end
    local w2 = math.max(1, floor(w / scale + 0.5))
    local h2 = math.max(1, floor(h / scale + 0.5))
    local out = {}
    local sx, sy = w / w2, h / h2
    for y2 = 0, h2 - 1 do
        local yA, yB = y2 * sy, (y2 + 1) * sy
        for x2 = 0, w2 - 1 do
            local xA, xB = x2 * sx, (x2 + 1) * sx
            local r, g, b, a, wt = 0, 0, 0, 0, 0
            for y = floor(yA), math.min(h - 1, math.ceil(yB) - 1) do
                local wy = math.min(yB, y + 1) - math.max(yA, y)
                if wy > 0 then
                    for x = floor(xA), math.min(w - 1, math.ceil(xB) - 1) do
                        local wx = math.min(xB, x + 1) - math.max(xA, x)
                        if wx > 0 then
                            local k = wx * wy
                            local o = (y * w + x) * 4
                            local al = px[o + 4] * k
                            r = r + px[o + 1] * al
                            g = g + px[o + 2] * al
                            b = b + px[o + 3] * al
                            a = a + al
                            wt = wt + k
                        end
                    end
                end
            end
            local o = (y2 * w2 + x2) * 4
            if a > 0 then
                out[o + 1] = floor(r / a + 0.5)
                out[o + 2] = floor(g / a + 0.5)
                out[o + 3] = floor(b / a + 0.5)
            else
                out[o + 1], out[o + 2], out[o + 3] = 0, 0, 0
            end
            out[o + 4] = floor(a / wt + 0.5)
        end
        if tick and y2 % 16 == 15 then tick() end
    end
    return w2, h2, out
end

---------------------------------------------------------------- TGA
function MPBImg.encodeTGA(w, h, px)
    local header = char(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        w % 256, floor(w / 256), h % 256, floor(h / 256), 32, 40)
    local rows = {}
    for y = 0, h - 1 do
        local row = {}
        for x = 0, w - 1 do
            local o = (y * w + x) * 4
            row[x + 1] = char(px[o + 3], px[o + 2], px[o + 1], px[o + 4])
        end
        rows[y + 1] = concat(row)
    end
    return header .. concat(rows)
end

---------------------------------------------------------------- fast path
-- pngToTGA(data, maxDim) -> tgaString, w2, h2
-- 8-bit RGBA / RGB non-interlaced PNGs (the common case) are unfiltered in
-- place inside the inflate buffer and downscaled by supersampling straight
-- from it -- no full-size pixel table is built. Anything else goes through
-- decodePNG + fitRGBA (slower, but handles every PNG type).
local function readHeader(data)
    if #data < 33 or data:sub(1, 8) ~= "\137PNG\r\n\26\n" then
        error("not a PNG file")
    end
    local pos, info, idat = 9, {}, {}
    while pos + 8 <= #data do
        local len  = be32(data, pos)
        local typ  = data:sub(pos + 4, pos + 7)
        local body = pos + 8
        if typ == "IHDR" then
            info.w, info.h = be32(data, body), be32(data, body + 4)
            info.depth, info.ctype = byte(data, body + 8), byte(data, body + 9)
            info.interlace = byte(data, body + 12)
        elseif typ == "tRNS" then
            info.trns = true
        elseif typ == "IDAT" then
            idat[#idat + 1] = data:sub(body, body + len - 1)
        elseif typ == "IEND" then
            break
        end
        pos = body + len + 4
    end
    return info, idat
end

function MPBImg.pngToTGA(data, maxDim)
    local info, idat = readHeader(data)
    local w, h, ctype = info.w, info.h, info.ctype
    local fast = w and info.depth == 8 and info.interlace == 0
        and (ctype == 6 or (ctype == 2 and not info.trns))
    if not fast then
        local dw, dh, px = MPBImg.decodePNG(data)
        local w2, h2, px2 = MPBImg.fitRGBA(dw, dh, px, maxDim)
        return MPBImg.encodeTGA(w2, h2, px2), w2, h2
    end
    if w * h > 4194304 then error("image too large (" .. w .. "x" .. h .. ")") end

    local z = concat(idat)
    if byte(z, 2) % 64 >= 32 then error("zlib preset dictionary not supported") end
    local raw = inflate(z, 3)

    local bpp      = (ctype == 6) and 4 or 3
    local rowBytes = w * bpp
    local stride   = rowBytes + 1
    if #raw < stride * h then error("PNG data truncated") end

    -- in-place unfilter; row y data occupies raw[d+1 .. d+rowBytes], d = y*stride+1
    for y = 0, h - 1 do
        local d  = y * stride + 1
        local ft = raw[d]
        local pd = d - stride            -- previous row (y > 0)
        if ft == 1 then
            for i = d + bpp + 1, d + rowBytes do
                local v = raw[i] + raw[i - bpp]
                if v > 255 then v = v - 256 end
                raw[i] = v
            end
        elseif ft == 2 then
            if y > 0 then
                for i = d + 1, d + rowBytes do
                    local v = raw[i] + raw[i - stride]
                    if v > 255 then v = v - 256 end
                    raw[i] = v
                end
            end
        elseif ft == 3 then
            if y > 0 then
                for i = d + 1, d + bpp do
                    local b = raw[i - stride]
                    local v = raw[i] + (b - b % 2) / 2
                    if v > 255 then v = v - 256 end
                    raw[i] = v
                end
                for i = d + bpp + 1, d + rowBytes do
                    local s = raw[i - bpp] + raw[i - stride]
                    local v = raw[i] + (s - s % 2) / 2
                    if v > 255 then v = v - 256 end
                    raw[i] = v
                end
            else
                for i = d + bpp + 1, d + rowBytes do
                    local a = raw[i - bpp]
                    local v = raw[i] + (a - a % 2) / 2
                    if v > 255 then v = v - 256 end
                    raw[i] = v
                end
            end
        elseif ft == 4 and y == 0 then
            -- Paeth on the first row == Sub
            for i = d + bpp + 1, d + rowBytes do
                local v = raw[i] + raw[i - bpp]
                if v > 255 then v = v - 256 end
                raw[i] = v
            end
        elseif ft == 4 then
            for i = d + 1, d + bpp do          -- a = c = 0 -> predictor = b
                local v = raw[i] + raw[i - stride]
                if v > 255 then v = v - 256 end
                raw[i] = v
            end
            for i = d + bpp + 1, d + rowBytes do
                local a = raw[i - bpp]
                local b = raw[i - stride]
                local c = raw[i - stride - bpp]
                local pa, pb = b - c, a - c
                local pc = pa + pb
                if pa < 0 then pa = -pa end
                if pb < 0 then pb = -pb end
                if pc < 0 then pc = -pc end
                local pr
                if pa <= pb and pa <= pc then pr = a
                elseif pb <= pc then pr = b
                else pr = c end
                local v = raw[i] + pr
                if v > 255 then v = v - 256 end
                raw[i] = v
            end
        elseif ft ~= 0 then
            error("bad PNG filter type " .. tostring(ft))
        end
    end

    -- output size (never upscale)
    local scale = math.max(w, h) / maxDim
    if scale < 1 then scale = 1 end
    local w2 = math.max(1, floor(w / scale + 0.5))
    local h2 = math.max(1, floor(h / scale + 0.5))
    local sx, sy = w / w2, h / h2
    local nx, ny = floor(sx + 0.5), floor(sy + 0.5)
    if nx < 1 then nx = 1 end
    if ny < 1 then ny = 1 end

    -- precomputed sample offsets: columns -> byte offset in a row, rows -> row start
    local colOff = {}
    for x2 = 0, w2 - 1 do
        local list = {}
        for k = 0, nx - 1 do
            local x = floor((x2 + (k + 0.5) / nx) * sx)
            if x > w - 1 then x = w - 1 end
            list[k + 1] = x * bpp
        end
        colOff[x2] = list
    end
    local rowOff = {}
    for y2 = 0, h2 - 1 do
        local list = {}
        for k = 0, ny - 1 do
            local y = floor((y2 + (k + 0.5) / ny) * sy)
            if y > h - 1 then y = h - 1 end
            list[k + 1] = y * stride + 1
        end
        rowOff[y2] = list
    end

    local n = nx * ny
    local rows = {}
    for y2 = 0, h2 - 1 do
        local ro = rowOff[y2]
        local line = {}
        for x2 = 0, w2 - 1 do
            local co = colOff[x2]
            local r, g, b, a = 0, 0, 0, 0
            if bpp == 4 then
                for j = 1, ny do
                    local base = ro[j]
                    for i = 1, nx do
                        local o = base + co[i]
                        local al = raw[o + 4]
                        if al > 0 then
                            r = r + raw[o + 1] * al
                            g = g + raw[o + 2] * al
                            b = b + raw[o + 3] * al
                            a = a + al
                        end
                    end
                end
            else
                for j = 1, ny do
                    local base = ro[j]
                    for i = 1, nx do
                        local o = base + co[i]
                        r = r + raw[o + 1] * 255
                        g = g + raw[o + 2] * 255
                        b = b + raw[o + 3] * 255
                        a = a + 255
                    end
                end
            end
            if a > 0 then
                line[x2 + 1] = char(floor(b / a + 0.5), floor(g / a + 0.5), floor(r / a + 0.5),
                                    floor(a / n + 0.5))
            else
                line[x2 + 1] = "\0\0\0\0"
            end
        end
        rows[y2 + 1] = concat(line)
    end
    local header = char(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        w2 % 256, floor(w2 / 256), h2 % 256, floor(h2 / 256), 32, 40)
    return header .. concat(rows), w2, h2
end

-------------------------------------------------------------------------------
-- Appearance images in the picker
--   MA3 UI textures only load TGA, from <install>/shared/resource/textures/.
--   Each appearance image png is converted ONCE (pure Lua) to a 96 px TGA
--   cache file in that folder, then loaded as a runtime Texture and shown
--   with Button.Icon. Cache name includes the png size, so a changed png
--   converts again. Unsupported images fall back to the colour strip.
-------------------------------------------------------------------------------
local IMG_SIZE    = 96
local _texRoot    = false   -- false = not searched yet, nil = not found
local _libPath    = nil

local function fileExists(path)
    local okF, r = pcall(FileExists, path)
    if okF and r ~= nil then return r and true or false end
    local okO, f = pcall(io.open, path, "rb")
    if okO and f then f:close(); return true end
    return false
end

local function readFile(path)
    local okO, f = pcall(io.open, path, "rb")
    if not okO or not f then return nil end
    local d = f:read("*a"); f:close(); return d
end

local function writeFile(path, data)
    local okO, f = pcall(io.open, path, "wb")
    if not okO or not f then return false end
    local okW = pcall(function() f:write(data) end)
    f:close()
    return okW
end

-- Locate the built-in textures folder (holds graphics.textures.xml).
local function findTexRoot()
    if _texRoot ~= false then return _texRoot end
    _texRoot = nil
    local suffixes = { "", "/textures", "/resource/textures", "/shared/resource/textures" }
    local okE, types = pcall(function() return Enums.PathType end)
    if okE and type(types) == "table" then
        for _, v in pairs(types) do
            local okP, p = pcall(GetPath, v)
            if okP and type(p) == "string" and p ~= "" then
                p = p:gsub("\\", "/"):gsub("/$", "")
                for _, s in ipairs(suffixes) do
                    if fileExists(p .. s .. "/graphics.textures.xml") then
                        _texRoot = p .. s
                        Printf("[MAgicPresetBuilder] Texture folder: %s", _texRoot)
                        return _texRoot
                    end
                end
            end
        end
    end
    ErrPrintf("[MAgicPresetBuilder] Texture folder not found -- picker images disabled.")
    return nil
end

local function libPath()
    if not _libPath then
        local okP, p = pcall(GetPath, Enums.PathType.Library)
        _libPath = (okP and p) and tostring(p):gsub("\\", "/") or ""
    end
    return _libPath
end

local function sanitize(s)
    s = s:gsub("[^%w]", "_"):gsub("_+", "_")
    if #s > 80 then s = s:sub(-80) end
    return s
end

-- Where the png lives on disk for an appearance (nil if unknown).
local function appearancePngPath(app)
    local media = tostring(safeProp(app, "mediafilename") or "")
    if media == "" then return nil, nil end
    media = media:gsub("\\", "/")
    local sub = media:gsub("^CUSTOM/", "")
    return libPath() .. "/media/images/" .. sub, media
end

-- Find an existing runtime texture by name, or create one for a cache file.
local function getTexture(texName, fileName)
    local okF, t = pcall(FindTexture, texName)
    if okF and t then return t end
    local tex = Root().GraphicsRoot.TextureCollect.Textures
    local okA, nt = pcall(function() return tex:Append('Texture') end)
    if not okA or not nt then return nil end
    pcall(function() nt.name = texName end)
    pcall(function() nt.filename = fileName end)
    return nt
end

-- Returns texture handle for the preset's appearance image, or nil.
-- 'stats' collects counts; conversion errors are logged once per image.
local function appearanceTexture(p, stats)
    local app = safeProp(p, "appearance")
    if not app then return nil end
    local img = safeProp(app, "image")
    if not img then return nil end
    local root = findTexRoot()
    if not root then return nil end

    local pngPath, media = appearancePngPath(app)
    local data, key
    if pngPath and fileExists(pngPath) then
        data = nil  -- read lazily only if conversion is needed
        local okS, f = pcall(io.open, pngPath, "rb")
        local size = 0
        if okS and f then size = f:seek("end") or 0; f:close() end
        key = sanitize(media) .. "_" .. tostring(size)
    else
        -- image not on disk: try the copy stored in the show file
        local fc = safeProp(img, "filecontent")
        if type(fc) == "string" and #fc > 33 and fc:sub(2, 4) == "PNG" then
            data = fc
            key = "show_" .. sanitize(tostring(safeProp(img, "name") or "img")) .. "_" .. #fc
        else
            stats.missing = stats.missing + 1
            return nil
        end
    end

    local cacheFile = "mpbcache_" .. key .. "_" .. IMG_SIZE .. ".tga"
    local cachePath = root .. "/" .. cacheFile
    if not fileExists(cachePath) then
        data = data or readFile(pngPath)
        if not data then stats.failed = stats.failed + 1; return nil end
        local okD, tga = pcall(MPBImg.pngToTGA, data, IMG_SIZE)
        if not okD then
            stats.failed = stats.failed + 1
            ErrPrintf("[MAgicPresetBuilder] Image skipped (%s): %s", tostring(media or key), tostring(tga))
            return nil
        end
        if not writeFile(cachePath, tga) then
            stats.failed = stats.failed + 1
            ErrPrintf("[MAgicPresetBuilder] Could not write image cache: %s", cachePath)
            return nil
        end
        stats.converted = stats.converted + 1
    end
    stats.images = stats.images + 1
    return getTexture("MPBC_" .. key, cacheFile)
end

-------------------------------------------------------------------------------
-- Appearance colour helpers (Appearance BackR/BackG/BackB are 0-255)
-------------------------------------------------------------------------------
local function presetAppearanceRGB(p)
    local ok, app = pcall(function() return p.appearance end)
    if not ok or not app then return nil end
    local okR, r = pcall(function() return tonumber(app.backr) end)
    local okG, g = pcall(function() return tonumber(app.backg) end)
    local okB, b = pcall(function() return tonumber(app.backb) end)
    if not (okR and okG and okB and r and g and b) then return nil end
    local function clamp(v) v = math.floor(v + 0.5); return v < 0 and 0 or (v > 255 and 255 or v) end
    return clamp(r), clamp(g), clamp(b)
end

-- One CFG colour definition per unique colour; reused on later runs.
local function appearanceColorDef(r, g, b)
    local hex  = string.format("%02X%02X%02X", r, g, b)
    local name = "MPB_A_" .. hex
    local cfg  = Root().ColorTheme.ColorGroups["CFG"]
    if cfg and cfg[name] then return "CFG." .. name end
    return getOrCreateColorDef(name, hex .. "FF")
end

-------------------------------------------------------------------------------
-- Preset picker (built-in): grid of every preset in the chosen pool.
-- Returns { no = <slot>, name = <name> } or nil on cancel.
-------------------------------------------------------------------------------
local function showPicker(overlay, poolEntry, stepIdx)
    local picked, done = nil, false
    local pool = getPresetPool(poolEntry.index)

    -- Collect presets (Children() is 1-based; skips gaps in the pool)
    local items = {}
    if pool then
        for _, p in ipairs(pool:Children()) do
            local no = p.no or p.index
            if no then
                local nm = (p.name and trim(p.name) ~= "") and p.name or ""
                local r, g, b = presetAppearanceRGB(p)
                table.insert(items, { no = tonumber(no), name = nm, r = r, g = g, b = b, p = p })
            end
        end
    end

    -- Appearance images (converted once, then cached)
    local stats = { images = 0, converted = 0, failed = 0, missing = 0 }
    local t0 = os.clock()
    local prog = nil
    local okSP, ph = pcall(StartProgress, "MAgic Preset Builder: loading preset images")
    if okSP then prog = ph; pcall(SetProgressRange, prog, 0, #items) end
    for i, it in ipairs(items) do
        local before = stats.converted
        local okT, tex = pcall(appearanceTexture, it.p, stats)
        if okT then it.tex = tex
        else ErrPrintf("[MAgicPresetBuilder] Image error on preset %s: %s", tostring(it.no), tostring(tex)) end
        if prog then pcall(SetProgress, prog, i) end
        if stats.converted > before then coroutine.yield() end   -- keep the console responsive
    end
    if prog then pcall(StopProgress, prog) end
    if stats.converted > 0 then
        Printf("[MAgicPresetBuilder] Converted %d images in %.1f s (CPU)", stats.converted, os.clock() - t0)
    end

    local base                  = overlay:Append('BaseInput')
    base.H                      = DIALOG_H
    base.W                      = DIALOG_W
    base.Columns                = 1
    base.Rows                   = 3
    base[1][1].SizePolicy       = 'Fixed'
    base[1][1].Size             = 55
    base[1][2].SizePolicy       = 'Stretch'
    base[1][3].SizePolicy       = 'Fixed'
    base[1][3].Size             = 70
    base.AutoClose              = 'No'
    base.CloseOnEscape          = 'Yes'
    base.BackColor              = COL_BG

    local closeBtn = buildTitleBar(base, string.format(
        'Pick %s preset for step %d', poolEntry.name, stepIdx))
    closeBtn.clicked = 'mpbPickCancel'

    local sc                    = base:Append('ScrollBox')
    sc.Name                     = 'mpbPickScroll'
    sc.Anchors                  = '0,1'
    local sbv                   = base:Append('ScrollBarV')
    sbv.ScrollTarget            = sc
    sbv.Anchors                 = '0,1'

    -- Tile: [colour strip 10] [image button 102] [label button 44]
    local COLS, BW, GAP, PADX = 5, 196, 10, 30
    local STRIP_H, IMG_H, LBL_H = 10, IMG_SIZE + 6, 44
    local PITCH = STRIP_H + IMG_H + LBL_H + GAP
    local withCol = 0
    for _, it in ipairs(items) do if it.r and not it.tex then withCol = withCol + 1 end end
    Printf("[MAgicPresetBuilder] Picker: %d presets, %d images (%d newly converted, %d failed, %d not found), %d colour",
        #items, stats.images, stats.converted, stats.failed, stats.missing, withCol)
    if #items == 0 then
        local lbl               = sc:Append('UIObject')
        lbl.Text                = 'No presets in the ' .. poolEntry.name .. ' pool.'
        lbl.Font                = 'Regular28'
        lbl.TextalignmentH      = 'Centre'
        lbl.W                   = DIALOG_W - 80
        lbl.H                   = 80
        lbl.X                   = PADX
        lbl.Y                   = 20
    end
    for i, it in ipairs(items) do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)
        local tx = PADX + col * (BW + GAP)
        local ty = 20 + row * PITCH
        local appCol = (it.r and not it.tex) and appearanceColorDef(it.r, it.g, it.b) or nil

        -- Colour strip (UIObject holds its resting colour reliably)
        local sw                = sc:Append('UIObject')
        sw.W                    = BW
        sw.H                    = STRIP_H
        sw.X                    = tx
        sw.Y                    = ty
        sw.BackColor            = appCol or COL_UNCHECKED

        -- Image area: appearance image via Icon, else the slot number
        local bi                = sc:Append('Button')
        bi.W                    = BW
        bi.H                    = IMG_H
        bi.X                    = tx
        bi.Y                    = ty + STRIP_H
        bi.TextalignmentH       = 'Centre'
        if it.tex then
            local okI = pcall(function() bi.Icon = it.tex end)
            if not okI then bi.Text = tostring(it.no) end
        else
            bi.Text             = tostring(it.no)
        end
        if appCol then bi.BackColor = appCol end
        bi.HasHover             = 'Yes'
        bi.plugincomponent      = myHandle
        bi.Name                 = 'mpbPick_' .. tostring(i)
        bi.clicked              = 'mpbPickPreset'

        -- Label: number + name (also tappable)
        local b                 = sc:Append('Button')
        b.Text                  = tostring(it.no) .. '  ' .. (it.name ~= "" and it.name or '(no name)')
        b.TextalignmentH        = 'Centre'
        b.W                     = BW
        b.H                     = LBL_H
        b.X                     = tx
        b.Y                     = ty + STRIP_H + IMG_H
        b.HasHover              = 'Yes'
        b.plugincomponent       = myHandle
        b.Name                  = 'mpbPickL_' .. tostring(i)
        b.clicked               = 'mpbPickPreset'
    end

    local grid                  = base:Append('UILayoutGrid')
    grid.Columns                = 1
    grid.Rows                   = 1
    grid.H                      = 70
    grid.Anchors                = '0,2'
    local cancel                = grid:Append('Button')
    cancel.Anchors              = '0,0'
    cancel.Text                 = 'Cancel'
    cancel.TextalignmentH       = 'Centre'
    cancel.HasHover             = 'Yes'
    cancel.plugincomponent      = myHandle
    cancel.BackColor            = COL_ABORT
    cancel.clicked              = 'mpbPickCancel'

    base:WaitInit()

    signalTable.mpbPickPreset = function(caller)
        local i = tonumber((caller.Name or ""):match("_(%d+)$"))
        if i and items[i] then picked = { no = items[i].no, name = items[i].name } end
        overlay:ClearUIChildren()
        done = true
    end
    signalTable.mpbPickCancel = function(caller)
        overlay:ClearUIChildren()
        done = true
    end

    repeat coroutine.yield() until done
    return picked
end

-------------------------------------------------------------------------------
-- Execution
-------------------------------------------------------------------------------
local function buildMAgicPreset(params)
    local poolName    = params.poolName
    local poolIndex   = params.poolIndex
    local outputSlot  = params.outputSlot
    local outputName  = params.outputName
    local fixtureExpr = params.fixtureExpr
    local embed       = params.embedPresets
    local slots       = params.presetSlots    -- nil in hard value mode
    local hardValues  = params.hardValues     -- nil in preset mode
    local numSteps    = slots and #slots or #hardValues

    Printf("=== MAgicPresetBuilder v" .. PLUGIN_VERSION .. " ===")
    Printf("Pool: %s  |  Slot: %d  |  Name: \"%s\"", poolName, outputSlot, outputName)
    local modeStr = hardValues and "Hard Value" or "Preset"
    Printf("Mode: %s  |  Fixtures: %s  |  Steps: %d  |  Embed: %s",
        modeStr, fixtureExpr, numSteps, tostring(embed))

    -- ObjectList requires the 'Fixture' keyword -- a bare number range won't resolve.
    -- If the user already typed "Fixture ..." we don't double-prefix it.
    local resolvedExpr = fixtureExpr
    if not resolvedExpr:match("^%s*[Ff]ixture%s") and
       not resolvedExpr:match("^%s*[Gg]roup%s") then
        resolvedExpr = "Fixture " .. resolvedExpr
    end

    local fids = {}
    local plusList = resolvedExpr:match("^%s*[Ff]ixture%s+([%d%s%+]+)$")
    if plusList and plusList:find("+", 1, true) then
        -- "Fixture 101+102+103": keep the listed order, no ObjectList
        for id in plusList:gmatch("%d+") do table.insert(fids, tonumber(id)) end
    else
        local fixtureList = ObjectList(resolvedExpr)
        if not fixtureList then
            ErrPrintf("[MAgicPresetBuilder] ObjectList nil for: " .. resolvedExpr)
            return false
        end
        for _, fix in ipairs(fixtureList) do
            table.insert(fids, fix.fid or fix.index)
        end
    end

    if #fids == 0 then
        ErrPrintf("[MAgicPresetBuilder] No fixtures found for: " .. resolvedExpr)
        return false
    end

    if #fids < numSteps then
        ErrPrintf(string.format(
            "[MAgicPresetBuilder] Need %d fixtures for %d steps, only %d found.",
            numSteps, numSteps, #fids))
        return false
    end

    Cmd("ClearAll /nu")
    coroutine.yield()

    ---------------------------------------------------------------------------
    -- MAgic programmer workflow (confirmed from MA3 manual):
    --   1. Select all N source fixtures as a block
    --   2. Next  ?  applies to fixture 1 only
    --   3. At Preset pool.slot1  ?  values land on fixture 1 in programmer
    --   4. Next  ?  steps to fixture 2
    --   5. At Preset pool.slot2  ?  values land on fixture 2 in programmer
    --   ... repeat for all steps ...
    --   6. Set  ?  re-selects all N fixtures (needed before Store)
    --   7. Store /Selective
    ---------------------------------------------------------------------------

    -- Step 1: select all N fixtures as the navigation block
    local allFidsStr = {}
    for i = 1, numSteps do
        table.insert(allFidsStr, tostring(fids[i]))
    end
    local selectAll = "Fixture " .. table.concat(allFidsStr, "+")
    Printf("Selecting block: %s", selectAll)
    Cmd(selectAll)
    coroutine.yield()

    -- Steps 2-N: Next then apply values/preset for each step
    for stepIdx = 1, numSteps do
        Cmd("Next")
        coroutine.yield()

        local applyCmd
        if hardValues then
            -- Hard Value mode: Attribute "X" At Y
            local hv = hardValues[stepIdx]
            applyCmd = string.format('Attribute "%s" At %s', hv.attr, hv.value)
        else
            -- Preset mode: At Preset pool.slot
            applyCmd = string.format("At Preset %d.%d", poolIndex, slots[stepIdx])
        end

        Printf("Step %d/%d -- Next -> %s", stepIdx, numSteps, applyCmd)

        if not Cmd(applyCmd) then
            ErrPrintf(string.format(
                "[MAgicPresetBuilder] Apply failed at step %d: %s", stepIdx, applyCmd))
            Cmd("ClearAll /nu")
            return false
        end
        coroutine.yield()
    end

    -- Step 6: Set re-selects all fixtures in the block before storing
    Printf("Set (re-select all %d fixtures)", numSteps)
    Cmd("Set")
    coroutine.yield()

    -- Step 7: Store
    local storeCmd = embed
        and string.format('Store Preset %d.%d "%s" /Embed /Selective', poolIndex, outputSlot, outputName)
        or  string.format('Store Preset %d.%d "%s" /Selective',        poolIndex, outputSlot, outputName)
    Printf("%s", storeCmd)
    if not Cmd(storeCmd) then
        ErrPrintf("[MAgicPresetBuilder] Store failed.")
        Cmd("ClearAll /nu"); return false
    end
    coroutine.yield()

    -- Set MAgic On (case-sensitive 'Yes')
    local magicCmd = string.format(
        "Set Preset %d.%d Property 'MAgic' 'Yes'", poolIndex, outputSlot)
    Printf("%s", magicCmd)
    if not Cmd(magicCmd) then
        ErrPrintf("[MAgicPresetBuilder] MAgic property failed -- verify manually.")
    end
    coroutine.yield()

    -- Convert to Universal (MAgic must be set first)
    local univCmd = string.format(
        'Set Preset %d.%d Property "PresetMode" "Universal"', poolIndex, outputSlot)
    Printf("%s", univCmd)
    if not Cmd(univCmd) then
        ErrPrintf("[MAgicPresetBuilder] Universal mode failed -- verify manually.")
    end
    coroutine.yield()

    Cmd("ClearAll /nu")
    coroutine.yield()

    Printf("=== DONE: %s[%d] \"%s\" (Universal MAgic, %d steps) ===",
        poolName, outputSlot, outputName, numSteps)
    return true
end

-------------------------------------------------------------------------------
-- Entry point
-------------------------------------------------------------------------------
local function main()
    initColors()

    local display = GetFocusDisplay()
    if not display then
        ErrPrintf("[MAgicPresetBuilder] No display found.")
        return
    end
    local overlay = display.ScreenOverlay
    if not overlay then
        ErrPrintf("[MAgicPresetBuilder] No ScreenOverlay on display.")
        return
    end

    local seeds = nil   -- carries state across UI rebuilds

    while true do
        local result = showMainUI(overlay, seeds)
        seeds = nil     -- consumed; reset for next iteration

        if result == nil then
            Printf("[MAgicPresetBuilder] Cancelled.")
            return
        end
        if result._rebuild then
            -- Carry the full state back into the next showMainUI call
            seeds = result
            if result._pickFor then
                local stepIdx = result._pickFor
                local choice  = showPicker(overlay, POOL_MAP[result._poolIdx], stepIdx)
                if choice and seeds.rows[stepIdx] then
                    if result._inputMode == "name" and choice.name ~= "" then
                        seeds.rows[stepIdx].slot = choice.name
                    else
                        seeds.rows[stepIdx].slot = tostring(choice.no)
                    end
                    Printf("[MAgicPresetBuilder] Step %d -> %s %d \"%s\"",
                        stepIdx, POOL_MAP[result._poolIdx].name, choice.no, choice.name)
                end
                seeds._pickFor = nil
            else
                Printf("[MAgicPresetBuilder] Rebuilding UI...")
            end
        else
            local ok = buildMAgicPreset(result)
            if ok then
                Printf("[MAgicPresetBuilder] Preset created successfully.")
            else
                ErrPrintf("[MAgicPresetBuilder] Creation failed -- see errors above.")
            end
            return
        end
    end
end

return main
