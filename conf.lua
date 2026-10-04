--- LÖVE configuration -------------------------------------------------------
-- This file is loaded by the engine *before* any other Lua code. It sets up
-- global parameters for window, modules, and other runtime options.
-- Style: snake_case, single spaces around '='.

function love.conf(t)
    -- Identity & version
    t.identity = "jellotris"            -- Save directory for app data
    t.version = "11.5"                  -- LÖVE version this game was developed with
    t.console = false                   -- Keep the Windows release free of a console window

    -- Window settings
    t.window.title = "Jellotris — a soft-body arcade"
    t.window.icon = "assets/icon.png"
    t.window.width = 1080
    t.window.height = 820
    t.window.resizable = true
    t.window.minwidth = 720
    t.window.minheight = 560

    t.window.vsync = 1                  -- 0 = off, -1 = adaptive, 1 = on
    t.window.msaa = 0                   -- Anti-aliasing (0 = disabled)

    -- Modules: disable unused ones to save memory/CPU
    t.modules.joystick = false
    t.modules.physics = true
    t.modules.video = false
end
