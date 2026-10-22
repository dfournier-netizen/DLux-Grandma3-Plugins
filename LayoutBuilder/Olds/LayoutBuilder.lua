--[[
    LayoutBuilder.lua  v1.6
    GrandMA3 Plugin -- Version compatible: 2.3.2+

    CHANGES v1.6:
        - Grid now fills top-down (row 1 on top); MA3 layout posY increases upward
        - Default Action is applied to every element (verified by read-back)
        - Pool lookups use Children() + real object numbers (fast, gap-safe)
        - Existing-layout mode checks the layout exists before building
        - Progress bar during build; console stays responsive
        - UI: ASCII only, empty selection field with hint label below,
          no focus grab (console keys keep working), CloseButton sizing

    FIXES v1.5:
        - Grid origin: screenX/Y now correctly offset element positions
        - Negative values handled via math.floor on integer parse
        - Wildcard: full pool scan using pcall to avoid nil crashes
        - Auto layout slot: advances past occupied slots
        - UI scrolling: proper 2-column base grid, scrollbar in column 1
        - Footer in its own fixed row, no overlap with scroll content
]]

local pluginName    = select(1, ...)
local componentName = select(2, ...)
local signalTable   = select(3, ...)
local myHandle      = select(4, ...)

-------------------------------------------------------------------------------
-- Colors
-------------------------------------------------------------------------------
local PLUGIN_VERSION = "1.6.0"
local UI_BG_IDX   = 30.12
local UI_CORAL    = nil
local UI_CYAN     = nil
local UI_LIME     = nil
local UI_CRIMSON  = nil
local UI_PURPLE   = nil
local UI_GOLD     = nil
local UI_TEAL     = nil
local UI_TITLE    = nil

local function getOrCreateColorDef(name, rgba)
    local cg = Root().ColorTheme.ColorGroups
    if not cg then return nil end
    local grp = cg["LBL"]
    if not grp then
        local gi = 1
        while cg[gi] ~= nil do gi = gi + 1 end
        Cmd("cd root / nu"); Cmd("cd \"ColorTheme\" / nu")
        Cmd("cd \"ColorGroups\" / nu")
        Cmd("store " .. gi .. " /nu")
        Cmd("label " .. gi .. " \"LBL\" /nu")
        Cmd("cd root / nu")
        grp = cg["LBL"]
        if not grp then return nil end
    end
    local e = grp[name]
    local idx
    if e then idx = e.index
    else
        idx = 1
        while grp[idx] ~= nil do idx = idx + 1 end
        Cmd("cd root / nu"); Cmd("cd \"ColorTheme\" / nu")
        Cmd("cd \"ColorGroups\" / nu"); Cmd("cd \"LBL\" / nu")
        Cmd("store " .. idx .. " /nu")
        Cmd("label " .. idx .. " \"" .. name .. "\" /nu")
        Cmd("cd root / nu")
    end
    Cmd("cd root / nu"); Cmd("cd \"ColorTheme\" / nu")
    Cmd("cd \"ColorGroups\" / nu"); Cmd("cd \"LBL\" / nu")
    Cmd(string.format('set %d RGBA="%s" /nu', idx, rgba))
    Cmd("cd root / nu")
    return "LBL." .. name
end

local function initColors()
    UI_CORAL   = getOrCreateColorDef("LB_CO", "FF4444FF")
    UI_CYAN    = getOrCreateColorDef("LB_CY", "00CFFFFF")
    UI_LIME    = getOrCreateColorDef("LB_LM", "00E676FF")
    UI_CRIMSON = getOrCreateColorDef("LB_CR", "B71C1CFF")
    UI_PURPLE  = getOrCreateColorDef("LB_PR", "7C4DFFFF")
    UI_GOLD    = getOrCreateColorDef("LB_GD", "FFD600FF")
    UI_TEAL    = getOrCreateColorDef("LB_TL", "1DE9B6FF")
    UI_TITLE   = getOrCreateColorDef("LB_TB", "FF4444FF")
end

-------------------------------------------------------------------------------
-- UI helpers
-------------------------------------------------------------------------------
local function trim(s) return s and s:match("^%s*(.-)%s*$") or "" end

-- Progress bar (MA3 StartProgress API), pcall-guarded; yields every 10 steps
local _prog, _progN = nil, 0
local function progStart(title, total)
    local ok, h = pcall(StartProgress, title)
    _prog, _progN = ok and h or nil, 0
    if _prog then pcall(SetProgressRange, _prog, 0, total); pcall(SetProgress, _prog, 0) end
end
local function progText(s) if _prog then pcall(SetProgressText, _prog, s) end end
local function progStep()
    _progN = _progN + 1
    if _prog then pcall(SetProgress, _prog, _progN) end
    if _progN % 10 == 0 then coroutine.yield() end
