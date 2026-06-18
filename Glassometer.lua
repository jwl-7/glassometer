local COLOR_BLUE_CORNFLOWER = rgbm(0.40, 0.50, 0.80, 0.50)
local COLOR_BLUE_DEEP       = rgbm(0.04, 0.06, 0.12, 0.50)
local COLOR_BLUE_ICE        = rgbm(0.92, 0.92, 0.96, 1.00)
local COLOR_BLUE_INDIGO     = rgbm(0.04, 0.04, 0.14, 1.00)
local COLOR_BLUE_NAVY       = rgbm(0.10, 0.10, 0.25, 0.35)
local COLOR_BLUE_SKY_BRIGHT = rgbm(0.55, 0.70, 1.00, 1.00)
local COLOR_BLUE_SKY        = rgbm(0.31, 0.63, 1.00, 0.50)
local COLOR_BLUE_SLATE      = rgbm(0.15, 0.15, 0.30, 0.40)
local COLOR_BLUE_STEEL      = rgb(0.30, 0.35, 0.60)
local COLOR_GREY            = rgbm(0.20, 0.20, 0.20, 1.00)
local COLOR_GOLD_BRIGHT     = rgbm(1.00, 0.85, 0.40, 1.00)
local COLOR_GOLD_SOFT       = rgbm(1.00, 0.85, 0.40, 0.75)
local COLOR_RED             = rgbm(1.00, 0.10, 0.10, 1.00)
local COLOR_RED_CRIMSON     = rgbm(0.12, 0.02, 0.02, 0.50)
local COLOR_RED_MAROON      = rgbm(0.70, 0.03, 0.03, 1.00)
local COLOR_RED_ORANGE      = rgbm(1.00, 0.20, 0.10, 1.00)
local COLOR_RED_SCARLET     = rgbm(1.00, 0.20, 0.20, 1.00)
local COLOR_RED_VIBRANT     = rgbm(1.00, 0.15, 0.15, 0.50)
local COLOR_VIOLET          = rgbm(0.59, 0.39, 1.00, 0.50)
local COLOR_VIOLET_SOFT     = rgbm(0.51, 0.39, 0.86, 1.00)
local COLOR_YELLOW_AMBER    = rgbm(1.00, 0.82, 0.15, 1.00)
local COLOR_YELLOW_BRONZE   = rgbm(0.08, 0.06, 0.02, 0.50)
local COLOR_YELLOW_GOLDEN   = rgbm(1.00, 0.75, 0.10, 0.50)
local COLOR_YELLOW_OFF      = rgbm(1.00, 0.86, 0.39, 1.00)

local FONT = 'Orbitron:./fonts/orbitron.ttf'

local KMH_TO_MPH = 0.621371

local RPM_MULT      = 1.14
local TOTAL_SWEEP   = 260
local ARC_START     = 140
local BOOST_MAX_BAR = 2.0
local BOOST_SWEEP   = 180
local BOOST_START   = ARC_START + (TOTAL_SWEEP - BOOST_SWEEP) / 2

local SETTINGS     = ac.storage({ scale = 1, imperial = true }, 'glass_')
local APP_MANIFEST = ac.INIConfig.load('manifest.ini', ac.INIFormat.Extended)
local APP_NAME     = APP_MANIFEST:get('ABOUT', 'NAME', '')
local WINDOW_ID    = APP_MANIFEST:get('WINDOW_0', 'ID', '')
local WINDOW_NAME  = 'IMGUI_LUA_' .. APP_NAME .. '_' .. WINDOW_ID
local WINDOW_SIZE  = vec2(300, 300)
local APP_WINDOW   = ac.accessAppWindow(WINDOW_NAME)

local BASE  = 175
local SIZE  = 128
local FADE  = 0.08

local _mcos   = math.cos
local _mfloor = math.floor
local _mlerp  = math.lerp
local _mmax   = math.max
local _mmin   = math.min
local _mrad   = math.rad
local _msin   = math.sin

local _rpm = 0
local _car = ac.getCar(0)
local _color = rgbm()
local _scale = refnumber(SETTINGS.scale)

