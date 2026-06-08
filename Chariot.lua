local nfs = require("nativefs")
local lovely = require("lovely")

chariot = {
  PATH = "",
  config = {},
  ui = {
    opts = {},
  },
}

local mod_dir = lovely.mod_dir -- Cache the base directory
local found = false
local search_str = "chariot" -- or "saturn-dev" depending on the environment

for _, item in ipairs(nfs.getDirectoryItems(mod_dir)) do
  local itemPath = mod_dir .. "/" .. item
  -- Check if the item is a directory and contains the search string
  if
    nfs.getInfo(itemPath, "directory") and string.lower(item):find(search_str)
  then
    chariot.PATH = itemPath
    found = true
    break
  end
end

-- Raise an error if the directory wasn't found
if not found then
  error("ERROR: Unable to locate Chariot directory.")
end

-- Function to get default configurations
function chariot.getDefaults()
  -- Path to the default configuration file
  local defaults_path = chariot.PATH .. "/defaults.lua"
  
  -- Check if the default configuration file exists
  if not nfs.getInfo(defaults_path) then
    error("Unable to fetch default configs.")
  else
    -- Load the default configuration file
    local defaults_loader = loadfile(defaults_path)

    -- If the file is loaded successfully, execute it
    if defaults_loader then
      chariot.config = defaults_loader() or nil

      -- Raise an error if the default configuration could not be read
      if not chariot.config then
        error("Unable to read default config.")
      end
    end
  end
end

function chariot.initialize()
  chariot.getDefaults()
  -- UI
  assert(load(nfs.read(chariot.PATH .. "/UI/definitions.lua")))()
  assert(load(nfs.read(chariot.PATH .. "/UI/functions.lua")))()
end

chariot.cancel_reroll = nil

local key_press_update_ref = Controller.key_press_update
function Controller:key_press_update(key, dt)
    key_press_update_ref(self, key, dt)  
    if love.keyboard.isDown("lctrl") then
        if key == "q" then
            chariot.reroll()
        end
		if key == "w" then
			chariot.cancel_reroll = true
		end
    end
end

chariot.reroll = function()
    if chariot.card_in_shop() or chariot.cancel_reroll or G.GAME.dollars - G.GAME.current_round.reroll_cost < 0 then
		chariot.cancel_reroll = nil
        return
    end
	
    G.FUNCS.reroll_shop()
    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        delay = 1,
        func = function()
            chariot.reroll()
            return true
        end
    }))
end

chariot.card_in_shop = function()
    if G.STATE ~= G.STATES.SHOP or not G.shop_jokers or not G.shop_jokers.cards then return end
	for _,v in ipairs(G.shop_jokers.cards) do
		if chariot.config.death and v.config.center_key == "c_death" then return true end
		if chariot.config.fool and v.config.center_key == "c_fool" then return true end
		if chariot.config.judgement and v.config.center_key == "c_judgement" then return true end
		if chariot.config.turtle_bean and v.config.center_key == "j_turtle_bean" then return true end
		if chariot.config.diet_cola and v.config.center_key == "j_diet_cola" then return true end
		if chariot.config.brainstorm and v.config.center_key == "j_brainstorm" then return true end
		if chariot.config.blueprint and v.config.center_key == "j_blueprint" then return true end
		if chariot.config.chaos_the_clown and v.config.center_key == "j_chaos" then return true end
		if chariot.config.negative and v.edition and v.edition.type == "negative" then return true end
	end
end

local start_up_ref = Game.start_up
function Game:start_up()
  start_up_ref(self)
  chariot.initialize()
end