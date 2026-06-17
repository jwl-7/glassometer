local KMH_TO_MPH = 0.621371

local BASE  = 175
local SIZE  = 128
local SCALE = SIZE / BASE
local ARCR  = SIZE * (158 / BASE)
local FADE  = 0.08

local RPM_MULT      = 1.14
local TOTAL_SWEEP   = 260
local ARC_START     = 140
local BOOST_MAX_BAR = 2.0
local BOOST_SWEEP   = 180
local BOOST_START = ARC_START + (TOTAL_SWEEP - BOOST_SWEEP) / 2

local _mcos   = math.cos
local _mfloor = math.floor
local _mlerp  = math.lerp
local _mmax   = math.max
local _mmin   = math.min
local _mrad   = math.rad
local _msin   = math.sin

local _rpm = 0
local _car = ac.getCar(0)

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
    elseif gear ==  0 then return 'N'
    else return tostring(gear) end
end

---@param t number
---@param alpha number? (Default: 1)
---@return rgbm
local function iridColor(t, alpha)
    alpha = alpha or 1

    local r = 0
    local g = 0
    local b = 0
    local cycle = (t * 3) % 3
    local phase = cycle % 1
    local seg = _mfloor(cycle) % 3

    if seg == 0 then
        r = _mlerp(0.2, 0.7, phase)
        g = _mlerp(0.9, 0.3, phase)
        b = 1.0
    elseif seg == 1 then
        r = _mlerp(0.7, 1.0, phase)
        g = _mlerp(0.3, 0.75, phase)
        b = _mlerp(1.0, 0.15, phase)
    else
        r = _mlerp(1.0, 0.2, phase)
        g = _mlerp(0.75, 0.9, phase)
        b = _mlerp(0.15, 1.0, phase)
    end

    return rgbm(r, g, b, alpha)
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
---@param rI number
---@param rO number
---@param startDeg number
---@param endDeg number
---@param alphaScale number
---@param segs number? (Default: 120)
local function iridArcBand(cx, cy, rI, rO, startDeg, endDeg, alphaScale, segs)
    segs = segs or 120
    local span = endDeg - startDeg

    for i = 0, segs - 1 do
        local t0 = i / segs
        local a1 = _mrad(startDeg + t0 * span)
        local a2 = _mrad(startDeg + (i + 1) / segs * span)
        local col = iridColor(t0, alphaScale)
        local p1 = vec2(cx + _mcos(a1) * rI, cy + _msin(a1) * rI)
        local p2 = vec2(cx + _mcos(a1) * rO, cy + _msin(a1) * rO)
        local p3 = vec2(cx + _mcos(a2) * rO, cy + _msin(a2) * rO)
        local p4 = vec2(cx + _mcos(a2) * rI, cy + _msin(a2) * rI)
        ui.drawQuadFilled(p1, p2, p3, p4, col)
    end
end

---@param cx number
---@param cy number
---@param r number
---@param s number
local function drawGlassDisc(cx, cy, r, s)
    ui.drawCircleFilled(vec2(cx, cy), r, rgbm(0, 0, 0, 0), 80)

    for i = 1, 8 do
        local frac = i / 8
        local alpha = _mlerp(0.0, 0.07, frac)
        ui.drawCircleFilled(vec2(cx, cy), r * frac, rgbm(0.3, 0.35, 0.6, alpha), 60)
    end

    iridArcBand(cx, cy, r - 14 * s, r - 2 * s, 0, 360, 0.18, 180)
    ui.drawCircle(vec2(cx, cy), r, rgbm(1, 1, 1, 0.30), 80, 1.5 * s)
end