---@param value number
---@param target number
---@param lag number
---@param dt number
---@return number
local function applyLagN(value, target, lag, dt)
    if lag <= 0 then return target end
    local mlag = _mmin(1, (1 - lag) * dt * 60)
    return value + (target - value) * mlag
end

---@param gear integer
---@return string
local function getGearName(gear)
    if gear == -1 then return 'R'
    elseif gear == 0 then return 'N'
    else return tostring(gear) end
end

---@param gear string
---@return rgbm, rgbm, rgbm
local function getGearColors(gear)
    if gear == 'R' then return COLOR_RED_CRIMSON, COLOR_RED_VIBRANT, COLOR_RED_SCARLET
    elseif gear == 'N' then return COLOR_BLUE_DEEP, COLOR_BLUE_CORNFLOWER, COLOR_BLUE_SKY_BRIGHT
    else return COLOR_YELLOW_BRONZE, COLOR_YELLOW_GOLDEN, COLOR_YELLOW_AMBER end
end

---@param t number
---@param alpha number? (Default: 1)
---@return rgbm
local function iridColor(t, alpha)
    alpha = alpha or 1
    local cycle = (t * 3) % 3
    local phase = cycle % 1
    local seg = _mfloor(cycle) % 3

    if seg == 0 then
        _color.r = _mlerp(0.2, 0.7, phase)
        _color.g = _mlerp(0.9, 0.3, phase)
        _color.b = 1.0
    elseif seg == 1 then
        _color.r = _mlerp(0.7, 1.0, phase)
        _color.g = _mlerp(0.3, 0.75, phase)
        _color.b = _mlerp(1.0, 0.15, phase)
    else
        _color.r = _mlerp(1.0, 0.2, phase)
        _color.g = _mlerp(0.75, 0.9, phase)
        _color.b = _mlerp(0.15, 1.0, phase)
    end

    _color.mult = alpha
    return _color
end

---@param cx number
---@param cy number
---@param r number
---@param startDeg number
---@param endDeg number
---@param col rgbm
---@param thickness number
---@param segs number? (Default: 80)
local function arcLines(cx, cy, r, startDeg, endDeg, col, thickness, segs)
    segs = segs or 80
    local step = (endDeg - startDeg) / segs

    for i = 0, segs - 1 do
        local a1 = _mrad(startDeg + i * step)
        local a2 = _mrad(startDeg + (i + 1) * step)
        local p1 = vec2(cx + _mcos(a1) * r, cy + _msin(a1) * r)
        local p2 = vec2(cx + _mcos(a2) * r, cy + _msin(a2) * r)
        ui.drawLine(p1, p2, col, thickness)
    end
end

---@param cx number
---@param cy number
---@param radiusInner number
---@param radiusOuter number
---@param startDeg number
---@param endDeg number
---@param alphaScale number
---@param segs number? (Default: 120)
local function iridArcBand(cx, cy, radiusInner, radiusOuter, startDeg, endDeg, alphaScale, segs)
    segs = segs or 120
    local span = endDeg - startDeg

    for i = 0, segs - 1 do
        local t0 = i / segs
        local a1 = _mrad(startDeg + t0 * span)
        local a2 = _mrad(startDeg + (i + 1) / segs * span)
        local p1 = vec2(cx + _mcos(a1) * radiusInner, cy + _msin(a1) * radiusInner)
        local p2 = vec2(cx + _mcos(a1) * radiusOuter, cy + _msin(a1) * radiusOuter)
        local p3 = vec2(cx + _mcos(a2) * radiusOuter, cy + _msin(a2) * radiusOuter)
        local p4 = vec2(cx + _mcos(a2) * radiusInner, cy + _msin(a2) * radiusInner)
        ui.drawQuadFilled(p1, p2, p3, p4, iridColor(t0, alphaScale))
    end
end

