-- src/systems/audio.lua
-- Procedural 8-bit audio: BGM loop + dialogue blip (Katana ZERO / Celeste inspired)

local Audio = {}
Audio.__index = Audio

local SAMPLE_RATE = 44100
local BITS = 16
local CHANNELS = 1  -- mono

-- Convert Hz to angular increment per sample
local function hzToInc(freq)
    return 2 * math.pi * freq / SAMPLE_RATE
end

-- Square wave (for blip only)
local function square(phase)
    return math.sin(phase) >= 0 and 1 or -1
end

-- Sine wave (peaceful, pure tone)
local function sine(phase)
    return math.sin(phase)
end

-- Soft clip
local function softClip(x)
    if x > 1 then return 1 end
    if x < -1 then return -1 end
    return x
end

function Audio:init()
    self.blip = self:generateBlip()
    self.bgmData = self:generateBGM()
    self.bgmSource = nil
end

--- Generate dialogue advance blip (Celeste-style: short, punchy, bright)
function Audio:generateBlip()
    local duration = 0.055  -- seconds
    local freq = 980
    local samples = math.floor(duration * SAMPLE_RATE * CHANNELS)
    local data = love.sound.newSoundData(samples, SAMPLE_RATE, BITS, CHANNELS)

    local inc = hzToInc(freq)
    local phase = 0

    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        -- Exponential decay envelope
        local env = math.exp(-t * 35)
        local s = square(phase) * env * 0.35
        phase = phase + inc
        data:setSample(i, softClip(s))
    end

    return data
end

--- Peaceful, serene BGM: sine waves, slow tempo, sparse melody (scenic / contemplative)
function Audio:generateBGM()
    local BPM = 58
    local BEAT = 60 / BPM
    local BAR = BEAT * 4
    local duration = BAR * 8  -- 8 bars, slow drift
    local samples = math.floor(duration * SAMPLE_RATE * CHANNELS)
    local data = love.sound.newSoundData(samples, SAMPLE_RATE, BITS, CHANNELS)

    -- Soft bass: Am – F – C – G (one note per bar), sine
    local bassFreqs = { 110, 87.31, 65.41, 98 }
    -- Sparse, held melody: gentle bells, lots of space (freq, start beat, duration)
    local melody = {
        { 261.63, 0, 2.5 },   { 220, 3, 2 },       -- C4, A3
        { 196, 6, 2.5 },      { 174.61, 9, 2.5 },  -- G3, F3
        { 220, 14, 2 },       { 261.63, 17, 2.5 }, -- A3, C4
        { 220, 22, 3 },       { 196, 26, 2.5 },    -- A3, G3
    }

    local bassPhase = 0
    local prevBar = -1

    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        local beat = t / BEAT
        local bar = math.floor(beat / 4) % 4

        if bar ~= prevBar then
            bassPhase = 0
            prevBar = bar
        end
        local bassF = bassFreqs[bar + 1]
        local bassInc = hzToInc(bassF)
        local bass = sine(bassPhase) * 0.09
        bassPhase = bassPhase + bassInc

        local mel = 0
        for _, m in ipairs(melody) do
            local startBeat = m[2]
            local durBeat = m[3]
            if beat >= startBeat and beat < startBeat + durBeat then
                local noteT = t - startBeat * BEAT
                local noteDur = durBeat * BEAT
                local attack = 0.15
                local ramp = (noteT < attack) and (noteT / attack) or 1
                local release = (1 - math.min(1, noteT / (noteDur * 0.6)))
                local env = 0.04 * ramp * release
                local phase = 2 * math.pi * m[1] * noteT
                mel = sine(phase) * env
                break
            end
        end

        local mix = softClip(bass + mel)
        data:setSample(i, mix)
    end

    return data
end

function Audio:playBlip()
    local src = love.audio.newSource(self.blip, "static")
    src:setVolume(0.7)
    src:play()
end

function Audio:playBGM()
    if self.bgmSource and self.bgmSource:isPlaying() then return end
    self.bgmSource = love.audio.newSource(self.bgmData, "static")
    self.bgmSource:setLooping(true)
    self.bgmSource:setVolume(0.35)
    self.bgmSource:play()
end

function Audio:stopBGM()
    if self.bgmSource then
        self.bgmSource:stop()
        self.bgmSource = nil
    end
end

return Audio
