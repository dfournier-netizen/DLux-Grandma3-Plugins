--[[
    SetNShot.lua
    GrandMA3 Plugin -- Verified against Release Notes v2.4 (2026-05-18)

    PURPOSE:
        Applies the NShot property to every matching phaser recipe across a
        user-defined range of cues and recipes in a sequence.

    UI DESIGN:
        Two-tone opaque look using named CFG color group entries (the same
        technique used in CreateFixtureGroups / MAgic Builder). All colors
        are fully opaque (FF alpha). Dark panel background with a lighter
        row stripe for alternating sections. Accent color used on the title
        bar and active toggle states.

    SEQUENCE SELECTION:
        User can either type a sequence number manually OR tap
        "Use Selected Sequence" which calls SelectedSequence() to resolve
        the currently-selected sequence at apply-time.

    NShot (phaser recipes -- 2+ steps only, per v2.4 release notes):
        * Unlimited   -> PlaybackNShot 0  (confirmed on console)
        * Custom #    -> any positive number or decimal (e.g. 1, 0.75, 4)
                        (only set when Custom # mode is active)
--]]

local pluginName    = select(1, ...)
local componentName = select(2, ...)
local signalTable   = select(3, ...)
local myHandle      = select(4, ...)

-------------------------------------------------------------------------------
-- CONSTANTS
-------------------------------------------------------------------------------

local PLUGIN_VERSION  = "2.1.1"
local NSHOT_UNLIMITED = "0"   -- confirmed on console: PlaybackNShot 0 = Unlimited
local MODE_UNLIMITED  = "Unlimited"
local MODE_CUSTOM     = "Custom"

-------------------------------------------------------------------------------
-- LAYER 1 -- Helpers
-------------------------------------------------------------------------------

local function trim(s)
    return s and s:match("^%s*(.-)%s*$") or ""
end

local function parsePosInt(s)
    s = trim(s)
    local n = tonumber(s)
    if n == nil or n < 1 or math.floor(n) ~= n then return nil end
    return math.floor(n)
end

local function parseNonNegNumber(s)
    s = trim(s)
    local n = tonumber(s)
    return (n ~= nil and n >= 0) and n or nil
end

local function parsePosNumber(s)
    local n = parseNonNegNumber(s)
    return (n ~= nil and n > 0) and n or nil
end

-------------------------------------------------------------------------------
-- LAYER 2 -- Color System (CFG ColorGroup pattern from CreateFixtureGroups)
--
-- Returns "CFG.<name>" strings usable directly as BackColor values.
-- All colors are fully opaque (FF alpha) for a clean, solid look.
-------------------------------------------------------------------------------

-- Color palette -- two-tone scheme:
--   DARK   : deep charcoal -- main panel background, label backgrounds
--   MID    : medium grey   -- row / input area background (second tone)
--   ACCENT : MA3 gold/amber -- title bar, active state highlight
--   DIM    : muted blue-grey -- inactive toggle buttons
--   GREEN  : confirm action
--   RED    : cancel / destructive action

local C = {
    DARK   = { name = "NS_DARK",   rgba = "1A1D21FF" },   -- near-black charcoal
    MID    = { name = "NS_MID",    rgba = "2C3038FF" },   -- blue-grey panel row
    ACCENT = { name = "NS_ACCENT", rgba = "C8900AFF" },   -- MA3-style amber/gold
    DIM    = { name = "NS_DIM",    rgba = "3A3F4BFF" },   -- muted inactive button
    GREEN  = { name = "NS_GREEN",  rgba = "1A7A40FF" },   -- apply / confirm green
    RED    = { name = "NS_RED",    rgba = "8C1F0EFF" },   -- cancel / danger red
    BRIGHT = { name = "NS_BRIGHT", rgba = "E8A812FF" },   -- bright amber -- active toggle
}

-- Resolved color strings, set by initColors()
local COL = {}

local function getOrCreateColorDef(name, rgba)
    local colorGroups = Root().ColorTheme.ColorGroups
    if not colorGroups then
        ErrPrintf("SetNShot: ColorTheme.ColorGroups not found")
        return "Global.Default"
    end

    local cfgGroup = colorGroups["CFG"]
    if not cfgGroup then
        local gIdx = 1
        while colorGroups[gIdx] ~= nil do gIdx = gIdx + 1 end
        Cmd("cd root /nu")
        Cmd("cd \"ColorTheme\" /nu")
        Cmd("cd \"ColorGroups\" /nu")
        Cmd("store " .. tostring(gIdx) .. " /nu")
        Cmd("label " .. tostring(gIdx) .. " \"CFG\" /nu")
        Cmd("cd root /nu")
        cfgGroup = colorGroups["CFG"]
        if not cfgGroup then
            ErrPrintf("SetNShot: Failed to create CFG color group")
            return "Global.Default"
        end
    end

    local entry    = cfgGroup[name]
    local entryIdx

    if entry then
        entryIdx = entry.index
    else
        entryIdx = 1
        while cfgGroup[entryIdx] ~= nil do entryIdx = entryIdx + 1 end
        Cmd("cd root /nu")
        Cmd("cd \"ColorTheme\" /nu")
        Cmd("cd \"ColorGroups\" /nu")
        Cmd("cd \"CFG\" /nu")
        Cmd("store " .. tostring(entryIdx) .. " /nu")
        Cmd("label " .. tostring(entryIdx) .. " \"" .. name .. "\" /nu")
        Cmd("cd root /nu")
    end

    -- Always refresh the RGBA value
    Cmd("cd root /nu")
    Cmd("cd \"ColorTheme\" /nu")
    Cmd("cd \"ColorGroups\" /nu")
    Cmd("cd \"CFG\" /nu")
    Cmd(string.format('set %d RGBA="%s" /nu', entryIdx, rgba))
    Cmd("cd root /nu")

    return "CFG." .. name
end

local function initColors()
    for key, def in pairs(C) do
        COL[key] = getOrCreateColorDef(def.name, def.rgba)
    end
end

-------------------------------------------------------------------------------
-- LAYER 3 -- UI widget builders
-------------------------------------------------------------------------------

-- Title bar: ACCENT background, returns close button handle.
local function buildTitleBar(base, text)
    local bar             = base:Append('TitleBar')
    bar.Columns           = 2
    bar.Rows              = 1
    bar.Anchors           = '0,0'
    bar.BackColor         = COL.ACCENT

    local title           = bar:Append('TitleButton')
    title.Text            = text
    title.Anchors         = '0,0'

    local close           = bar:Append('CloseButton')
    close.Anchors         = '1,0'
    close.plugincomponent = myHandle
    return close
end

-- Two-button footer: green primary + red cancel.
local function buildFooter(base, anchorRow, primaryLabel)
    local grid              = base:Append('UILayoutGrid')
    grid.Columns            = 2
    grid.Rows               = 1
    grid.H                  = 66
    grid.Anchors            = '0,' .. anchorRow

    local primary           = grid:Append('Button')
    primary.Anchors         = '0,0'
    primary.Text            = primaryLabel
    primary.TextalignmentH  = 'Centre'
    primary.HasHover        = 'Yes'
    primary.plugincomponent = myHandle
    primary.BackColor       = COL.GREEN

    local cancel            = grid:Append('Button')
    cancel.Anchors          = '1,0'
    cancel.Text             = 'Cancel'
    cancel.TextalignmentH   = 'Centre'
    cancel.HasHover         = 'Yes'
    cancel.plugincomponent  = myHandle
    cancel.BackColor        = COL.RED

    return primary, cancel
end

-- Section header row: DARK background with left-aligned uppercase label.
local function buildSectionHeader(sb, text, x, y, w, h)
    local bg            = sb:Append('UIObject')
    bg.W                = w
    bg.H                = h
    bg.X                = x
    bg.Y                = y
    bg.BackColor        = COL.DARK

    local lbl           = sb:Append('UIObject')
    lbl.Text            = text
    lbl.Font            = 'Regular20'
    lbl.TextalignmentH  = 'Left'
    lbl.W               = w - 16
    lbl.H               = h
    lbl.X               = x + 12
    lbl.Y               = y
    return h
end

-- Row stripe background (MID color), spans full content width.
local function buildRowBg(sb, x, y, w, h)
    local bg        = sb:Append('UIObject')
    bg.W            = w
    bg.H            = h
    bg.X            = x
    bg.Y            = y
    bg.BackColor    = COL.MID
end

-- Standard label (right-aligned) + LineEdit pair. Returns the LineEdit.
local function buildInputRow(sb, labelText, defaultVal, x, y,
                              labelW, inputW, rowH, gap, signal)
    local lbl               = sb:Append('UIObject')
    lbl.Text                = labelText
    lbl.Font                = 'Regular20'
    lbl.TextalignmentH      = 'Right'
    lbl.W                   = labelW
    lbl.H                   = rowH
    lbl.X                   = x
    lbl.Y                   = y

    local ed                = sb:Append('LineEdit')
    ed.Text                 = tostring(defaultVal)
    ed.Font                 = 'Regular24'
    ed.TextalignmentH       = 'Centre'
    ed.W                    = inputW
    ed.H                    = rowH
    ed.X                    = x + labelW + gap
    ed.Y                    = y
    ed.plugincomponent      = myHandle
    ed.textchanged          = signal
    return ed
end

-- Label + two side-by-side LineEdits (From / To). Returns fromEd, toEd.
local function buildRangeRow(sb, labelText, defFrom, defTo, x, y,
                              labelW, inputW, rowH, gap,
                              sigFrom, sigTo)
    local lbl               = sb:Append('UIObject')
    lbl.Text                = labelText
    lbl.Font                = 'Regular20'
    lbl.TextalignmentH      = 'Right'
    lbl.W                   = labelW
    lbl.H                   = rowH
    lbl.X                   = x
    lbl.Y                   = y

    local halfW             = math.floor((inputW - gap) / 2)
    local ex                = x + labelW + gap

    -- Sub-labels
    local sl1               = sb:Append('UIObject')
    sl1.Text                = 'From'
    sl1.Font                = 'Regular20'
    sl1.TextalignmentH      = 'Centre'
    sl1.W                   = halfW
    sl1.H                   = 28
    sl1.X                   = ex
    sl1.Y                   = y - 30

    local sl2               = sb:Append('UIObject')
    sl2.Text                = 'To  (blank = all)'
    sl2.Font                = 'Regular20'
    sl2.TextalignmentH      = 'Centre'
    sl2.W                   = halfW
    sl2.H                   = 28
    sl2.X                   = ex + halfW + gap
    sl2.Y                   = y - 30

    local fromEd            = sb:Append('LineEdit')
    fromEd.Text             = tostring(defFrom)
    fromEd.Font             = 'Regular24'
    fromEd.TextalignmentH   = 'Centre'
    fromEd.W                = halfW
    fromEd.H                = rowH
    fromEd.X                = ex
    fromEd.Y                = y
    fromEd.plugincomponent  = myHandle
    fromEd.textchanged      = sigFrom

    local toEd              = sb:Append('LineEdit')
    toEd.Text               = tostring(defTo)
    toEd.Font               = 'Regular24'
    toEd.TextalignmentH     = 'Centre'
    toEd.W                  = halfW
    toEd.H                  = rowH
    toEd.X                  = ex + halfW + gap
    toEd.Y                  = y
    toEd.plugincomponent    = myHandle
    toEd.textchanged        = sigTo

    return fromEd, toEd
end

-- Two-option toggle button pair. Returns btnA, btnB.
-- defaultA: true means option A is active initially.
local function buildTogglePair(sb, labelText, labelA, labelB,
                                x, y, labelW, inputW, rowH, gap,
                                sigA, sigB, defaultA)
    local lbl               = sb:Append('UIObject')
    lbl.Text                = labelText
    lbl.Font                = 'Regular20'
    lbl.TextalignmentH      = 'Right'
    lbl.W                   = labelW
    lbl.H                   = rowH
    lbl.X                   = x
    lbl.Y                   = y

    local hw                = math.floor((inputW - gap) / 2)
    local ex                = x + labelW + gap

    local btnA              = sb:Append('Button')
    btnA.Text               = labelA
    btnA.TextalignmentH     = 'Centre'
    btnA.W                  = hw
    btnA.H                  = rowH
    btnA.X                  = ex
    btnA.Y                  = y
    btnA.HasHover           = 'Yes'
    btnA.plugincomponent    = myHandle
    btnA.clicked            = sigA
    btnA.BackColor          = defaultA  and COL.BRIGHT or COL.DIM

    local btnB              = sb:Append('Button')
    btnB.Text               = labelB
    btnB.TextalignmentH     = 'Centre'
    btnB.W                  = hw
    btnB.H                  = rowH
    btnB.X                  = ex + hw + gap
    btnB.Y                  = y
    btnB.HasHover           = 'Yes'
    btnB.plugincomponent    = myHandle
    btnB.clicked            = sigB
    btnB.BackColor          = (not defaultA) and COL.BRIGHT or COL.DIM

    return btnA, btnB
end

-- Small hint text row.
local function buildHint(sb, text, x, y, w)
    local hint          = sb:Append('UIObject')
    hint.Text           = text
    hint.Font           = 'Regular20'
    hint.TextalignmentH = 'Centre'
    hint.W              = w
    hint.H              = 22
    hint.X              = x
    hint.Y              = y
end

-------------------------------------------------------------------------------
-- LAYER 4 -- Dialog
-------------------------------------------------------------------------------

local function showInputUI(overlay)
    local result = nil
    local done   = false

    -- -- Layout constants -----------------------------------------------------
    local PAD     = 16
    local GAP     = 10
    local SECTH   = 32
    local ROWH    = 62
    local ROWGAP  = 8
    local SUBLBL  = 30
    local SECGAP  = 6

    local WIN_W   = 760
    local SB_W    = 20
    local LABEL_W = 220
    local INPUT_W = WIN_W - SB_W - PAD * 2 - LABEL_W - GAP

    -- -- Live state ------------------------------------------------------------
    local useSelectedSeq = false
    local curSeqFrom     = '1'
    local curSeqTo       = ''       -- blank = single sequence
    local curCueFrom     = '1'
    local curCueTo       = ''
    local curRecFrom     = '1'
    local curRecTo       = ''

    -- NShot
    local curNShotStr    = '1'
    local curNShotMode   = MODE_CUSTOM   -- MODE_UNLIMITED or MODE_CUSTOM
    local setNShot       = true          -- checkbox: apply NShot

    -- Direction
    local curDirection   = 'Forward'
    local setDirection   = false

    -- Measure
    local curMeasure     = '1'
    local setMeasure     = false

    -- Width
    local curWidth          = '100'
    local setWidth          = false
    local setAdaptiveWidth  = false   -- mutually exclusive with setWidth

    -- Measure adaptive
    local setAdaptiveMeasure = false  -- mutually exclusive with setMeasure

    -- Button/toggle handles
    local btnUseSelected, btnManual
    local seqInput, seqToInput
    local btnUnlim, btnCustom
    local btnDirFwd, btnDirBwd, btnDirAlt
    local btnNShotOn, btnNShotOff
    local btnDirOn,   btnDirOff
    local btnMeasOn,  btnMeasOff
    local btnWidthOn, btnWidthOff
    local btnAdaptMeasOn,  btnAdaptMeasOff
    local btnAdaptWidthOn, btnAdaptWidthOff
    local widthValueInput                    -- LineEdit handle for greying
    local measValueInput                     -- LineEdit handle for greying

    -- -- Helper: two-state enable/disable toggle (On/Off) ---------------------
    local function buildEnableRow(sb_, labelText, y, sigOn, sigOff, defaultOn)
        local hw  = math.floor((INPUT_W - GAP) / 2)
        local ex  = PAD + LABEL_W + GAP

        local lbl           = sb_:Append('UIObject')
        lbl.Text            = labelText
        lbl.Font            = 'Regular20'
        lbl.TextalignmentH  = 'Right'
        lbl.W               = LABEL_W
        lbl.H               = ROWH
        lbl.X               = PAD
        lbl.Y               = y

        local bOn           = sb_:Append('Button')
        bOn.Text            = 'Apply'
        bOn.TextalignmentH  = 'Centre'
        bOn.W               = hw
        bOn.H               = ROWH
        bOn.X               = ex
        bOn.Y               = y
        bOn.HasHover        = 'Yes'
        bOn.plugincomponent = myHandle
        bOn.clicked         = sigOn
        bOn.BackColor       = defaultOn and COL.BRIGHT or COL.DIM

        local bOff          = sb_:Append('Button')
        bOff.Text           = 'Skip'
        bOff.TextalignmentH = 'Centre'
        bOff.W              = hw
        bOff.H              = ROWH
        bOff.X              = ex + hw + GAP
        bOff.Y              = y
        bOff.HasHover       = 'Yes'
        bOff.plugincomponent= myHandle
        bOff.clicked        = sigOff
        bOff.BackColor      = defaultOn and COL.DIM or COL.BRIGHT

        return bOn, bOff
    end

    -- -- Build base ------------------------------------------------------------
    local base              = overlay:Append('BaseInput')
    base.H                  = 960
    base.W                  = WIN_W
    base.Columns            = 1
    base.Rows               = 3
    base[1][1].SizePolicy   = 'Fixed'
    base[1][1].Size         = 55
    base[1][2].SizePolicy   = 'Stretch'
    base[1][3].SizePolicy   = 'Fixed'
    base[1][3].Size         = 66
    base.AutoClose          = 'No'
    base.CloseOnEscape      = 'Yes'
    base.BackColor          = COL.DARK

    local closeBtn          = buildTitleBar(base, 'Set Phaser Recipe Properties  v' .. PLUGIN_VERSION)
    closeBtn.clicked        = 'onNS_Close'

    local sb                = base:Append('ScrollBox')
    sb.Name                 = 'nshotScrollBox'
    sb.Anchors              = '0,1'

    local scrollBar         = base:Append('ScrollBarV')
    scrollBar.ScrollTarget  = sb      -- direct object reference
    scrollBar.Anchors       = '0,1'

    local Y   = 0
    local CW  = WIN_W - SB_W - PAD * 2

    -- =======================================================================
    -- SECTION 1: SEQUENCE
    -- =======================================================================
    buildSectionHeader(sb, '  SEQUENCE', 0, Y, WIN_W - SB_W, SECTH)
    Y = Y + SECTH + SECGAP

    -- Source toggle: Use Selected / Enter Manually
    buildRowBg(sb, PAD, Y, CW, ROWH)
    btnUseSelected, btnManual = buildTogglePair(
        sb, 'Source',
        'Use Selected Seq', 'Enter Manually',
        PAD, Y, LABEL_W, INPUT_W, ROWH, GAP,
        'onNS_UseSelected', 'onNS_Manual', false
    )
    Y = Y + ROWH + ROWGAP

    -- Sequence From / To range row
    Y = Y + SUBLBL
    buildRowBg(sb, PAD, Y, CW, ROWH)
    buildRangeRow(sb, 'Sequence  #', '1', '', PAD, Y,
                  LABEL_W, INPUT_W, ROWH, GAP,
                  'onNS_SeqFrom', 'onNS_SeqTo')
    Y = Y + ROWH + ROWGAP

    -- =======================================================================
    -- SECTION 2: CUE RANGE
    -- =======================================================================
    Y = Y + 4
    buildSectionHeader(sb, '  CUE RANGE  --  by cue number  (decimals ok, e.g. 1.5)', 0, Y, WIN_W - SB_W, SECTH)
    Y = Y + SECTH + SECGAP + SUBLBL

    buildRowBg(sb, PAD, Y, CW, ROWH)
    buildRangeRow(sb, 'Cue  #', '1', '', PAD, Y,
                  LABEL_W, INPUT_W, ROWH, GAP,
                  'onNS_CueFrom', 'onNS_CueTo')
    Y = Y + ROWH + ROWGAP

    -- =======================================================================
    -- SECTION 3: RECIPE RANGE
    -- =======================================================================
    Y = Y + 4
    buildSectionHeader(sb, '  RECIPE RANGE  --  1-based index within part', 0, Y, WIN_W - SB_W, SECTH)
    Y = Y + SECTH + SECGAP + SUBLBL

    buildRowBg(sb, PAD, Y, CW, ROWH)
    buildRangeRow(sb, 'Recipe  #', '1', '', PAD, Y,
                  LABEL_W, INPUT_W, ROWH, GAP,
                  'onNS_RecFrom', 'onNS_RecTo')
    Y = Y + ROWH + ROWGAP

    -- =======================================================================
    -- SECTION 4: NSHOT
    -- =======================================================================
    Y = Y + 4
    buildSectionHeader(sb, '  NSHOT', 0, Y, WIN_W - SB_W, SECTH)
    Y = Y + SECTH + SECGAP

    -- Apply / Skip toggle
    buildRowBg(sb, PAD, Y, CW, ROWH)
    btnNShotOn, btnNShotOff = buildEnableRow(sb, 'NShot', Y,
                                              'onNS_NShotOn', 'onNS_NShotOff', true)
    Y = Y + ROWH + ROWGAP

    -- Unlimited / Custom # mode
    buildRowBg(sb, PAD, Y, CW, ROWH)
    btnUnlim, btnCustom = buildTogglePair(
        sb, 'Mode',
        'Unlimited  (loop)', 'Custom  #',
        PAD, Y, LABEL_W, INPUT_W, ROWH, GAP,
        'onNS_ModeUnlim', 'onNS_ModeCustom', false
    )
    btnCustom.BackColor = COL.BRIGHT
    Y = Y + ROWH + ROWGAP

    -- Custom value input
    buildRowBg(sb, PAD, Y, CW, ROWH)
    buildInputRow(sb, 'Custom  #', '1', PAD, Y,
                  LABEL_W, INPUT_W, ROWH, GAP, 'onNS_NShotStr')
    Y = Y + ROWH + ROWGAP

    buildHint(sb, '1 = one shot   |   0.75 = 75% of a cycle   |   4 = four full cycles',
              PAD, Y, CW)
    Y = Y + 22 + ROWGAP

    -- =======================================================================
    -- SECTION 5: DIRECTION
    -- =======================================================================
    Y = Y + 4
    buildSectionHeader(sb, '  DIRECTION', 0, Y, WIN_W - SB_W, SECTH)
    Y = Y + SECTH + SECGAP

    -- Apply / Skip toggle
    buildRowBg(sb, PAD, Y, CW, ROWH)
    btnDirOn, btnDirOff = buildEnableRow(sb, 'Direction', Y,
                                          'onNS_DirOn', 'onNS_DirOff', false)
    Y = Y + ROWH + ROWGAP

    -- Three-way direction selector
    buildRowBg(sb, PAD, Y, CW, ROWH)
    do
        local thirdW = math.floor((INPUT_W - GAP * 2) / 3)
        local ex     = PAD + LABEL_W + GAP

        local lbl           = sb:Append('UIObject')
        lbl.Text            = 'Value'
        lbl.Font            = 'Regular20'
        lbl.TextalignmentH  = 'Right'
        lbl.W               = LABEL_W
        lbl.H               = ROWH
        lbl.X               = PAD
        lbl.Y               = Y

        btnDirFwd           = sb:Append('Button')
        btnDirFwd.Text      = 'Forward'
        btnDirFwd.TextalignmentH = 'Centre'
        btnDirFwd.W         = thirdW
        btnDirFwd.H         = ROWH
        btnDirFwd.X         = ex
        btnDirFwd.Y         = Y
        btnDirFwd.HasHover  = 'Yes'
        btnDirFwd.plugincomponent = myHandle
        btnDirFwd.clicked   = 'onNS_DirFwd'
        btnDirFwd.BackColor = COL.BRIGHT   -- default

        btnDirBwd           = sb:Append('Button')
        btnDirBwd.Text      = 'Backward'
        btnDirBwd.TextalignmentH = 'Centre'
        btnDirBwd.W         = thirdW
        btnDirBwd.H         = ROWH
        btnDirBwd.X         = ex + thirdW + GAP
        btnDirBwd.Y         = Y
        btnDirBwd.HasHover  = 'Yes'
        btnDirBwd.plugincomponent = myHandle
        btnDirBwd.clicked   = 'onNS_DirBwd'
        btnDirBwd.BackColor = COL.DIM

        btnDirAlt           = sb:Append('Button')
        btnDirAlt.Text      = 'Alternate'
        btnDirAlt.TextalignmentH = 'Centre'
        btnDirAlt.W         = thirdW
        btnDirAlt.H         = ROWH
        btnDirAlt.X         = ex + (thirdW + GAP) * 2
        btnDirAlt.Y         = Y
        btnDirAlt.HasHover  = 'Yes'
        btnDirAlt.plugincomponent = myHandle
        btnDirAlt.clicked   = 'onNS_DirAlt'
        btnDirAlt.BackColor = COL.DIM
    end
    Y = Y + ROWH + ROWGAP

    -- =======================================================================
    -- SECTION 6: MEASURE
    -- =======================================================================
    Y = Y + 4
    buildSectionHeader(sb, '  MEASURE', 0, Y, WIN_W - SB_W, SECTH)
    Y = Y + SECTH + SECGAP

    -- PlaybackMeasure: Apply / Skip
    buildRowBg(sb, PAD, Y, CW, ROWH)
    btnMeasOn, btnMeasOff = buildEnableRow(sb, 'Measure', Y,
                                            'onNS_MeasOn', 'onNS_MeasOff', false)
    Y = Y + ROWH + ROWGAP

    buildRowBg(sb, PAD, Y, CW, ROWH)
    measValueInput = buildInputRow(sb, 'Value', '1', PAD, Y,
                                   LABEL_W, INPUT_W, ROWH, GAP, 'onNS_Measure')
    Y = Y + ROWH + ROWGAP

    -- PlaybackAdaptiveMeasure: Apply Yes / Skip (mutually exclusive with Measure)
    buildRowBg(sb, PAD, Y, CW, ROWH)
    btnAdaptMeasOn, btnAdaptMeasOff = buildEnableRow(sb, 'Adaptive Measure', Y,
                                                      'onNS_AdaptMeasOn', 'onNS_AdaptMeasOff', false)
    Y = Y + ROWH + ROWGAP

    -- =======================================================================
    -- SECTION 7: WIDTH
    -- =======================================================================
    Y = Y + 4
    buildSectionHeader(sb, '  WIDTH', 0, Y, WIN_W - SB_W, SECTH)
    Y = Y + SECTH + SECGAP

    -- PlaybackWidth: Apply / Skip
    buildRowBg(sb, PAD, Y, CW, ROWH)
    btnWidthOn, btnWidthOff = buildEnableRow(sb, 'Width', Y,
                                              'onNS_WidthOn', 'onNS_WidthOff', false)
    Y = Y + ROWH + ROWGAP

    buildRowBg(sb, PAD, Y, CW, ROWH)
    widthValueInput = buildInputRow(sb, 'Value  (0-100)', '100', PAD, Y,
                                    LABEL_W, INPUT_W, ROWH, GAP, 'onNS_Width')
    Y = Y + ROWH + ROWGAP

    -- PlaybackAdaptiveWidth: Apply Yes / Skip (mutually exclusive with Width)
    buildRowBg(sb, PAD, Y, CW, ROWH)
    btnAdaptWidthOn, btnAdaptWidthOff = buildEnableRow(sb, 'Adaptive Width', Y,
                                                        'onNS_AdaptWidthOn', 'onNS_AdaptWidthOff', false)
    Y = Y + ROWH + ROWGAP

    -- -- Footer ---------------------------------------------------------------
    local applyBtn, cancelBtn = buildFooter(base, 2, '  Apply')
    applyBtn.clicked          = 'onNS_Apply'
    cancelBtn.clicked         = 'onNS_Close'

    base:WaitInit()
    -- No FindBestFocus: leave focus on the command line so console keys work.

    -- -- Refresh helpers -------------------------------------------------------

    local function refreshSeqToggle()
        btnUseSelected.BackColor = useSelectedSeq      and COL.BRIGHT or COL.DIM
        btnManual.BackColor      = (not useSelectedSeq) and COL.BRIGHT or COL.DIM
    end

    local function refreshModeToggle()
        btnUnlim.BackColor  = (curNShotMode == MODE_UNLIMITED) and COL.BRIGHT or COL.DIM
        btnCustom.BackColor = (curNShotMode == MODE_CUSTOM)    and COL.BRIGHT or COL.DIM
    end

    local function refreshDirButtons()
        btnDirFwd.BackColor = (curDirection == 'Forward')   and COL.BRIGHT or COL.DIM
        btnDirBwd.BackColor = (curDirection == 'Backward')  and COL.BRIGHT or COL.DIM
        btnDirAlt.BackColor = (curDirection == 'Alternate') and COL.BRIGHT or COL.DIM
    end

    local function refreshEnablePair(bOn, bOff, enabled)
        bOn.BackColor  = enabled       and COL.BRIGHT or COL.DIM
        bOff.BackColor = (not enabled) and COL.BRIGHT or COL.DIM
    end

    -- Grey out a LineEdit when its sibling adaptive toggle takes over
    local function setInputGreyed(input, greyed)
        if input then
            if greyed then
                pcall(function() input.BackColor = COL.DIM end)
            else
                pcall(function() input.BackColor = nil end)
            end
        end
    end

    local function refreshMeasureState()
        refreshEnablePair(btnMeasOn,      btnMeasOff,      setMeasure)
        refreshEnablePair(btnAdaptMeasOn, btnAdaptMeasOff, setAdaptiveMeasure)
        setInputGreyed(measValueInput, setAdaptiveMeasure)
        if setAdaptiveMeasure then
            setMeasure = false
            refreshEnablePair(btnMeasOn, btnMeasOff, false)
        end
    end

    local function refreshWidthState()
        refreshEnablePair(btnWidthOn,      btnWidthOff,      setWidth)
        refreshEnablePair(btnAdaptWidthOn, btnAdaptWidthOff, setAdaptiveWidth)
        setInputGreyed(widthValueInput, setAdaptiveWidth)
        if setAdaptiveWidth then
            setWidth = false
            refreshEnablePair(btnWidthOn, btnWidthOff, false)
        end
    end

    -- -- Callbacks -------------------------------------------------------------

    signalTable.onNS_UseSelected = function(c)
        useSelectedSeq = true; refreshSeqToggle()
    end
    signalTable.onNS_Manual = function(c)
        useSelectedSeq = false; refreshSeqToggle()
    end

    signalTable.onNS_SeqFrom  = function(c) curSeqFrom  = c.content or curSeqFrom  end
    signalTable.onNS_SeqTo    = function(c) curSeqTo    = c.content or curSeqTo    end
    signalTable.onNS_CueFrom  = function(c) curCueFrom  = c.content or curCueFrom  end
    signalTable.onNS_CueTo    = function(c) curCueTo    = c.content or curCueTo    end
    signalTable.onNS_RecFrom  = function(c) curRecFrom  = c.content or curRecFrom  end
    signalTable.onNS_RecTo    = function(c) curRecTo    = c.content or curRecTo    end
    signalTable.onNS_NShotStr = function(c) curNShotStr = c.content or curNShotStr end
    signalTable.onNS_Measure  = function(c) curMeasure  = c.content or curMeasure  end
    signalTable.onNS_Width    = function(c) curWidth    = c.content or curWidth    end

    signalTable.onNS_NShotOn  = function(c) setNShot = true;  refreshEnablePair(btnNShotOn,  btnNShotOff,  true)  end
    signalTable.onNS_NShotOff = function(c) setNShot = false; refreshEnablePair(btnNShotOn,  btnNShotOff,  false) end

    signalTable.onNS_DirOn    = function(c) setDirection = true;  refreshEnablePair(btnDirOn,   btnDirOff,   true)  end
    signalTable.onNS_DirOff   = function(c) setDirection = false; refreshEnablePair(btnDirOn,   btnDirOff,   false) end

    signalTable.onNS_MeasOn  = function(c)
        setMeasure = true; setAdaptiveMeasure = false; refreshMeasureState()
    end
    signalTable.onNS_MeasOff = function(c)
        setMeasure = false; refreshMeasureState()
    end
    signalTable.onNS_AdaptMeasOn  = function(c)
        setAdaptiveMeasure = true; refreshMeasureState()
    end
    signalTable.onNS_AdaptMeasOff = function(c)
        setAdaptiveMeasure = false; refreshMeasureState()
    end

    signalTable.onNS_WidthOn  = function(c)
        setWidth = true; setAdaptiveWidth = false; refreshWidthState()
    end
    signalTable.onNS_WidthOff = function(c)
        setWidth = false; refreshWidthState()
    end
    signalTable.onNS_AdaptWidthOn  = function(c)
        setAdaptiveWidth = true; refreshWidthState()
    end
    signalTable.onNS_AdaptWidthOff = function(c)
        setAdaptiveWidth = false; refreshWidthState()
    end

    signalTable.onNS_ModeUnlim  = function(c) curNShotMode = MODE_UNLIMITED; refreshModeToggle() end
    signalTable.onNS_ModeCustom = function(c) curNShotMode = MODE_CUSTOM;    refreshModeToggle() end

    signalTable.onNS_DirFwd = function(c) curDirection = 'Forward';   refreshDirButtons() end
    signalTable.onNS_DirBwd = function(c) curDirection = 'Backward';  refreshDirButtons() end
    signalTable.onNS_DirAlt = function(c) curDirection = 'Alternate'; refreshDirButtons() end

    signalTable.onNS_Apply = function(c)

        -- Must apply at least one property
        if not setNShot and not setDirection and not setMeasure and not setWidth and not setAdaptiveMeasure and not setAdaptiveWidth then
            ErrPrintf("SetNShot: Nothing to apply -- enable at least one property.")
            return
        end

        -- -- Sequence range ------------------------------------------------
        local seqFromIdx, seqToIdx
        if useSelectedSeq then
            local selSeq = SelectedSequence()
            if selSeq == nil then
                ErrPrintf("SetNShot: No sequence selected.")
                return
            end
            seqFromIdx = selSeq.index
            seqToIdx   = selSeq.index
            Printf("SetNShot: Using selected sequence -- index %d (%s)",
                seqFromIdx, tostring(selSeq.name or ""))
        else
            seqFromIdx = parsePosInt(curSeqFrom)
            if seqFromIdx == nil then
                ErrPrintf("SetNShot: Sequence From must be a positive integer (got '%s').", curSeqFrom)
                return
            end
            local seqToRaw = trim(curSeqTo)
            seqToIdx = (seqToRaw == '') and seqFromIdx or parsePosInt(seqToRaw)
            if seqToIdx == nil then
                ErrPrintf("SetNShot: Sequence To must be a positive integer or blank (got '%s').", curSeqTo)
                return
            end
            if seqToIdx < seqFromIdx then
                ErrPrintf("SetNShot: Sequence To must be >= Sequence From.")
                return
            end
        end

        -- -- Cue range -----------------------------------------------------
        local cueFrom = parseNonNegNumber(curCueFrom)
        if cueFrom == nil then
            ErrPrintf("SetNShot: Cue From must be a number >= 0 (got '%s').", curCueFrom)
            return
        end
        local cueToRaw = trim(curCueTo)
        local cueTo    = (cueToRaw == '') and math.huge or parseNonNegNumber(cueToRaw)
        if cueTo == nil or cueTo < cueFrom then
            ErrPrintf("SetNShot: Cue To invalid (got '%s').", curCueTo)
            return
        end

        -- -- Recipe range --------------------------------------------------
        local recFrom = parsePosInt(curRecFrom)
        if recFrom == nil then
            ErrPrintf("SetNShot: Recipe From must be a positive integer (got '%s').", curRecFrom)
            return
        end
        local recToRaw = trim(curRecTo)
        local recTo    = (recToRaw == '') and math.huge or parsePosInt(recToRaw)
        if recTo == nil or recTo < recFrom then
            ErrPrintf("SetNShot: Recipe To invalid (got '%s').", curRecTo)
            return
        end

        -- -- NShot value ---------------------------------------------------
        local nshotValue = nil
        if setNShot then
            if curNShotMode == MODE_UNLIMITED then
                nshotValue = NSHOT_UNLIMITED
            else
                local n = parsePosNumber(curNShotStr)
                if n == nil then
                    ErrPrintf("SetNShot: Custom # must be a positive number (got '%s').", curNShotStr)
                    return
                end
                nshotValue = tostring(n)
            end
        end

        -- -- Measure value -------------------------------------------------
        local measureValue = nil
        if setMeasure then
            local n = parsePosNumber(curMeasure)
            if n == nil then
                ErrPrintf("SetNShot: Measure must be a positive number (got '%s').", curMeasure)
                return
            end
            measureValue = tostring(n)
        end

        -- -- Width value ---------------------------------------------------
        local widthValue = nil
        if setWidth then
            local n = parseNonNegNumber(curWidth)
            if n == nil or n > 100 then
                ErrPrintf("SetNShot: Width must be a number 0-100 (got '%s').", curWidth)
                return
            end
            widthValue = tostring(n)
        end

        result = {
            seqFromIdx   = seqFromIdx,
            seqToIdx     = seqToIdx,
            cueFrom      = cueFrom,
            cueTo        = cueTo,
            recFrom      = recFrom,
            recTo        = recTo,
            nshotValue   = nshotValue,
            dirValue     = setDirection and curDirection or nil,
            measureValue        = measureValue,
            widthValue          = widthValue,
            adaptiveMeasureVal  = setAdaptiveMeasure or nil,
            adaptiveWidthVal    = setAdaptiveWidth   or nil,
        }
        overlay:ClearUIChildren()
        done = true
    end

    signalTable.onNS_Close = function(c)
        overlay:ClearUIChildren()
        done = true
    end

    repeat coroutine.yield() until done
    return result
end

-------------------------------------------------------------------------------
-- LAYER 5 -- Core processing
-------------------------------------------------------------------------------

local function applyToSequence(seqIndex, params)
    local cueFrom    = params.cueFrom
    local cueTo      = params.cueTo
    local recFrom    = params.recFrom
    local recTo      = params.recTo
    local nshotValue = params.nshotValue
    local dirValue   = params.dirValue
    local measValue         = params.measureValue
    local widthValue        = params.widthValue
    local adaptMeasVal      = params.adaptiveMeasureVal
    local adaptWidthVal     = params.adaptiveWidthVal

    local sequences = DataPool().Sequences
    if sequences == nil then return 0, 0 end

    local seq = sequences[seqIndex]
    if seq == nil then
        ErrPrintf("SetNShot: Sequence %d not found -- skipping.", seqIndex)
        return 0, 0
    end

    local seqName = (trim(seq.name or "") ~= "") and seq.name or ("#" .. seqIndex)

    local cues = seq:Children()
    if cues == nil then return 0, 0 end

    local function fmtCueNo(rawNo)
        local d = rawNo / 1000.0
        if math.floor(d) == d then
            return tostring(math.floor(d))
        else
            return string.format("%.3f", d):gsub("0+$", ""):gsub("%.$", "")
        end
    end

    -- Pass 1: collect qualifying cues
    local qualifiedCues = {}

    for i = 3, #cues do
        local cue = cues[i]
        if cue == nil then goto scanNextCue end

        local cueNoRaw = tonumber(cue.no)
        if cueNoRaw == nil then goto scanNextCue end
        local cueNoDisplay = cueNoRaw / 1000.0
        if cueNoDisplay < cueFrom or cueNoDisplay > cueTo then goto scanNextCue end

        local parts = cue:Children()
        if parts == nil then goto scanNextCue end

        for pi = 1, #parts do
            local part = parts[pi]
            if part == nil then goto scanNextPart end

            local recipes = part:Children()
            if recipes == nil then goto scanNextPart end

            local phaserCount = 0
            for ri = 1, #recipes do
                local r = recipes[ri]
                if r ~= nil and r:GetClass() == "PhaserRecipe" then
                    phaserCount = phaserCount + 1
                end
            end

            if phaserCount == 0 then goto scanNextPart end

            local actualRecTo = (recTo == math.huge) and phaserCount or math.min(recTo, phaserCount)
            if recFrom > actualRecTo then goto scanNextPart end

            qualifiedCues[#qualifiedCues + 1] = {
                cueNoStr = fmtCueNo(cueNoRaw),
                partNo   = part.index,
                rFrom    = recFrom,
                rTo      = actualRecTo,
            }

            ::scanNextPart::
        end
        ::scanNextCue::
    end

    if #qualifiedCues == 0 then return 0, 0 end

    -- Pass 2: issue commands
    local cueCount    = 0
    local updateCount = 0

    for _, entry in ipairs(qualifiedCues) do
        local cueNoStr = entry.cueNoStr
        local partNo   = entry.partNo
        local rFrom    = entry.rFrom
        local rTo      = entry.rTo

        local partAddr
        if rFrom == rTo then
            partAddr = string.format("Part %d.%d", partNo, rFrom)
        else
            partAddr = string.format("Part %d.%d Thru %d", partNo, rFrom, rTo)
        end

        local base_cmd = string.format("Set Sequence %d Cue %s %s",
            seqIndex, cueNoStr, partAddr)

        local cueUpdated = false

        local function send(prop, val)
            local cmd = string.format('%s Property "%s" %s /nc /nu', base_cmd, prop, val)
            Printf("SetNShot: %s", cmd)
            if Cmd(cmd) then
                updateCount = updateCount + (rTo - rFrom + 1)
                cueUpdated  = true
            else
                ErrPrintf("SetNShot: Failed -- %s", cmd)
            end
        end

        if nshotValue      then send("PlaybackNShot",           nshotValue)      end
        if dirValue        then send("PlaybackDirection",        dirValue)        end
        if measValue       then send("PlaybackMeasure",          measValue)       end
        if adaptMeasVal    then send("PlaybackAdaptiveMeasure",  "Yes")           end
        if widthValue      then send("PlaybackWidth",            widthValue)      end
        if adaptWidthVal   then send("PlaybackAdaptiveWidth",    "Yes")           end

        if cueUpdated then cueCount = cueCount + 1 end
    end

    return cueCount, updateCount
end

local function applyAll(params)
    local totalCues    = 0
    local totalUpdates = 0

    for seqIdx = params.seqFromIdx, params.seqToIdx do
        local c, u = applyToSequence(seqIdx, params)
        totalCues    = totalCues    + c
        totalUpdates = totalUpdates + u
    end

    return totalCues, totalUpdates
end

-------------------------------------------------------------------------------
-- LAYER 6 -- Entry point
-------------------------------------------------------------------------------

local function main()
    Printf("SetNShot v%s", PLUGIN_VERSION)
    initColors()

    local overlay = GetFocusDisplay().ScreenOverlay
    local params  = showInputUI(overlay)

    if not params then
        Printf("SetNShot: Cancelled.")
        return
    end

    local seqRange = (params.seqFromIdx == params.seqToIdx)
        and tostring(params.seqFromIdx)
        or  (tostring(params.seqFromIdx) .. " Thru " .. tostring(params.seqToIdx))
    Printf("SetNShot: Applying to Sequence %s ...", seqRange)

    local cues, updates = applyAll(params)

    if updates == 0 then
        ErrPrintf("SetNShot: No recipes were updated. Check sequence, cue, and recipe ranges.")
    else
        Printf("SetNShot: Done -- %d cue(s) across %d sequence(s) updated.",
            cues,
            params.seqToIdx - params.seqFromIdx + 1)
    end
end

return main