---@param cx number
---@param cy number
local function drawGlassDisc(cx, cy)
    local radius = SIZE * SETTINGS.scale
    ui.drawCircleFilled(vec2(cx, cy), radius, rgbm.colors.transparent, 80)

    for i = 1, 8 do
        local frac = i / 8
        _color:set(COLOR_BLUE_STEEL, _mlerp(0, 0.07, frac))
        ui.drawCircleFilled(vec2(cx, cy), radius * frac, _color, 60)
    end

    _color:set(rgb.colors.white, 0.3)
    iridArcBand(cx, cy, radius - (12 * SETTINGS.scale), radius - (2 * SETTINGS.scale), 0, 360, 0.18, 180)
    ui.drawCircle(vec2(cx, cy), radius, _color, 80, 1.5)
end

---@param cx number
---@param cy number
---@param rpmFactor number
local function drawRpmTrack(cx, cy, rpmFactor)
    local scale = (SIZE / BASE) * SETTINGS.scale
    local radius = SIZE * (158 / BASE) * SETTINGS.scale
    local rI = radius - 12 * scale
    local rO = radius

    for i = 0, 119 do
        local t0 = i / 120
        local a1 = _mrad(ARC_START + t0 * TOTAL_SWEEP)
        local a2 = _mrad(ARC_START + (i + 1) / 120 * TOTAL_SWEEP)
        local fa = t0 < FADE and (t0 / FADE) or (t0 > (1 - FADE) and ((1 - t0) / FADE) or 1.0)
        local p1 = vec2(cx + _mcos(a1) * (rI - scale), cy + _msin(a1) * (rI - scale))
        local p2 = vec2(cx + _mcos(a1) * (rO + scale), cy + _msin(a1) * (rO + scale))
        local p3 = vec2(cx + _mcos(a2) * (rO + scale), cy + _msin(a2) * (rO + scale))
        local p4 = vec2(cx + _mcos(a2) * (rI - scale), cy + _msin(a2) * (rI - scale))
        _color:set(COLOR_BLUE_STEEL, 0.08 * fa)
        ui.drawQuadFilled(p1, p2, p3, p4, _color)

        local pi1 = vec2(cx + _mcos(a1) * rI, cy + _msin(a1) * rI)
        local pi2 = vec2(cx + _mcos(a2) * rI, cy + _msin(a2) * rI)
        local po1 = vec2(cx + _mcos(a1) * rO, cy + _msin(a1) * rO)
        local po2 = vec2(cx + _mcos(a2) * rO, cy + _msin(a2) * rO)
        _color:set(rgb.colors.white, 0.25 * fa)
        ui.drawLine(pi1, pi2, _color, 1.5 * scale)
        ui.drawLine(po1, po2, _color, 1.5 * scale)
    end

    if rpmFactor <= 0.001 then return end

    local fillSegs = _mfloor(rpmFactor * 240)
    for i = 0, fillSegs do
        local t0 = i / 240
        local a1 = _mrad(ARC_START + t0 * TOTAL_SWEEP)
        local a2 = _mrad(ARC_START + (i + 1) / 240 * TOTAL_SWEEP)
        local fa = t0 < FADE and (t0 / FADE) or 1.0
        local p1 = vec2(cx + _mcos(a1) * (rI - scale), cy + _msin(a1) * (rI - scale))
        local p2 = vec2(cx + _mcos(a1) * (rO + scale), cy + _msin(a1) * (rO + scale))
        local p3 = vec2(cx + _mcos(a2) * (rO + scale), cy + _msin(a2) * (rO + scale))
        local p4 = vec2(cx + _mcos(a2) * (rI - scale), cy + _msin(a2) * (rI - scale))
        ui.drawQuadFilled(p1, p2, p3, p4, iridColor(t0, 0.9 * fa))
    end
end