---@param cx number
---@param cy number
---@param arcR number
---@param rpmFactor number
---@param s number
local function drawRpmTrack(cx, cy, arcR, rpmFactor, s)
    local rI = arcR - 12 * s
    local rO = arcR
    local bgSegs = 120

    for i = 0, bgSegs - 1 do
        local t0 = i / bgSegs
        local t1 = (i + 1) / bgSegs
        local a1 = _mrad(ARC_START + t0 * TOTAL_SWEEP)
        local a2 = _mrad(ARC_START + t1 * TOTAL_SWEEP)
        local fa = t0 < FADE and (t0 / FADE) or (t0 > (1 - FADE) and ((1 - t0) / FADE) or 1.0)
        local p1 = vec2(cx + _mcos(a1) * (rI - s), cy + _msin(a1) * (rI - s))
        local p2 = vec2(cx + _mcos(a1) * (rO + s), cy + _msin(a1) * (rO + s))
        local p3 = vec2(cx + _mcos(a2) * (rO + s), cy + _msin(a2) * (rO + s))
        local p4 = vec2(cx + _mcos(a2) * (rI - s), cy + _msin(a2) * (rI - s))
        ui.drawQuadFilled(p1, p2, p3, p4, rgbm(0.3, 0.35, 0.6, 0.08 * fa))

        local col = rgbm(1, 1, 1, 0.25 * fa)
        local pi1 = vec2(cx + _mcos(a1) * rI, cy + _msin(a1) * rI)
        local pi2 = vec2(cx + _mcos(a2) * rI, cy + _msin(a2) * rI)
        local po1 = vec2(cx + _mcos(a1) * rO, cy + _msin(a1) * rO)
        local po2 = vec2(cx + _mcos(a2) * rO, cy + _msin(a2) * rO)
        ui.drawLine(pi1, pi2, col, 1.5 * s)
        ui.drawLine(po1, po2, col, 1.5 * s)
    end

    if rpmFactor <= 0.001 then
        return
    end

    local fillSegs = _mfloor(rpmFactor * 240)

    for i = 0, fillSegs do
        local t0 = i / 240
        local a1 = _mrad(ARC_START + t0 * TOTAL_SWEEP)
        local a2 = _mrad(ARC_START + (i + 1) / 240 * TOTAL_SWEEP)
        local fa = t0 < FADE and (t0 / FADE) or 1.0
        local col = iridColor(t0, 0.9 * fa)
        local p1 = vec2(cx + _mcos(a1) * (rI - s), cy + _msin(a1) * (rI - s))
        local p2 = vec2(cx + _mcos(a1) * (rO + s), cy + _msin(a1) * (rO + s))
        local p3 = vec2(cx + _mcos(a2) * (rO + s), cy + _msin(a2) * (rO + s))
        local p4 = vec2(cx + _mcos(a2) * (rI - s), cy + _msin(a2) * (rI - s))
        ui.drawQuadFilled(p1, p2, p3, p4, col)
    end
end

---@param cx number
---@param cy number
---@param arcR number
---@param s number
local function drawTicks(cx, cy, arcR, s)
    for i = 0, 10 do
        local t = i / 10
        local a = _mrad(ARC_START + t * TOTAL_SWEEP)
        local inner = arcR - 28 * s
        local outer = arcR - 13 * s
        local p1 = vec2(cx + _mcos(a) * inner, cy + _msin(a) * inner)
        local p2 = vec2(cx + _mcos(a) * outer, cy + _msin(a) * outer)
        ui.drawLine(p1, p2, iridColor(t, 1.0), 4.0 * s)

        local labelR = arcR - 48 * s
        ui.setCursor(vec2(cx + _mcos(a) * labelR - 16 * s, cy + _msin(a) * labelR - 11 * s))
        ui.dwriteTextAligned(tostring(i), 16 * s, ui.Alignment.Center, ui.Alignment.Center, vec2(32 * s, 22 * s), false, rgbm(1, 1, 1, 0.90))
    end
end