end
local function progStop() if _prog then pcall(StopProgress, _prog) end; _prog = nil end

-- Pool children with their real object numbers, in pool order
local function poolItems(pool)
    local out = {}
    local ok, kids = pcall(function() return pool:Children() end)
    if not ok or not kids then return out end
    for _, obj in ipairs(kids) do
        local no = tonumber(obj.no)
        if no then out[#out + 1] = { no = no, obj = obj } end
    end
    return out
end

local function buildTitleBar(base, txt)
    local tb = base:Append('TitleBar')
    tb.Columns = 2; tb.Rows = 1; tb.Anchors = '0,0'
    local ttl = tb:Append('TitleButton')
    ttl.Text = txt; ttl.Font = 'Regular28'; ttl.Anchors = '0,0'
    local cls = tb:Append('CloseButton')
    cls.Anchors = '1,0'
    cls.plugincomponent = myHandle
    tb.BackColor = UI_TITLE
    return cls
end

local function buildFooter(base, anchorRow, lbl)
    local g = base:Append('UILayoutGrid')
    g.Columns = 2; g.Rows = 1; g.H = 72
    g.Anchors = '0,' .. anchorRow
    local ok = g:Append('Button')
    ok.Anchors = '0,0'; ok.Text = lbl
    ok.TextalignmentH = 'Centre'; ok.HasHover = 'Yes'
    ok.plugincomponent = myHandle; ok.BackColor = UI_LIME
    local cn = g:Append('Button')
    cn.Anchors = '1,0'; cn.Text = 'Cancel'
    cn.TextalignmentH = 'Centre'; cn.HasHover = 'Yes'
    cn.plugincomponent = myHandle; cn.BackColor = UI_CRIMSON
    return ok, cn
end

local function divider(parent, txt, y)
    local d = parent:Append('UIObject')
    d.Text = txt; d.Font = 'Regular24'; d.TextalignmentH = 'Centre'
    d.H = 38; d.Anchors = '0,0,1,0'; d.X = 0; d.Y = y
    return y + 46
end

local function cycleBtn(parent, txt, x, y, w, h, color, ev)
    local b = parent:Append('Button')
    b.Text = txt; b.H = h; b.W = w; b.X = x; b.Y = y
    b.TextalignmentH = 'Centre'; b.HasHover = 'Yes'
    b.plugincomponent = myHandle; b.clicked = ev; b.BackColor = color
    return b
end

local function rowLabel(parent, txt, y, rh, lw, px, gap)
    local l = parent:Append('UIObject')
    l.Text = txt; l.Font = 'Regular24'; l.TextalignmentH = 'Right'
    l.W = lw; l.H = rh; l.X = px; l.Y = y
    return px + lw + gap
end

-- Build a BaseInput with a separate scroll column and scrollbar
-- Returns base, scroll
local function buildBase(overlay, title, W, H, closeCB)
    -- Single column, 3 rows: title (fixed) | scroll (stretch) | footer (fixed)
    local base = overlay:Append('BaseInput')
    base.H = H; base.W = W
    base.Columns = 1; base.Rows = 3
    base[1][1].SizePolicy = 'Fixed';   base[1][1].Size = 55   -- title bar
    base[1][2].SizePolicy = 'Stretch'                          -- scroll area
    base[1][3].SizePolicy = 'Fixed';   base[1][3].Size = 72   -- footer buttons
    base.AutoClose = 'No'; base.CloseOnEscape = 'Yes'
    base.BackColor = UI_BG_IDX

    local cls = buildTitleBar(base, title)
    cls.clicked = closeCB

    local scroll = base:Append('ScrollBox')
    scroll.Name  = 'lbScroll'
    scroll.Anchors = '0,1'

    local sb = base:Append('ScrollBarV')
    sb.ScrollTarget = scroll
    sb.Anchors = '0,1'

    return base, scroll
end

-------------------------------------------------------------------------------
-- Step 1 UI
-------------------------------------------------------------------------------
local function showStep1UI(overlay)
    local result, done = nil, false

    local objTypes   = { "Sequence", "Group", "Macro", "Executor", "Fixture", "SubFixture" }
    local selMethods = { "Index Range", "Tag Name", "Wildcard" }
    local layModes   = { "New Layout", "Existing Layout" }
    local selHints   = {
        ["Index Range"] = "e.g.  5001  or  5001 Thru 5100",
        ["Tag Name"]    = "e.g.  Col FdFrX  (exact tag name)",
        ["Wildcard"]    = "e.g.  Col Ph*  (matches names starting with 'Col Ph')",
    }

    local curObj  = 1; local curSel = 1; local curMode = 1
    local selVal  = ""; local subVal = "1"
    local layName = "Layout 1"; local laySlot = "1"

    local W, H   = 1200, 680
    local rowH   = 78
    local labelW = 250
    local inputW = 630
    local padX   = math.floor((W - 40 - labelW - inputW - 20) / 2)
    local gap    = 20

    local base, scroll = buildBase(overlay,
        'Layout Builder v' .. PLUGIN_VERSION .. '  |  Step 1 -- Object Selection', W, H, 'onLB1Close')
    scroll.Name = 'lb1Scroll'

    local y = 16

    local cx = rowLabel(scroll, 'Object Type', y, rowH, labelW, padX, gap)
    local btnObj = cycleBtn(scroll, objTypes[curObj], cx, y, inputW, rowH, UI_CORAL, 'onCycleObj')
    y = y + rowH + 16

    cx = rowLabel(scroll, 'Select By', y, rowH, labelW, padX, gap)
    local btnSel = cycleBtn(scroll, selMethods[curSel], cx, y, inputW, rowH, UI_CYAN, 'onCycleSel')
    y = y + rowH + 16

    rowLabel(scroll, 'Selection', y, rowH, labelW, padX, gap)
    local edSel = scroll:Append('LineEdit')
    edSel.Text = ''; edSel.Font = 'Regular24'
    edSel.TextalignmentH = 'Centre'; edSel.W = inputW; edSel.H = rowH
    edSel.X = padX + labelW + gap; edSel.Y = y
    edSel.plugincomponent = myHandle; edSel.textchanged = 'onSelChanged'
    local selHint = scroll:Append('UIObject')
    selHint.Text = selHints[selMethods[curSel]]; selHint.Font = 'Regular20'
    selHint.TextalignmentH = 'Centre'; selHint.W = inputW; selHint.H = 28
    selHint.X = padX + labelW + gap; selHint.Y = y + rowH + 2
    y = y + rowH + 16 + 30

    -- SubFixture range (hidden unless SubFixture)
    local lblSub = scroll:Append('UIObject')
    lblSub.Text = 'SubFix Range'; lblSub.Font = 'Regular24'
    lblSub.TextalignmentH = 'Right'; lblSub.W = labelW; lblSub.H = rowH
    lblSub.X = padX; lblSub.Y = y; lblSub.Visible = 'No'
    local edSub = scroll:Append('LineEdit')
    edSub.Text = subVal; edSub.Font = 'Regular24'
    edSub.TextalignmentH = 'Centre'; edSub.W = inputW; edSub.H = rowH
    edSub.X = padX + labelW + gap; edSub.Y = y; edSub.Visible = 'No'
    edSub.plugincomponent = myHandle; edSub.textchanged = 'onSubChanged'
    y = y + rowH + 24

    y = divider(scroll, '--  Layout Target  --', y)

    cx = rowLabel(scroll, 'Layout Mode', y, rowH, labelW, padX, gap)
    local btnMode = cycleBtn(scroll, layModes[curMode], cx, y, inputW, rowH, UI_PURPLE, 'onCycleMode')
    y = y + rowH + 16

    cx = rowLabel(scroll, 'Layout Name', y, rowH, labelW, padX, gap)
    local edName = scroll:Append('LineEdit')
    edName.Text = layName; edName.Font = 'Regular24'
    edName.TextalignmentH = 'Centre'; edName.W = inputW; edName.H = rowH
    edName.X = cx; edName.Y = y
    edName.plugincomponent = myHandle; edName.textchanged = 'onNameChanged'
    y = y + rowH + 16

    local lblSlot = scroll:Append('UIObject')
    lblSlot.Text = 'Start Slot'; lblSlot.Font = 'Regular24'
    lblSlot.TextalignmentH = 'Right'; lblSlot.W = labelW; lblSlot.H = rowH
    lblSlot.X = padX; lblSlot.Y = y
    local edSlot = scroll:Append('LineEdit')
    edSlot.Text = laySlot; edSlot.Font = 'Regular24'
    edSlot.TextalignmentH = 'Centre'; edSlot.W = inputW; edSlot.H = rowH
    edSlot.X = padX + labelW + gap; edSlot.Y = y
    edSlot.plugincomponent = myHandle; edSlot.textchanged = 'onSlotChanged'

    local ok, cn = buildFooter(base, 2, 'Next  >')
    ok.clicked = 'onLB1Next'; cn.clicked = 'onLB1Close'

    base:WaitInit()   -- no FindBestFocus: console keys stay on the command line

    local function updateSubVisibility()
        local isSubFix = (objTypes[curObj] == "SubFixture")
        lblSub.Visible = isSubFix and 'Yes' or 'No'
        edSub.Visible  = isSubFix and 'Yes' or 'No'
    end

    signalTable.onCycleObj = function()
        curObj = (curObj % #objTypes) + 1
        btnObj.Text = objTypes[curObj]; updateSubVisibility()
    end
    signalTable.onCycleSel = function()
        curSel = (curSel % #selMethods) + 1
        btnSel.Text = selMethods[curSel]
        edSel.Text = ""; selVal = ""
        selHint.Text = selHints[selMethods[curSel]]
    end
    signalTable.onCycleMode = function()
        curMode = (curMode % #layModes) + 1
        btnMode.Text = layModes[curMode]
        lblSlot.Visible = (curMode == 1) and 'Yes' or 'No'
        edSlot.Visible  = (curMode == 1) and 'Yes' or 'No'
    end
    signalTable.onSelChanged  = function(c) selVal  = c.content or selVal  end
    signalTable.onSubChanged  = function(c) subVal  = c.content or subVal  end
    signalTable.onNameChanged = function(c) layName = c.content or layName end
    signalTable.onSlotChanged = function(c) laySlot = c.content or laySlot end

    signalTable.onLB1Next = function()
        local sel = trim(selVal)
        if sel == "" then ErrPrintf("Selection cannot be empty."); return end
        local nm = trim(layName)
        if nm == "" then ErrPrintf("Layout name cannot be empty."); return end
        local sn = math.floor(tonumber(laySlot) or 0)
        if curMode == 1 and sn < 1 then ErrPrintf("Start slot must be >= 1."); return end
        local ot = objTypes[curObj]
        if (ot == "Fixture" or ot == "SubFixture") and selMethods[curSel] ~= "Index Range" then
            ErrPrintf("Fixture / SubFixture only support Select By = Index Range.")
            return
        end
        if curMode == 2 then
            local okL, lay = pcall(function() return DataPool().Layouts[nm] end)
            if not okL or lay == nil then
                ErrPrintf("Existing layout \"%s\" not found.", nm)
                return
            end
        end
        result = {
            objType    = objTypes[curObj],
            selMethod  = selMethods[curSel],
            selValue   = sel,
            subValue   = trim(subVal),
            newLayout  = (curMode == 1),
            layoutName = nm,
            layoutSlot = sn,
        }
        overlay:ClearUIChildren(); done = true
    end
    signalTable.onLB1Close = function()
        overlay:ClearUIChildren(); done = true
    end

    repeat coroutine.yield() until done
    return result
end

-------------------------------------------------------------------------------
-- Object resolution
-------------------------------------------------------------------------------
local function wildcardToPattern(w)
    local p = w:gsub("([%.%+%-%^%$%(%)%[%]%%])", "%%%1")
    return "^" .. p:gsub("%*", ".*"):gsub("%?", ".") .. "$"
end

local function parseRange(s)
    local s2 = s:lower()
    local a, b = s2:match("(%d+)%s+thru%s+(%d+)")
    if a and b then return tonumber(a), tonumber(b) end
    local single = s:match("^%s*(%d+)%s*$")
    if single then return tonumber(single), tonumber(single) end
    return nil, nil
end

local function resolveObjects(step1)
    local objType   = step1.objType
    local selMethod = step1.selMethod
    local selValue  = step1.selValue
    local results   = {}

    if objType == "Fixture" or objType == "SubFixture" then
        local from, to = parseRange(selValue)
        if not from then ErrPrintf("Cannot parse fixture range: '%s'", selValue); return {} end
        for i = from, to do
            local label, assignTarget
            if objType == "SubFixture" then
                label = string.format("Fixture %d SubFix %s", i, step1.subValue)
                assignTarget = string.format("Fixture %d.%s", i, step1.subValue)
            else
                label = string.format("Fixture %d", i)
                assignTarget = string.format("Fixture %d", i)
            end
            table.insert(results, { label = label, assignTarget = assignTarget })
        end
        Printf("Resolved %d %s(s).", #results, objType)
        return results
    end

    local pool
    if     objType == "Sequence"  then pool = DataPool().Sequences
    elseif objType == "Group"     then pool = DataPool().Groups
    elseif objType == "Macro"     then pool = DataPool().Macros
    elseif objType == "Executor"  then pool = DataPool().Executors
    else ErrPrintf("Unknown type: %s", objType); return {} end

    if pool == nil then ErrPrintf("Pool not available for %s.", objType); return {} end
    local items = poolItems(pool)

    local function add(it)
        local name = trim(it.obj.name)
        if name == "" then return end
        table.insert(results, {
            label        = string.format("%s %d \"%s\"", objType, it.no, name),
            assignTarget = string.format("%s %d", objType, it.no),
        })
    end

    if selMethod == "Index Range" then
        local from, to = parseRange(selValue)
        if not from then ErrPrintf("Cannot parse range: '%s'", selValue); return {} end
        for _, it in ipairs(items) do
            if it.no >= from and it.no <= to then add(it) end
        end

    elseif selMethod == "Tag Name" then
        local want = selValue:lower()
        local tagHandle = nil
        for _, it in ipairs(poolItems(DataPool().Tags)) do
            if trim(it.obj.name):lower() == want then tagHandle = it.obj; break end
        end
        if not tagHandle then ErrPrintf("Tag not found: '%s'", selValue); return {} end
        for _, it in ipairs(items) do
            local okT, tags = pcall(function() return it.obj.tags end)
            if okT and tags then
                for _, tg in pairs(tags) do
                    local okN, tn = pcall(function() return tg.name end)
                    if tg == tagHandle or (okN and tn and trim(tn):lower() == want) then
                        add(it); break
                    end
                end
            end
        end

    elseif selMethod == "Wildcard" then
        local pat = wildcardToPattern(selValue)
        for _, it in ipairs(items) do
            if trim(it.obj.name):match(pat) then add(it) end
        end
    end

    Printf("Resolved %d object(s).", #results)
    return results
end

-------------------------------------------------------------------------------
-- Step 2 UI
-------------------------------------------------------------------------------
local function showStep2UI(overlay, objects, step1)
    local result, done = nil, false
    local count = #objects

    local sizePresets = {
        { label="Small",  w=80,  h=80  },
        { label="Medium", w=130, h=130 },
        { label="Large",  w=180, h=180 },
        { label="Wide",   w=200, h=100 },
        { label="Tall",   w=100, h=200 },
        { label="Custom", w=130, h=130 },
    }
    local actions = { "Go", "Toggle", "Flash", "Select" }

    local curSize   = 2; local curAction = 1
    local cols      = math.min(count, 10)
    local objW      = sizePresets[curSize].w
    local objH      = sizePresets[curSize].h
    local customW   = "130"; local customH = "130"
    local gapPx     = "5"
    local originX   = "0"; local originY = "0"

    local W, H   = 1200, 1000
    local rowH   = 76
    local labelW = 250
    local inputW = 630
    local padX   = math.floor((W - 40 - labelW - inputW - 20) / 2)
    local gap    = 20
    local half   = math.floor(inputW / 2) - 6

    local function gridSummary()
        local r = math.ceil(count / math.max(cols, 1))
        return string.format("%d cols  x  %d rows  (%d objects)", cols, r, count)
    end

    local base, scroll = buildBase(overlay,
        string.format('Layout Builder v%s  |  Step 2 -- Config  (%d objects)', PLUGIN_VERSION, count),
        W, H, 'onLB2Close')
    scroll.Name = 'lb2Scroll'

    local y = 12

    -- Info banner
    local info = scroll:Append('UIObject')
    info.Text = string.format('"%s"  ->  %s  |  %s',
        step1.selValue, step1.objType,
        step1.newLayout
            and ('New: "' .. step1.layoutName .. '" @ slot ' .. step1.layoutSlot)
            or  ('Existing: "' .. step1.layoutName .. '"'))
    info.Font = 'Regular24'; info.TextalignmentH = 'Centre'
    info.H = 40; info.Anchors = '0,0,1,0'; info.X = 0; info.Y = y
    y = y + 48

    -- Grid
    y = divider(scroll, '--  Grid  --', y)

    local cx = rowLabel(scroll, 'Columns', y, rowH, labelW, padX, gap)
    local edCols = scroll:Append('LineEdit')
    edCols.Text = tostring(cols); edCols.Font = 'Regular24'
    edCols.TextalignmentH = 'Centre'
    edCols.W = math.floor(inputW * 0.35); edCols.H = rowH; edCols.X = cx; edCols.Y = y
    edCols.plugincomponent = myHandle; edCols.textchanged = 'onColsChanged'
    local lblGrid = scroll:Append('UIObject')
    lblGrid.Text = gridSummary(); lblGrid.Font = 'Regular24'
    lblGrid.TextalignmentH = 'Left'
    lblGrid.W = math.ceil(inputW * 0.63); lblGrid.H = rowH
    lblGrid.X = cx + math.floor(inputW * 0.35) + 10; lblGrid.Y = y
    y = y + rowH + 16

    cx = rowLabel(scroll, 'Gap (px)', y, rowH, labelW, padX, gap)
    local edGap = scroll:Append('LineEdit')
    edGap.Text = gapPx; edGap.Font = 'Regular24'
    edGap.TextalignmentH = 'Centre'; edGap.W = inputW; edGap.H = rowH
    edGap.X = cx; edGap.Y = y
    edGap.plugincomponent = myHandle; edGap.textchanged = 'onGapChanged'
    y = y + rowH + 24

    -- Size
    y = divider(scroll, '--  Object Size  --', y)
    cx = rowLabel(scroll, 'Size', y, rowH, labelW, padX, gap)
    local function sizeLabel()
        local p = sizePresets[curSize]
        if p.label == "Custom" then return string.format("Custom  (%s x %s px)", customW, customH) end
        return string.format("%s  (%d x %d px)", p.label, p.w, p.h)
    end
    local btnSize = cycleBtn(scroll, sizeLabel(), cx, y, inputW, rowH, UI_GOLD, 'onCycleSize')
    y = y + rowH + 16

    local lblCust = scroll:Append('UIObject')
    lblCust.Text = 'W  x  H  (px)'; lblCust.Font = 'Regular24'
    lblCust.TextalignmentH = 'Right'; lblCust.W = labelW; lblCust.H = rowH
    lblCust.X = padX; lblCust.Y = y; lblCust.Visible = 'No'
    local edCW = scroll:Append('LineEdit')
    edCW.Text = customW; edCW.Font = 'Regular24'; edCW.TextalignmentH = 'Centre'
    edCW.W = half; edCW.H = rowH; edCW.X = padX + labelW + gap; edCW.Y = y
    edCW.plugincomponent = myHandle; edCW.textchanged = 'onCWChanged'; edCW.Visible = 'No'
    local edCH = scroll:Append('LineEdit')
    edCH.Text = customH; edCH.Font = 'Regular24'; edCH.TextalignmentH = 'Centre'
    edCH.W = half; edCH.H = rowH; edCH.X = padX + labelW + gap + half + 12; edCH.Y = y
    edCH.plugincomponent = myHandle; edCH.textchanged = 'onCHChanged'; edCH.Visible = 'No'
    y = y + rowH + 24

    -- Action
    y = divider(scroll, '--  Default Action  --', y)
    cx = rowLabel(scroll, 'Action', y, rowH, labelW, padX, gap)
    local btnAction = cycleBtn(scroll, actions[curAction], cx, y, inputW, rowH, UI_TEAL, 'onCycleAction')
    y = y + rowH + 24

    -- Grid origin
    y = divider(scroll, '--  Grid Origin  (optional, px)  --', y)
    local lblOX = scroll:Append('UIObject')
    lblOX.Text = 'Start X  /  Y'; lblOX.Font = 'Regular24'
    lblOX.TextalignmentH = 'Right'; lblOX.W = labelW; lblOX.H = rowH
    lblOX.X = padX; lblOX.Y = y
    local edOX = scroll:Append('LineEdit')
    edOX.Text = originX; edOX.Font = 'Regular24'; edOX.TextalignmentH = 'Centre'
    edOX.W = half; edOX.H = rowH; edOX.X = padX + labelW + gap; edOX.Y = y
    edOX.plugincomponent = myHandle; edOX.textchanged = 'onOXChanged'
    local edOY = scroll:Append('LineEdit')
    edOY.Text = originY; edOY.Font = 'Regular24'; edOY.TextalignmentH = 'Centre'
    edOY.W = half; edOY.H = rowH; edOY.X = padX + labelW + gap + half + 12; edOY.Y = y
    edOY.plugincomponent = myHandle; edOY.textchanged = 'onOYChanged'
    y = y + rowH + 24

    -- Visibility
    y = divider(scroll, '--  Element Visibility  --', y)
    local visItems = {
        { label = "Border",        prop = "visibilityBorder",       on = false },
        { label = "Indicator Bar", prop = "visibilityIndicatorBar", on = true  },
        { label = "Object Name",   prop = "visibilityObjectName",   on = true  },
        { label = "Object ID",     prop = "visibilityId",           on = false },
        { label = "Object CID",    prop = "visibilityCid",          on = false },
        { label = "Value",         prop = "visibilityValue",        on = false },
        { label = "Icon",          prop = "visibilityIcon",         on = true  },
    }
    local cbH  = 68
    local cbW  = math.floor((labelW + inputW + gap) / 2) - 8
    local visCBs = {}
    for i, item in ipairs(visItems) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local cb = scroll:Append('CheckBox')
        cb.Text = item.label; cb.Font = 'Regular24'
        cb.H = cbH; cb.W = cbW
        cb.X = padX + col * (cbW + 16); cb.Y = y + row * (cbH + 10)
        cb.State = item.on and 1 or 0
        cb.plugincomponent = myHandle; cb.clicked = 'onVisCBClick'
        visCBs[i] = cb
    end
    local visRows = math.ceil(#visItems / 2)
    y = y + visRows * (cbH + 10) + 16

    -- Tail spacer so last row isn't flush against bottom
    local tail = scroll:Append('UIObject')
    tail.H = 30; tail.W = 10; tail.X = 0; tail.Y = y

    local ok, cn = buildFooter(base, 2, 'Build Layout  >')
    ok.clicked = 'onLB2Build'; cn.clicked = 'onLB2Close'

    base:WaitInit()   -- no FindBestFocus: console keys stay on the command line

    -- Callbacks
    signalTable.onColsChanged = function(c)
        local v = math.floor(tonumber(c.content) or cols)
        if v >= 1 then cols = v; lblGrid.Text = gridSummary() end
    end
    signalTable.onGapChanged  = function(c) gapPx   = c.content or gapPx   end
    signalTable.onOXChanged   = function(c) originX = c.content or originX  end
    signalTable.onOYChanged   = function(c) originY = c.content or originY  end

    signalTable.onCycleSize = function()
        curSize = (curSize % #sizePresets) + 1
        local p = sizePresets[curSize]
        local isCustom = (p.label == "Custom")
        if not isCustom then objW = p.w; objH = p.h end
        lblCust.Visible = isCustom and 'Yes' or 'No'
        edCW.Visible    = isCustom and 'Yes' or 'No'
        edCH.Visible    = isCustom and 'Yes' or 'No'
        btnSize.Text    = sizeLabel()
    end
    signalTable.onCWChanged = function(c)
        customW = c.content or customW
        objW = math.floor(tonumber(customW) or 130)
        btnSize.Text = sizeLabel()
    end
    signalTable.onCHChanged = function(c)
        customH = c.content or customH
        objH = math.floor(tonumber(customH) or 130)
        btnSize.Text = sizeLabel()
    end
    signalTable.onCycleAction = function()
        curAction = (curAction % #actions) + 1
        btnAction.Text = actions[curAction]
    end
    signalTable.onVisCBClick = function(caller)
        caller.State = caller.State == 1 and 0 or 1
    end

    signalTable.onLB2Build = function()
        local vis = {}
        for i, item in ipairs(visItems) do
            vis[item.prop] = (visCBs[i].State == 1)
        end
        -- Parse origin -- math.floor handles negatives correctly
        local ox = math.floor(tonumber(originX) or 0)
        local oy = math.floor(tonumber(originY) or 0)
        result = {
            cols    = math.max(cols, 1),
            rows    = math.ceil(count / math.max(cols, 1)),
            objW    = objW,
            objH    = objH,
            gap     = math.floor(tonumber(gapPx) or 5),
            action  = actions[curAction],
            originX = ox,
            originY = oy,
            vis     = vis,
        }
        overlay:ClearUIChildren(); done = true
    end
    signalTable.onLB2Close = function()
        overlay:ClearUIChildren(); done = true
    end

    repeat coroutine.yield() until done
    return result
end

-------------------------------------------------------------------------------
-- Build layout
-------------------------------------------------------------------------------
-- Layout element "Action" values to try (first that reads back wins)
local ACTION_CANDIDATES = {
    Go     = { "Go+", "Go", "GoPlus" },
    Toggle = { "Toggle" },
    Flash  = { "Flash" },
    Select = { "Select" },
}
local function buildLayout(step1, step2, objects)
    local layoutName = step1.layoutName
    local cols       = step2.cols
    local objW       = step2.objW
    local objH       = step2.objH
    local gapPx      = step2.gap
    local action     = step2.action
    local originX    = step2.originX or 0
    local originY    = step2.originY or 0

    -- Find next free layout slot
    if step1.newLayout then
        local slot = step1.layoutSlot
        local used = {}
        for _, it in ipairs(poolItems(DataPool().Layouts)) do used[it.no] = true end
        while used[slot] do
            Printf("  Slot %d occupied -- advancing.", slot)
            slot = slot + 1
        end
        Printf("Creating layout \"%s\" at slot %d...", layoutName, slot)
        Cmd(string.format('Store Layout %d "%s" /nc', slot, layoutName))
    else
        Printf("Using existing layout \"%s\"...", layoutName)
    end

    Printf("Placing %d object(s)  |  %d cols  |  %dx%d px  |  gap %dpx  |  origin %d,%d  |  action: %s",
        #objects, cols, objW, objH, gapPx, originX, originY, action)

    -- Count existing elements BEFORE assigning so we know where new ones start.
    -- New elements will be at indices (existingCount+1) through (existingCount+#objects).
    local existingCount = 0
    local layout = DataPool().Layouts[layoutName]
    if layout then
        local ok2, cnt = pcall(function() return layout:Count() end)
        if ok2 and cnt then
            existingCount = cnt
        end
    end
    Printf("Layout has %d existing element(s) -- new elements start at index %d.",
        existingCount, existingCount + 1)

    progStart("Layout Builder", #objects * 2)

    -- PASS 1: Assign all objects first (Assign resets all positions each call)
    Printf("Pass 1: Assigning...")
    progText("Assigning objects...")
    for i, obj in ipairs(objects) do
        Cmd(string.format('Assign %s At Layout "%s" /nc', obj.assignTarget, layoutName))
        if i % 50 == 0 then Printf("  %d / %d assigned", i, #objects) end
        progStep()
    end

    -- PASS 2: Set position, size, visibility per element.
    -- Address new elements by offsetting from existingCount.
    Printf("Pass 2: Positioning...")
    progText("Positioning elements...")
    local actionVal = nil      -- resolved on the first element, reused after
    local actionTried = false
    for i, obj in ipairs(objects) do
        local col  = (i - 1) % cols
        local row  = math.floor((i - 1) / cols)
        local px   = originX + col * (objW + gapPx)
        -- MA3 layout posY increases upward: step DOWN so row 1 is on top
        local py   = originY - row * (objH + gapPx)
        local elemN = existingCount + i   -- correct index into the layout

        local addr = string.format('Layout "%s".%d', layoutName, elemN)
        Cmd(string.format('Set %s Property "posX"   %d', addr, px))
        Cmd(string.format('Set %s Property "posY"   %d', addr, py))
        Cmd(string.format('Set %s Property "Width"  %d', addr, objW))
        Cmd(string.format('Set %s Property "Height" %d', addr, objH))

        if step2.vis then
            for prop, isOn in pairs(step2.vis) do
                Cmd(string.format('Set %s Property "%s" "%s"',
                    addr, prop, isOn and "Visible" or "Hidden"))
            end
        end

        -- Default action: try candidate values on the first element and keep
        -- the first one that reads back correctly.
        if not actionTried then
            actionTried = true
            local cands = ACTION_CANDIDATES[action] or { action }
            local okL, lay = pcall(function() return DataPool().Layouts[layoutName] end)
            local readable = false
            for _, v in ipairs(cands) do
                Cmd(string.format('Set %s Property "Action" "%s"', addr, v))
                local got = ""
                if okL and lay then
                    local okE, el = pcall(function() return lay[elemN] end)
                    if okE and el then
                        local okA, av = pcall(function() return el.action end)
                        got = okA and tostring(av) or ""
                    end
                end
                Printf("  Action try '%s' -> element reads '%s'", v, got)
                if got ~= "" then readable = true end
                if got:lower():gsub("[^%w]", "") == v:lower():gsub("[^%w]", "") then
                    actionVal = v; break
                end
            end
            if not actionVal and not readable then
                -- can't read the property back: use the first candidate everywhere
                actionVal = cands[1]
                Cmd(string.format('Set %s Property "Action" "%s"', addr, actionVal))
                ErrPrintf("Layout Builder: action '%s' set but not verifiable -- check an element.", actionVal)
            elseif not actionVal then
                ErrPrintf("Layout Builder: no candidate for action '%s' was accepted -- check element Action manually.", action)
            end
        elseif actionVal then
            Cmd(string.format('Set %s Property "Action" "%s"', addr, actionVal))
        end

        if i % 50 == 0 then Printf("  %d / %d positioned", i, #objects) end
        progStep()
    end
    progStop()

    Printf("=== Layout Builder complete ===")
    Printf("  Layout : \"%s\"  |  %d objects  |  %dx%d grid  |  action %s",
        layoutName, #objects, cols, step2.rows, tostring(actionVal or "not set"))
    Printf("  Size   : %dx%d px  |  gap %d px  |  origin %d,%d",
        objW, objH, gapPx, originX, originY)
end

-------------------------------------------------------------------------------
-- Entry point
-------------------------------------------------------------------------------
local function main()
    initColors()
    local overlay = GetFocusDisplay().ScreenOverlay

    local step1 = showStep1UI(overlay)
    if not step1 then Printf("Layout Builder: cancelled."); return end

    local objects = resolveObjects(step1)
    if #objects == 0 then
        ErrPrintf("No objects found. Check selection and try again.")
        return
    end
    Printf("Found %d object(s).", #objects)

    local step2 = showStep2UI(overlay, objects, step1)
    if not step2 then Printf("Layout Builder: cancelled."); return end

    buildLayout(step1, step2, objects)
end

return main
