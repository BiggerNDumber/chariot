local lovely = require("lovely")

chariot = {}

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

chariot.reroll = function(key)

    if chariot.card_in_shop(key) or chariot.cancel_reroll then
		chariot.cancel_reroll = nil
        return
    end
	
    G.FUNCS.reroll_shop()
    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        delay = 1,
        func = function()
            chariot.reroll(key)
            return true
        end
    }))
end

chariot.card_in_shop = function(key)
    if G.STATE ~= G.STATES.SHOP or not G.shop_jokers or not G.shop_jokers.cards then return end
    for _,v in ipairs(G.shop_jokers.cards) do
        if v.config.center_key == "j_diet_cola" or v.config.center_key == "j_brainstorm" or v.config.center_key == "j_blueprint" then 
			return true
		end
		if v.edition and v.edition.type == "negative" then
			return true
		end
    end
end