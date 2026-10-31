"""Small Lua 5.1 simulation for the native color settings."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "LH_Tweaks" / ".test-runtime"))
from lupa.lua51 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
local swatches, sliders, settings = {}, {}, {}
local values = {
    textR = 0.2, textG = 0.3, textB = 0.4, textAlpha = 0.7,
    shadowR = 0, shadowG = 0, shadowB = 0, shadowAlpha = 1,
    backgroundR = 0, backgroundG = 0, backgroundB = 0, backgroundAlpha = 0.8,
    barR = 0.3, barG = 0.55, barB = 0.8, barAlpha = 0.9,
    borderR = 0.65, borderG = 0.59, borderB = 0.45, borderAlpha = 1,
}
LH_TinyDPS = {
    Get = function(_, key) return values[key] end,
    GetDefault = function(_, key) return values[key] end,
    GetDefaultWidth = function() return 190 end,
    GetFontNames = function() return {{"Default"}} end,
    GetOutlineNames = function() return {"None"} end,
    SetColor = function(_, prefix, r, g, b)
        values[prefix .. "R"], values[prefix .. "G"], values[prefix .. "B"] = r, g, b
    end,
}
LH_Tweaks = { RegisterModule = function(_, _, _, build) Build = build end }
EventRegistry = { RegisterCallback = function() end }
CreateSettingsListSectionHeaderInitializer = function(title) return title end
CreateSettingsButtonInitializer = function() return {} end
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
CreateColor = function(r, g, b, a)
    return { GenerateHexColor = function()
        return string.format("%02x%02x%02x%02x", math.floor(a * 255 + .5),
            math.floor(r * 255 + .5), math.floor(g * 255 + .5), math.floor(b * 255 + .5))
    end }
end
CreateColorFromHexString = function(hex)
    return { GetRGB = function()
        return tonumber(hex:sub(3, 4), 16) / 255,
            tonumber(hex:sub(5, 6), 16) / 255,
            tonumber(hex:sub(7, 8), 16) / 255
    end }
end
Settings = {
    RegisterProxySetting = function(_, name, _, label, default, get, set)
        local setting = { name = name, label = label, default = default, get = get, set = set }
        settings[name] = setting
        return setting
    end,
    CreateColorSwatch = function(_, setting) swatches[#swatches + 1] = setting end,
    CreateSliderOptions = function() return { SetLabelFormatter = function() end } end,
    CreateSlider = function(_, setting) sliders[#sliders + 1] = setting end,
    CreateCheckbox = function() end,
    CreateControlTextContainer = function()
        return { Add = function() end, GetData = function() return {} end }
    end,
    CreateDropdown = function() end,
    NotifyUpdate = function() end,
}
Test = { swatches = swatches, sliders = sliders, settings = settings, values = values }
''')
lua.execute('assert(loadfile("Settings.lua"))("LH_TinyDPS")')
lua.execute(r'''
Build({}, { AddInitializer = function() end })
assert(#Test.swatches == 5)
local expected = { text = true, shadow = true, background = true, bar = true, border = true }
for _, setting in ipairs(Test.swatches) do
    local prefix = setting.name:match("^LH_TinyDPS_(.+)Color$")
    assert(expected[prefix], setting.name)
    expected[prefix] = nil
    assert(setting.get() == setting.default)
end
assert(next(expected) == nil)
local alphaCount = 0
for _, setting in ipairs(Test.sliders) do
    local key = setting.name:match("^LH_TinyDPS_(.+)$")
    assert(not key:match("[RGB]$"), key)
    if key:match("Alpha$") then alphaCount = alphaCount + 1 end
end
assert(alphaCount == 5)
local text = Test.settings.LH_TinyDPS_textColor
text.set("ff804020")
assert(math.abs(Test.values.textR - 128 / 255) < 1e-9)
assert(math.abs(Test.values.textG - 64 / 255) < 1e-9)
assert(math.abs(Test.values.textB - 32 / 255) < 1e-9)
assert(Test.values.textAlpha == 0.7)
''')
print("LH_TinyDPS color settings: 5 swatches, RGB conversion and opacity preservation passed")