---@param cx number
---@param cy number
local function drawTicks(cx, cy)
    local scale = (SIZE / BASE) * SETTINGS.scale
    local radius = SIZE * (158 / BASE) * SETTINGS.scale

    for i = 0, 10 do
        local t = i / 10
        local a = _mrad(ARC_START + t * TOTAL_SWEEP)
        local p1 = vec2(cx + _mcos(a) * (radius - 28 * scale), cy + _msin(a) * (radius - 28 * scale))
        local p2 = vec2(cx + _mcos(a) * (radius - 13 * scale), cy + _msin(a) * (radius - 13 * scale))
        ui.drawLine(p1, p2, iridColor(t, 1.0), 4.0 * scale)

        local labelR = radius - 48 * scale
        _color:set(rgb.colors.white, 0.9)
        ui.setCursor(vec2(cx + _mcos(a) * labelR - 16 * scale, cy + _msin(a) * labelR - 11 * scale))
        ui.dwriteTextAligned(tostring(i), 16 * scale, ui.Alignment.Center, ui.Alignment.Center, vec2(32 * scale, 22 * scale), false, _color)
    end
end

---@param cx number
---@param cy number
---@param angleDeg number
local function drawNeedle(cx, cy, angleDeg)
    local scale = (SIZE / BASE) * SETTINGS.scale
    local radius = SIZE * (158 / BASE) * SETTINGS.scale

    local a    = _mrad(angleDeg)
    local perp = _mrad(angleDeg + 90)
    local tip  = vec2(cx + _mcos(a) * (radius - 20 * scale), cy + _msin(a) * (radius - 20 * scale))
    local base = vec2(cx - _mcos(a) * 32 * scale,          cy - _msin(a) * 32 * scale)
    local bl   = vec2(base.x + _mcos(perp) * 5 * scale,    base.y + _msin(perp) * 5 * scale)
    local br   = vec2(base.x - _mcos(perp) * 5 * scale,    base.y - _msin(perp) * 5 * scale)

    _color:set(rgb.colors.white, 0.4)
    ui.drawCircleFilled(vec2(cx, cy), radius - 18 * scale, rgbm.colors.transparent, 80)
    ui.beginGradientShade()
    ui.drawTriangleFilled(bl, tip, br, COLOR_RED)
    ui.endGradientShade(tip, base, COLOR_RED_ORANGE, COLOR_RED_MAROON)
    ui.drawCircleFilled(vec2(cx, cy), 13 * scale, COLOR_BLUE_INDIGO, 24)
    ui.drawCircleFilled(vec2(cx, cy), 8 * scale,  COLOR_BLUE_ICE, 20)
    ui.drawCircle(vec2(cx, cy), 13 * scale, _color, 24, 1.5 * scale)
end

---@param cx number
---@param cy number
---@param boost number
local function drawBoostArc(cx, cy, boost)
    local scale = (SIZE / BASE) * SETTINGS.scale
    local radius = SIZE * (158 / BASE) * SETTINGS.scale

    local radiusOuter = radius * 0.45
    local radiusInner = radiusOuter - 8 * scale
    local boostFactor = _mmax(0, _mmin(boost / BOOST_MAX_BAR, 1.0))
    local segs = 60

    for i = 0, segs - 1 do
        local t0 = i / segs
        local a1 = _mrad(BOOST_START + t0 * BOOST_SWEEP)
        local a2 = _mrad(BOOST_START + (i + 1) / segs * BOOST_SWEEP)
        local p1 = vec2(cx + _mcos(a1) * radiusInner, cy + _msin(a1) * radiusInner)
        local p2 = vec2(cx + _mcos(a1) * radiusOuter, cy + _msin(a1) * radiusOuter)
        local p3 = vec2(cx + _mcos(a2) * radiusOuter, cy + _msin(a2) * radiusOuter)
        local p4 = vec2(cx + _mcos(a2) * radiusInner, cy + _msin(a2) * radiusInner)
        ui.drawQuadFilled(p1, p2, p3, p4, COLOR_BLUE_SLATE)
    end

    _color:set(rgb.colors.white, 0.12)
    arcLines(cx, cy, radiusInner, BOOST_START, BOOST_START + BOOST_SWEEP, _color, 0.6 * scale, 40)
    arcLines(cx, cy, radiusOuter, BOOST_START, BOOST_START + BOOST_SWEEP, _color, 0.6 * scale, 40)

    if boostFactor > 1e-3 then
        local fillSegs = _mfloor(boostFactor * 100)

        for i = 0, fillSegs do
            local t0    = i / 100
            local a1    = _mrad(BOOST_START + t0 * BOOST_SWEEP)
            local a2    = _mrad(BOOST_START + (i + 1) / 100 * BOOST_SWEEP)
            local bFrac = _mmin(t0 / _mmax(boostFactor, 0.001), 1.0)

            if boostFactor > 0.75 then
                local heat = (boostFactor - 0.75) / 0.25
                _color.r = _mlerp(0, 1, heat)
                _color.g = _mlerp(0.55, 0.95, heat)
                _color.b = _mlerp(1, 0, heat)
            else
                _color.r = 0
                _color.g = _mlerp(0.55, 0.95, bFrac)
                _color.b = 1
            end
            _color.mult = 0.88

            local p1 = vec2(cx + _mcos(a1) * radiusInner, cy + _msin(a1) * radiusInner)
            local p2 = vec2(cx + _mcos(a1) * radiusOuter, cy + _msin(a1) * radiusOuter)
            local p3 = vec2(cx + _mcos(a2) * radiusOuter, cy + _msin(a2) * radiusOuter)
            local p4 = vec2(cx + _mcos(a2) * radiusInner, cy + _msin(a2) * radiusInner)
            ui.drawQuadFilled(p1, p2, p3, p4, _color)
        end

        local tipA = _mrad(BOOST_START + boostFactor * BOOST_SWEEP)
        _color:set(rgb.colors.white, 0.65)
        ui.drawLine(
            vec2(cx + _mcos(tipA) * radiusInner, cy + _msin(tipA) * radiusInner),
            vec2(cx + _mcos(tipA) * radiusOuter, cy + _msin(tipA) * radiusOuter),
            _color, 2.0 * scale
        )
    end
