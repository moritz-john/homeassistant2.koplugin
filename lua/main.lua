--[[--
Home Assistant 2 plugin for KOReader.
Sends service calls to the Home Assistant REST API using configured controls.
]]

local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local QRMessage = require("ui/widget/qrmessage")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local JSON = require("rapidjson")
local http = require("socket.http")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local Screen = Device.screen

local CONFIG_FILE = DataStorage:getSettingsDir() .. "/homeassistant2_config.lua"

-- Display a message in KOReader.
local function showMessage(text, timeout)
    UIManager:show(InfoMessage:new { text = text, timeout = timeout })
end

-- Keep http:// or https://, add http:// if missing, and remove trailing slashes.
local function normalizeUrl(url)
    url = util.trim(url or "")
    if url ~= "" and not url:match("^https?://") then
        url = "http://" .. url
    end
    return (url:gsub("/+$", ""))
end

local HA2 = WidgetContainer:extend {
    name = "homeassistant2",
    is_doc_only = false,
}

-- Load the config and register the plugin's main-menu entry.
function HA2:init()
    self:ensureConfigExists()

    local loaded, err = self:loadActions()
    if not loaded then
        logger.warn("HomeAssistant2: could not load config:", err)
        self.actions = {}
        self.config = { settings = {} }
        self:registerDispatcherActions()
    end

    self.ui.menu:registerToMainMenu(self)
end

-- Copy the bundled sample config when no user config exists yet.
function HA2:ensureConfigExists()
    if lfs.attributes(CONFIG_FILE, "mode") ~= "file" then
        local copy_err = ffiutil.copyFile(self.path .. "/homeassistant2_config.sample.lua", CONFIG_FILE)
        if copy_err then
            logger.warn("HomeAssistant2: could not copy sample config:", copy_err)
        end
    end
end

-- Load and validate the config before replacing the active settings and actions.
function HA2:loadActions()
    local ok, config = pcall(dofile, CONFIG_FILE)
    if not ok then
        return nil, tostring(config)
    elseif type(config) ~= "table" then
        return nil, "The config file must return a table."
    end

    local settings = config.settings
    if type(settings) ~= "table" then
        return nil, "The 'settings' entry must be a table."
    end
    if settings.url ~= nil and type(settings.url) ~= "string" then
        return nil, "The settings.url value must be a string."
    end
    if settings.token ~= nil and type(settings.token) ~= "string" then
        return nil, "The settings.token value must be a string."
    end

    local actions = config.user_actions
    if type(actions) ~= "table" then
        return nil, "The 'user_actions' entry must be a table."
    end
    for index, action in ipairs(actions) do
        if type(action) ~= "table" then
            return nil, string.format("user_actions entry %d must be a table.", index)
        end
        if type(action.meta) ~= "table" then
            return nil, string.format("user_actions entry %d: The 'meta' entry must be a table.", index)
        end
        if type(action.meta.label) ~= "string" or action.meta.label == "" then
            return nil, string.format("user_actions entry %d: The 'meta.label' value must be a non-empty string.", index)
        end
    end

    self.config = config
    self.actions = actions
    self:registerDispatcherActions()
    return true
end

-- Register dispatcher entries for the current actions.
function HA2:registerDispatcherActions()
    -- Remove old actions from the dispatcher.
    for _i, name in ipairs(self.registered_actions or {}) do
        Dispatcher:removeAction(name)
    end
    -- Reset the list of registered action names.
    self.registered_actions = {}

    -- Register the HA2 button dialog action.
    local button_dialog_action = "ha2_show_button_dialog"
    Dispatcher:registerAction(button_dialog_action, {
        category = "none",
        event = "ShowHA2ButtonDialog",
        title = "Home Assistant 2 actions",
        general = true,
    })
    table.insert(self.registered_actions, button_dialog_action)

    -- Register each HA2 action.
    for index, action in ipairs(self.actions) do
        local name = "ha2_action_" .. index
        Dispatcher:registerAction(name, {
            category = "none",
            event = "ActivateHA2Action",
            arg = index,
            title = action.meta.label,
            general = true,
        })
        table.insert(self.registered_actions, name)
    end
end

-- Add the plugin entry to KOReader's main menu.
function HA2:addToMainMenu(menu_items)
    menu_items.homeassistant2 = {
        text = "Home Assistant 2",
        sorting_hint = "tools",
        sub_item_table_func = function() return self:buildMenuItems() end,
    }
end

