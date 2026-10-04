-- Tiny synthesized instruments. No sound files or third-party dependencies.
local Audio = {}
Audio.__index = Audio

local function synthesize(duration, frequency, slide, noise, volume)
    local rate = 22050
    local data = love.sound.newSoundData(math.floor(duration * rate), rate, 16, 1)
    local phase = 0
    local random = love.math.newRandomGenerator(42)
    for i = 0, data:getSampleCount() - 1 do
        local t = i / rate
        local envelope = math.min(1, t * 180) * math.exp(-t / duration * 5)
        phase = phase + frequency * math.exp(slide * t) / rate * math.pi * 2
        local tone = math.sin(phase) + 0.22 * math.sin(phase * 2)
        local sample = tone * (1 - noise) + (random:random() * 2 - 1) * noise
        data:setSample(i, math.max(-1, math.min(1, sample * envelope * volume)))
    end
    return love.audio.newSource(data, "static")
end

function Audio.new()
    local self = setmetatable({ muted = false, sounds = {}, voices = {} }, Audio)
    -- A machine without an audio device can still play the game.
    local ok, result = pcall(function()
        return {
            rotate = synthesize(0.12, 410, 5, 0.02, 0.15),
            hold = synthesize(0.21, 270, 5, 0.03, 0.18),
            drop = synthesize(0.24, 160, -9, 0.22, 0.25),
            land = synthesize(0.26, 135, -6, 0.08, 0.25),
            stone = synthesize(0.22, 72, -10, 0.48, 0.32),
            clear = synthesize(0.58, 520, 2, 0.02, 0.23),
            over = synthesize(0.8, 190, -2, 0.04, 0.2),
            start = synthesize(0.4, 330, 3, 0.01, 0.19),
        }
    end)
    if ok then self.sounds = result end
    return self
end

function Audio:play(name, pitch)
    if self.muted or not self.sounds[name] then return end
    for i = #self.voices, 1, -1 do
        if not self.voices[i]:isPlaying() then
            self.voices[i]:release()
            table.remove(self.voices, i)
        end
    end
    if #self.voices >= 16 then return end
    local voice = self.sounds[name]:clone()
    voice:setPitch(pitch or 1)
    voice:play()
    self.voices[#self.voices + 1] = voice
end

function Audio:toggle()
    self.muted = not self.muted
    if self.muted then
        for _, voice in ipairs(self.voices) do voice:stop() end
    end
end

return Audio