end

---@param cx number
---@param cy number
---@param speed number
local function drawSpeedBox(cx, cy, speed)
    local scale = (SIZE / BASE) * SETTINGS.scale
    local units = SETTINGS.imperial and 'MPH' or 'KMH'
    local unitsSize = ui.measureDWriteText(units, 22 * scale)

    local bx = cx - 50 * scale
    local by = cy + 78 * scale
    local bw = 100 * scale
    local bh = 50 * scale

    local p1 = vec2(bx, by)
    local p2 = vec2(bx + bw, by + bh)
    local boxSize = p2 - p1

    ui.drawRectFilled(p1, p2, COLOR_BLUE_NAVY, 8 * scale, ui.CornerFlags.All)
    ui.drawRect(p1, p2, iridColor(0.3, 0.4), 8 * scale, ui.CornerFlags.All, 1.5 * scale)

    ui.setCursor(p1)
    ui.offsetCursorY(-2 * scale)
    ui.dwriteTextAligned(tostring(speed), 36 * scale, ui.Alignment.Center, ui.Alignment.Center, boxSize, false, iridColor(_mmin(speed / 200, 1.0), 0.95))

    _color:set(rgb.colors.white, 0.75)
    ui.setCursor(p1)
    ui.offsetCursorY(unitsSize.y + (8 * scale))
    ui.dwriteTextAligned(units, 22 * scale, ui.Alignment.Center, ui.Alignment.Center, boxSize, false, _color)
end

---@param cx number
---@param cy number
---@param gear string
local function drawGearBox(cx, cy, gear)
    local scale = (SIZE / BASE) * SETTINGS.scale

    local bx = cx - 40 * scale
    local by = cy + 18 * scale
    local bw = 80 * scale
    local bh = 52 * scale

    local bgColor, borderColor, textColor = getGearColors(gear)
    local p1 = vec2(bx, by)
    local p2 = vec2(bx + bw, by + bh)
    local boxSize = p2 - p1

    ui.drawRectFilled(p1, p2, bgColor, 10 * scale, ui.CornerFlags.All)
    ui.drawRect(p1, p2, borderColor, 10 * scale, ui.CornerFlags.All, 1.5 * scale)

    ui.setCursor(p1)
    ui.offsetCursorY(-2 * scale)
    ui.dwriteTextAligned(gear, 44 * scale, ui.Alignment.Center, ui.Alignment.Center, boxSize, false, textColor)
