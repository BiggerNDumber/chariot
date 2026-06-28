local nfs = require("nativefs")
local lovely = require("lovely")

chariot = {
    PATH = "",
    config = {},
    ui = {
        opts = {},
    },
    polychrome_blocked = false,
    currently_selling = false,
}

local mod_dir = lovely.mod_dir -- Cache the base directory
local found = false
local search_str = "chariot"   -- or "saturn-dev" depending on the environment

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
chariot.has_sold = false

local key_press_update_ref = Controller.key_press_update
function Controller:key_press_update(key, dt)
    key_press_update_ref(self, key, dt)
    if love.keyboard.isDown("lctrl") then
        if key == "q" then
            if chariot.config.automatic then
                chariot.update_polychrome()
                chariot.reroll_automatic()
            else
                chariot.update_polychrome()
                chariot.reroll()
            end
        end
        if key == "w" then
            chariot.cancel_reroll = true
        end
        if key == "e" then
            for _, v in ipairs(G.shop_jokers.cards) do
                print(v.config.center_key)
            end
        end
    end
end

chariot.update_polychrome = function()
    for _, current_joker in ipairs(G.jokers.cards) do
        if current_joker.edition and current_joker.edition.type == "polychrome" then
            chariot.polychrome_blocked = true
        end
    end
end