---@param cx number
---@param cy number
---@param angleDeg number
---@param arcR number
---@param s number
local function drawNeedle(cx, cy, angleDeg, arcR, s)
    local a = _mrad(angleDeg)
    local perp = _mrad(angleDeg + 90)
    local tip = vec2(cx + _mcos(a) * (arcR - 20 * s), cy + _msin(a) * (arcR - 20 * s))
    local base = vec2(cx - _mcos(a) * 32 * s, cy - _msin(a) * 32 * s)
    local bl = vec2(base.x + _mcos(perp) * 5 * s, base.y + _msin(perp) * 5 * s)
    local br = vec2(base.x - _mcos(perp) * 5 * s, base.y - _msin(perp) * 5 * s)

    ui.drawCircleFilled(vec2(cx, cy), arcR - 18 * s, rgbm(0, 0, 0, 0), 80)

    ui.beginGradientShade()
    ui.drawTriangleFilled(bl, tip, br, rgbm(1.0, 0.1, 0.1, 1.0))
    ui.endGradientShade(tip, base, rgbm(1.0, 0.2, 0.1, 1.0), rgbm(0.7, 0.03, 0.03, 1.0))

    ui.drawCircleFilled(vec2(cx, cy), 13 * s, rgbm(0.04, 0.04, 0.14, 1.0), 24)
    ui.drawCircleFilled(vec2(cx, cy), 8 * s, rgbm(0.92, 0.92, 0.96, 1.0), 20)
    ui.drawCircle(vec2(cx, cy), 13 * s, rgbm(1, 1, 1, 0.4), 24, 1.5 * s)
end

---@param cx number
---@param cy number
---@param arcR number
---@param boost number
---@param s number
local function drawBoostArc(cx, cy, arcR, boost, s)
    local rO = arcR * 0.45
    local rI = rO - 8 * s
    local boostFactor = _mmax(0, _mmin(boost / BOOST_MAX_BAR, 1.0))
    local segs = 60

    for i = 0, segs - 1 do
        local t0 = i / segs
        local a1 = _mrad(BOOST_START + t0 * BOOST_SWEEP)
        local a2 = _mrad(BOOST_START + (i + 1) / segs * BOOST_SWEEP)
        local p1 = vec2(cx + _mcos(a1) * rI, cy + _msin(a1) * rI)
        local p2 = vec2(cx + _mcos(a1) * rO, cy + _msin(a1) * rO)
        local p3 = vec2(cx + _mcos(a2) * rO, cy + _msin(a2) * rO)
        local p4 = vec2(cx + _mcos(a2) * rI, cy + _msin(a2) * rI)
        ui.drawQuadFilled(p1, p2, p3, p4, rgbm(0.15, 0.15, 0.3, 0.4))
    end

    arcLines(cx, cy, rI, BOOST_START, BOOST_START + BOOST_SWEEP, rgbm(1, 1, 1, 0.12), 0.6 * s, 40)
    arcLines(cx, cy, rO, BOOST_START, BOOST_START + BOOST_SWEEP, rgbm(1, 1, 1, 0.12), 0.6 * s, 40)

    if boostFactor > 0.001 then
        local fillSegs = _mfloor(boostFactor * 100)

        for i = 0, fillSegs do
            local t0 = i / 100
            local a1 = _mrad(BOOST_START + t0 * BOOST_SWEEP)
            local a2 = _mrad(BOOST_START + (i + 1) / 100 * BOOST_SWEEP)
            local bFrac = _mmin(t0 / _mmax(boostFactor, 0.001), 1.0)
            local r = _mlerp(0.0, 0.0, bFrac)
            local g = _mlerp(0.55, 0.95, bFrac)
            local b = _mlerp(1.0, 1.0, bFrac)

            if boostFactor > 0.75 then
                local heat = (boostFactor - 0.75) / 0.25
                r = _mlerp(r, 1.0, heat)
                g = _mlerp(g, 0.55, heat)
                b = _mlerp(b, 0.1, heat)
            end

            local p1 = vec2(cx + _mcos(a1) * rI, cy + _msin(a1) * rI)
            local p2 = vec2(cx + _mcos(a1) * rO, cy + _msin(a1) * rO)
            local p3 = vec2(cx + _mcos(a2) * rO, cy + _msin(a2) * rO)
            local p4 = vec2(cx + _mcos(a2) * rI, cy + _msin(a2) * rI)
            ui.drawQuadFilled(p1, p2, p3, p4, rgbm(r, g, b, 0.88))
        end

        local tipA = _mrad(BOOST_START + boostFactor * BOOST_SWEEP)
        ui.drawLine(
            vec2(cx + _mcos(tipA) * rI, cy + _msin(tipA) * rI),
            vec2(cx + _mcos(tipA) * rO, cy + _msin(tipA) * rO),
            rgbm(1, 1, 1, 0.65),
            2.0 * s
        )
    end