end

---@param dt number
---@param rpm number
---@return number
local function updateRpm(dt, rpm)
    local mult = rpm > 1200 and 1.0 + (RPM_MULT - 1.0) * _mmin((rpm - 1200) / 3000, 1.0) or 1.0
    _rpm = applyLagN(_rpm, rpm * mult, 0.9, dt)
    return _mmin(_rpm / 10000, 1.05)
end

local function handleWindowPin()
    if APP_WINDOW and ui.windowHovered() and ui.mouseClicked(ui.MouseButton.Right) then
        local pinned = APP_WINDOW:pinned()
        APP_WINDOW:setPinned(not pinned)
    end
end

function script.settings()
    ui.pushDWriteFont(FONT)
    ui.pushStyleColor(ui.StyleColor.Button, COLOR_GREY)
    ui.pushStyleColor(ui.StyleColor.ButtonHovered, COLOR_BLUE_SKY)
    ui.pushStyleColor(ui.StyleColor.ButtonActive, COLOR_VIOLET_SOFT)
    ui.pushStyleColor(ui.StyleColor.SliderGrab, COLOR_GOLD_SOFT)
    ui.pushStyleColor(ui.StyleColor.SliderGrabActive, COLOR_GOLD_BRIGHT)
    ui.pushStyleColor(ui.StyleColor.FrameBg, COLOR_GREY)
    ui.pushStyleColor(ui.StyleColor.FrameBgHovered, COLOR_BLUE_SKY)
    ui.pushStyleColor(ui.StyleColor.FrameBgActive, COLOR_VIOLET)

    ui.text('['); ui.sameLine(0, 0)
    ui.textColored('RIGHT', COLOR_YELLOW_OFF); ui.sameLine(0, 0)
    ui.text('-'); ui.sameLine(0, 0)
    ui.textColored('CLICK', COLOR_YELLOW_OFF); ui.sameLine(0, 0)
    ui.text('] on tacometer to '); ui.sameLine(0, 0)
    ui.textColored('pin ', COLOR_YELLOW_OFF); ui.sameLine(0, 0)
    ui.text('it!')

    local label = SETTINGS.imperial and 'Speed Units: MPH' or 'Speed Units: KMH'
    if ui.button(label .. '##units', vec2(156, 22)) then
        SETTINGS.imperial = not SETTINGS.imperial
    end

    ui.setNextItemWidth(156)
    if ui.slider('##scale', _scale, 0.1, 5, 'Scale: %.1f') then
        SETTINGS.scale = _scale.value
        if APP_WINDOW then
            APP_WINDOW:resize(WINDOW_SIZE:clone():scale(SETTINGS.scale))
        end
    end
    if ui.itemClicked(ui.MouseButton.Right) then
        _scale:set(1)
        SETTINGS.scale = _scale.value
        if APP_WINDOW then
            APP_WINDOW:resize(WINDOW_SIZE:clone():scale(SETTINGS.scale))
        end
    end

    ui.popDWriteFont()
end

---@param dt number
function script.glass(dt)
    if not _car then return end
    ui.childWindow('##glass', ui.availableSpace(), ui.WindowFlags.None, function()
        ui.pushDWriteFont(FONT)
        local cx    = ui.windowSize().x / 2
        local cy    = ui.windowSize().y / 2
        local rpmf  = updateRpm(dt, _car.rpm)
        local speed = SETTINGS.imperial and _mfloor(_car.speedKmh * KMH_TO_MPH) or _mfloor(_car.speedKmh)
        local angle = ARC_START + rpmf * TOTAL_SWEEP
        drawGlassDisc(cx, cy)
        drawRpmTrack(cx, cy, rpmf)
        drawTicks(cx, cy)
        drawBoostArc(cx, cy, _car.turboBoost)
        drawGearBox(cx, cy, getGearName(_car.gear))
        drawSpeedBox(cx, cy, speed)
        drawNeedle(cx, cy, angle)
        ui.popDWriteFont()
        handleWindowPin()
    end)
end