chariot.attempt_sell_blueprints = function()
    if G.jokers.cards[#G.jokers.cards].config.center_key ~= "j_diet_cola" and G.jokers.cards[#G.jokers.cards].config.center_key ~= "j_brainstorm" then return end
    if G.jokers.cards[#G.jokers.cards-1].config.center_key == "j_blueprint" then
        if G.jokers.cards[#G.jokers.cards-1].edition and G.jokers.cards[#G.jokers.cards-1].edition.type == "negative" then
            return
        end
        if G.jokers.cards[#G.jokers.cards-1].edition and G.jokers.cards[#G.jokers.cards-1].edition.type == "polychrome" then
            chariot.polychrome_blocked = false
        end
        chariot.execute(G.jokers.cards[#G.jokers.cards-1], true, false, false)
        return true
    end
    return false
end

-- TODO: Mark out the indexes of the negatives, only iterate over the non-negatives
chariot.sell_jokers = function()
    chariot.currently_selling = true
    if chariot.attempt_sell_blueprints() then return true end
    for _, current_joker in ipairs(G.jokers.cards) do
        if not current_joker.edition or current_joker.edition.type ~= "negative" then
            if current_joker.config.center_key ~= "j_blueprint" then
                if current_joker.config.center_key ~= "j_chaos" or G.GAME.current_round.reroll_cost > 0 then
                    if current_joker.edition and current_joker.edition.type == "polychrome" then
                        chariot.polychrome_blocked = false
                    end
                    chariot.execute(current_joker, true, false, false)
                    return true
                end
            end
        end
    end
    chariot.currently_selling = false
    return false
end

chariot.jokers_full = function()
    local total_non_negatives = 0
    for _, current_joker in ipairs(G.jokers.cards) do
        if not current_joker.edition or current_joker.edition.type ~= "negative" then
            total_non_negatives = total_non_negatives + 1
        end
    end
    return total_non_negatives > 5
end

chariot.reset_reroll = function()
    chariot.cancel_reroll = nil
    chariot.currently_selling = false
    chariot.polychrome_blocked = false
end

chariot.reroll = function()
    if chariot.card_in_shop() ~= nil or chariot.cancel_reroll or G.GAME.dollars - G.GAME.current_round.reroll_cost < 0 then
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

chariot.reroll_automatic = function()
    if chariot.cancel_reroll or G.GAME.dollars - G.GAME.current_round.reroll_cost < 0 then
        chariot.reset_reroll()
        return
    end

    if chariot.sell_jokers() then
        G.E_MANAGER:add_event(Event({
            trigger = 'after',
            delay = 0.05,
            func = function()
                chariot.reroll_automatic()
                return true
            end
        }))
        return
    end

    if chariot.currently_selling then return end

    if chariot.jokers_full() then
        chariot.reset_reroll()
        return
    end

    local reroll_shop = true
    local correct_card = chariot.card_in_shop()
    if correct_card ~= nil then
        local should_end = true
        local identifier = chariot.verify_card(correct_card)
        local has_polychrome = correct_card.edition and correct_card.edition.type == "polychrome"
        if identifier == "sell" then
            if chariot.polychrome_blocked and has_polychrome then
                chariot.reset_reroll()
                return
            end
            if has_polychrome then chariot.polychrome_blocked = true end
            chariot.execute(correct_card, true, false, false)
            should_end = false
            reroll_shop = false
        end
        if identifier == "blueprint" then
            if chariot.polychrome_blocked and has_polychrome then
                chariot.reset_reroll()
                return
            end
            if has_polychrome then chariot.polychrome_blocked = true end
            chariot.execute(correct_card, true, false, false)
            should_end = false
            reroll_shop = false
        end
        if identifier == "chaos" then
            if chariot.polychrome_blocked and has_polychrome then
                chariot.reset_reroll()
                return
            end
            if has_polychrome then chariot.polychrome_blocked = true end
            chariot.execute(correct_card, true, false, false)
            should_end = false
            reroll_shop = false
        end

        if should_end then
            chariot.reset_reroll()
            return
        end
    end

    if reroll_shop then
        G.FUNCS.reroll_shop()
    end

    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        delay = 1,
        func = function()
            chariot.reroll_automatic()
            return true
        end
    }))
end

chariot.card_in_shop = function()
    if G.STATE ~= G.STATES.SHOP or not G.shop_jokers or not G.shop_jokers.cards then return end
    for _, v in ipairs(G.shop_jokers.cards) do
        if chariot.verify_card(v) ~= "false" then return v end
    end
    return nil
end

chariot.verify_card = function(card)
    if chariot.config.negative and card.edition and card.edition.type == "negative" then return "break" end

    if chariot.config.temperance and card.config.center_key == "c_temperance" then return "consumable" end
    if chariot.config.hermit and card.config.center_key == "c_hermit" then return "consumable" end
    if chariot.config.death and card.config.center_key == "c_death" then return "consumable" end
    if chariot.config.fool and card.config.center_key == "c_fool" then return "consumable" end
    if chariot.config.judgement and card.config.center_key == "c_judgement" then return "consumable" end

    if chariot.config.turtle_bean and card.config.center_key == "j_turtle_bean" then return "sell" end
    if chariot.config.diet_cola and card.config.center_key == "j_diet_cola" then return "sell" end
    if chariot.config.brainstorm and card.config.center_key == "j_brainstorm" then return "sell" end
    if chariot.config.blueprint and card.config.center_key == "j_blueprint" then return "blueprint" end
    if chariot.config.chaos_the_clown and card.config.center_key == "j_chaos" then return "chaos" end
    if chariot.config.reserved_parking and card.config.center_key == "j_reserved_parking" then return "sell" end
    if chariot.config.mime and card.config.center_key == "j_mime" then return "sell" end
    if chariot.config.burglar and card.config.center_key == "j_burglar" then return "sell" end
    if chariot.config.showman and card.config.center_key == "j_ring_master" then return "sell" end

    return "false"
end

chariot.crawl_for_buttons = function(ui_buttons, result)
    result = result or {}
    if not ui_buttons then
        return result
    end
    local lua_wtf = {}
    lua_wtf.iterator = function(node)
        if node and node.states and node.states.visible then
            if node.config and node.config.func then
                result[node.config.func] = {
                    node = node,
                    action = node.config.handy_insta_action or nil,
                }
            end
            if node.children then
                for _, child_node in ipairs(node.children) do
                    lua_wtf.iterator(child_node)
                end
            end
        end
    end
    lua_wtf.iterator(ui_buttons.UIRoot)
    return result
end

chariot.can_execute = function(card, buy_or_sell, use)
    return not not (
        (buy_or_sell or use)
        and card
        and card.area
        and card.is
        and card:is(Card)
    )
end
chariot.execute = function(card, buy_or_sell, use, only_sell)
    if card.REMOVED then
        return false
    end

    local target_button = nil
    local is_shop_button = false
    local is_custom_button = false
    local is_playable_consumeable = false

    local current_card_state = card.highlighted
    if not current_card_state then
        card:highlight(true)
    end
    local base_background = G.UIDEF.card_focus_ui(card)
    local base_attach = base_background:get_UIE_by_ID("ATTACH_TO_ME").children
    local card_buttons = G.UIDEF.use_and_sell_buttons(card)
    local card_buttons_ui = UIBox({
        definition = card_buttons,
        config = {},
    })

    local result_funcs = {}
    chariot.crawl_for_buttons(card_buttons_ui, result_funcs)
    chariot.crawl_for_buttons(card.children.use_button, result_funcs)

    local get_node = function(a)
        return a and a.node
    end

    if use then
        if card.area == G.hand and card.ability.consumeable then
            local success, playale_consumeable_button = pcall(function()
                -- G.UIDEF.use_and_sell_buttons(G.hand.highlighted[1]).nodes[1].nodes[2].nodes[1].nodes[1]
                return card_buttons_ui.UIRoot.children[1].children[2].children[1].children[1]
            end)
            if success and playale_consumeable_button then
                target_button = playale_consumeable_button
                is_custom_button = true
                is_playable_consumeable = true
            end
        else
            for _, node_info in pairs(result_funcs) do
                if node_info.action == "use" then
                    target_button = node_info.node
                    is_custom_button = true
                    break
                end
            end
            target_button = target_button
                or base_attach.buy_and_use
                or get_node(result_funcs.can_use_consumeable)
                or base_attach.use
                or card.children.buy_and_use_button
            is_shop_button = target_button == card.children.buy_and_use_button
        end
    elseif buy_or_sell then
        if only_sell then
            for _, node_info in pairs(result_funcs) do
                if node_info.action == "sell" then
                    target_button = node_info.node
                    is_custom_button = true
                    break
                end
            end
            target_button = target_button or base_attach.sell or nil
        else
            for _, node_info in pairs(result_funcs) do
                if node_info.action == "buy" or node_info.action == "sell" or node_info.action == "buy_or_sell" then
                    target_button = node_info.node
                    is_custom_button = true
                    break
                end
            end
            target_button = target_button
                or get_node(result_funcs.can_select_crazy_card) -- Cines
                or get_node(result_funcs.can_select_alchemical) -- Alchemical cards
                or get_node(result_funcs.can_use_mupack) -- Multipacks
                or get_node(result_funcs.can_reserve_card) -- Code cards, for example
                or card.children.buy_button
                or base_attach.buy
                or base_attach.redeem
                or base_attach.sell
        end
        is_shop_button = target_button ~= nil and target_button == card.children.buy_button
    end

    if target_button and not is_shop_button and not is_custom_button then
        for _, node_info in pairs(result_funcs) do
            if node_info.node == target_button then
                is_custom_button = true
                break
            end
        end
    end

    local target_button_UIBox
    local target_button_definition

    local cleanup = function(leave_highlight)
        base_background:remove()
        card_buttons_ui:remove()
        if not leave_highlight and not current_card_state then
            card:highlight(false)
        end
    end
    if target_button then
        target_button_UIBox = target_button
        target_button_definition = (is_custom_button and target_button)
            or (is_shop_button and target_button.definition)
            or target_button.definition.nodes[1]

        local check, button = chariot.fake_check({
            func = G.FUNCS[target_button_definition.config.func],
            node = is_custom_button and target_button or nil,
            UIBox = target_button_UIBox,
            config = target_button_definition.config,
        })
        if check then
            chariot.fake_execute({
                func = G.FUNCS[button or target_button_definition.config.button],
                node = is_custom_button and target_button or nil,
                UIBox = target_button_UIBox,
                config = target_button_definition.config,
            })
            G.E_MANAGER:add_event(Event({
                no_delete = true,
                blocking = false,
                func = function()
                    return true
                end,
            }))
            cleanup(is_playable_consumeable)
            return true
        end
    end

    cleanup()
    return false
end

chariot.fake_check = function(arg)
    if type(arg.func) ~= "function" then
        return false, nil
    end
    if arg.node then
        arg.func(arg.node)
        return arg.node.config.button ~= nil, arg.node.config.button
    else
        local fake_event = {
            UIBox = arg.UIBox,
            config = arg.config or {
                ref_table = arg.card,
                button = arg.button,
                id = arg.id,
            },
        }
        arg.func(fake_event)
        return fake_event.config.button ~= nil, fake_event.config.button
    end
end
chariot.fake_execute = function(arg)
    if type(arg.func) == "function" then
        if arg.node then
            arg.func(arg.node)
        else
            arg.func({
                UIBox = arg.UIBox,
                config = arg.config or {
                    ref_table = arg.card,
                    button = arg.button,
                    id = arg.id,
                },
            })
        end
    end
end

local start_up_ref = Game.start_up
function Game:start_up()
    start_up_ref(self)
    chariot.initialize()
end