end

---@param cx number
---@param cy number
---@param speed number
---@param s number
local function drawSpeedBox(cx, cy, speed, s)
    local bx = cx - 50 * s
    local by = cy + 72 * s
    local bw = 100 * s
    local bh = 50 * s

    ui.drawRectFilled(vec2(bx, by), vec2(bx + bw, by + bh), rgbm(0.1, 0.1, 0.25, 0.35), 8 * s, ui.CornerFlags.All)
    ui.drawRect(vec2(bx, by), vec2(bx + bw, by + bh), iridColor(0.3, 0.4), 8 * s, ui.CornerFlags.All, 1.5 * s)

    ui.setCursor(vec2(cx - 30 * s, by + 4 * s))
    ui.dwriteTextAligned(tostring(speed), 36 * s, ui.Alignment.Center, ui.Alignment.Center, vec2(60 * s, 40 * s), false, rgbm(1, 1, 1, 0.95))

    ui.setCursor(vec2(cx - 25 * s, by + bh + 4 * s))
    ui.dwriteTextAligned("MPH", 22 * s, ui.Alignment.Center, ui.Alignment.Center, vec2(50 * s, 26 * s), false, rgbm(1, 1, 1, 0.75))
end

---@param cx number
---@param cy number
---@param gear string|number
---@param s number
local function drawGearBox(cx, cy, gear, s)
    local gbx = cx - 40 * s
    local gby = cy + 14 * s
    local gbw = 80 * s
    local gbh = 52 * s

    ui.drawRectFilled(vec2(gbx, gby), vec2(gbx + gbw, gby + gbh), rgbm(0.08, 0.06, 0.02, 0.5), 10 * s, ui.CornerFlags.All)
    ui.drawRect(vec2(gbx, gby), vec2(gbx + gbw, gby + gbh), rgbm(1.0, 0.75, 0.1, 0.5), 10 * s, ui.CornerFlags.All, 1.5 * s)

    ui.setCursor(vec2(cx - 20 * s, gby + 2 * s))
    ui.dwriteTextAligned(tostring(gear), 44 * s, ui.Alignment.Center, ui.Alignment.Center, vec2(40 * s, 48 * s), false, rgbm(1.0, 0.82, 0.15, 1.0))
end

---@param dt number
---@param rpm number
local function updateRpm(dt, rpm)
    local mult = rpm > 1200 and 1.0 + (RPM_MULT - 1.0) * _mmin((rpm - 1200) / 3000, 1.0) or 1.0
    _rpm = applyLagN(_rpm, rpm * mult, 0.9, dt)
    return _mmin(_rpm / 10000, 1.05)
end

---@param dt number
function script.glass(dt)
    if not _car then return end
    ui.pushDWriteFont('Orbitron:./fonts/orbitron.ttf')
    local cx = ui.windowSize().x / 2
    local cy = ui.windowSize().y / 2
    local rpmf = updateRpm(dt, _car.rpm)
    drawGlassDisc(cx, cy, SIZE, SCALE)
    drawRpmTrack(cx, cy, ARCR, rpmf, SCALE)
    drawTicks(cx, cy, ARCR, SCALE)
    drawBoostArc(cx, cy, ARCR, _car.turboBoost, SCALE)
    drawGearBox(cx, cy, getGearName(_car.gear), SCALE)
    drawSpeedBox(cx, cy, _mfloor(_car.speedKmh * KMH_TO_MPH), SCALE)
    drawNeedle(cx, cy, ARC_START + rpmf * TOTAL_SWEEP, ARCR, SCALE)
    ui.popDWriteFont()
end