-- Build or refresh the plugin menu entries from the current settings and actions.
function HA2:buildMenuItems()
    local items = {}

    if self.config.settings.show_getting_started == true then
        table.insert(items, {
            text = "\u{EB62} Getting started (long press for QR code)",
            separator = true,
            callback = function() self:showGettingStarted() end,
            hold_callback = function() self:showRepositoryQr() end,
        })
    end

    -- Add a menu entry for each configured action.
    for _, action in ipairs(self.actions) do
        table.insert(items, {
            text = action.meta.label,
            callback = function() self:runAction(action) end,
        })
    end

    if #items == 0 then
        table.insert(items, { text = "No actions configured", enabled = false })
    else
        items[#items].separator = true
    end

    table.insert(items, {
        text = "\u{EB4F} Reload configuration",
        separator = true,
        keep_menu_open = true,
        callback = function(menu)
            local loaded, err = self:loadActions()
            if loaded then
                showMessage("Config reloaded.")
            else
                showMessage("Could not reload config:\n" .. err)
            end
            menu.item_table = self:buildMenuItems()
            menu:updateItems()
        end,
    })

    return items
end

-- Display instructions for configuring the plugin.
function HA2:showGettingStarted()
    showMessage(
        "From your computer:\n\n"
        .. "\u{EAA5} Edit 'koreader/settings/homeassistant2_config.lua'\n\n"
        .. "\u{EAA8} Configure your URL, token and actions, then reload the config.\n\n"
        .. "\u{EAAB} Set show_getting_started = false.\n\n"
        .. "\u{E885} Full documentation: https://github.com/moritz-john/homeassistant2.koplugin"
    )
end

-- Display a QR code linking to the plugin repository.
function HA2:showRepositoryQr()
    local qr_size = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.6)
    UIManager:show(QRMessage:new {
        text = "https://github.com/moritz-john/homeassistant2.koplugin",
        width = qr_size,
        height = qr_size,
    })
end

-- Show a dialog listing all available actions.
function HA2:onShowHA2ButtonDialog()
    if #self.actions == 0 then
        showMessage("No actions configured")
        return true
    end

    local dialog
    local buttons = {}
    for _, action in ipairs(self.actions) do
        table.insert(buttons, { {
            text = action.meta.label,
            align = "left",
            callback = function()
                UIManager:close(dialog)
                self:runAction(action)
            end,
        } })
    end

    dialog = ButtonDialog:new {
        title = "Home Assistant:",
        title_align = "center",
        width_factor = 0.6,
        buttons = buttons,
    }
    UIManager:show(dialog)
    return true
end

-- Run the configured action at the given position in the action list.
function HA2:onActivateHA2Action(index)
    local action = self.actions[index]
    if action then
        self:runAction(action)
    else
        -- This should not happen because only configured actions are registered.
        showMessage("No action at position " .. tostring(index) .. ".")
    end
    return true
end

-- Run an action when online and display whether it succeeded.
function HA2:runAction(action)
    if NetworkMgr:willRerunWhenOnline(function() self:runAction(action) end) then
        return
    end

    local ok, err = self:callService(action)
    if ok then
        showMessage("Executed: " .. action.meta.label, 3)
    else
        showMessage("Failed: " .. action.meta.label .. "\n\n" .. err)
    end
end

-- Validate an action's service metadata, build its payload, and send the call.
function HA2:callService(action)
    local meta = action.meta

    -- The REST API still calls the second part "service"; Home Assistant's UI calls it "action".
    local domain, service
    if type(meta.action) == "string" then
        domain, service = meta.action:match("^([%w_]+)%.([%w_]+)$")
    end
    if not domain then
        return nil, "meta.action must look like 'light.turn_on' (domain.action)."
    end

    local service_data = {}
    for key, value in pairs(action) do
        if key ~= "meta" then
            service_data[key] = value
        end
    end

    local path = string.format("/api/services/%s/%s", domain, service)
    return self:request("POST", path, service_data)
end

-- Send a Home Assistant REST request and return its result.
function HA2:request(method, path, service_data)
    local settings = self.config.settings
    local base_url = normalizeUrl(settings.url)
    local token = util.trim(settings.token or "")
    if base_url == "" or token == "" then
        return nil, "Set the Home Assistant URL and token in 'homeassistant2_config.lua'."
    end

    -- Encode empty service data as {} and fail if JSON encoding is not possible.
    local request_body = service_data and (next(service_data) == nil and "{}" or JSON.encode(service_data))
    if service_data and not request_body then
        return nil, "Could not encode service data."
    end

    local response_chunks = {}

    local headers = {
        ["Authorization"] = "Bearer " .. token,
        ["Content-Type"] = request_body and "application/json",
        ["Content-Length"] = request_body and tostring(#request_body),
    }
    local source = request_body and ltn12.source.string(request_body)

    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    -- Returns 1 and the HTTP code, or nil and an error message.
    local ok, code = http.request({
        url = base_url .. path,
        method = method,
        headers = headers,
        source = source,
        sink = socketutil.table_sink(response_chunks),
    })
    socketutil:reset_timeout()

    if not ok then
        return nil, tostring(code)
    end

    -- Return an error unless the status is 200 or 201 (success codes).
    if type(code) ~= "number" or (code ~= 200 and code ~= 201) then
        return nil, string.format("HTTP %s: %s", tostring(code), table.concat(response_chunks):sub(1, 300))
    end

    return true
end

return HA2
