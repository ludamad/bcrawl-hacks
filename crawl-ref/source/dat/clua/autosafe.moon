ATT_HOSTILE = 0
ATT_NEUTRAL = 1

delta_to_cmd = (dx, dy) ->
    d2v = {
        [-1]: {
            [-1]: "CMD_MOVE_UP_LEFT"
            [0]: "CMD_MOVE_LEFT"
            [1]: "CMD_MOVE_DOWN_LEFT"
        }
        [0]: {
            [-1]: "CMD_MOVE_UP"
            [0]: "CMD_WAIT"
            [1]: "CMD_MOVE_DOWN"
        }
        [1]: {
            [-1]: "CMD_MOVE_UP_RIGHT"
            [0]: "CMD_MOVE_RIGHT"
            [1]: "CMD_MOVE_DOWN_RIGHT"
        }
    }
    return d2v[dx][dy]

sign = (a) ->
    return a > 0 and 1 or a < 0 and -1 or 0

abs = (a) ->
    return a * sign(a)

choose_move_towards = (ax, ay, bx, by, square_func) ->
    los_radius = you.los()
    move = nil
    dx = bx - ax
    dy = by - ay
    try_move = (mx, my) ->
        if mx == 0 and my == 0
            return nil
        elseif abs(ax+mx) > los_radius or abs(ay+my) > los_radius
            return nil
        elseif square_func(ax+mx, ay+my)
            return {mx,my}
        else
            return nil
    if abs(dx) > abs(dy)
        if abs(dy) == 1
            move = try_move(sign(dx), 0)
        if move == nil then move = try_move(sign(dx), sign(dy))
        if move == nil then move = try_move(sign(dx), 0)
        if move == nil and abs(dx) > abs(dy)+1
            move = try_move(sign(dx), 1)
        if move == nil and abs(dx) > abs(dy)+1
            move = try_move(sign(dx), -1)
        if move == nil then move = try_move(0, sign(dy))
    elseif abs(dx) == abs(dy)
        move = try_move(sign(dx), sign(dy))
        if move == nil then move = try_move(sign(dx), 0)
        if move == nil then move = try_move(0, sign(dy))
    else
        if abs(dx) == 1
            move = try_move(0, sign(dy))
        if move == nil then move = try_move(sign(dx), sign(dy))
        if move == nil then move = try_move(0, sign(dy))
        if move == nil and abs(dy) > abs(dx)+1
            move = try_move(1, sign(dy))
        if move == nil and abs(dy) > abs(dx)+1
            move = try_move(-1, sign(dy))
        if move == nil then move = try_move(sign(dx), 0)
    return move

can_move_maybe = (dx, dy) ->
  if view.feature_at(dx,dy) ~= "unseen" and view.is_safe_square(dx,dy)
    m = monster.get_monster_at(dx, dy)
    if not m or not m\is_firewood()
      return true
  return false

have_reaching = () ->
    wp = items.equipped_at("weapon")
    return wp and wp.reach_range == 2 and not wp.is_melded

will_tab = (ax, ay, bx, by) ->
    if abs(bx-ax) <= 1 and abs(by-ay) <= 1 or abs(bx-ax) <= 2 and abs(by-ay) <= 2 and have_reaching()
        return true
    move = choose_move_towards(ax, ay, bx, by, can_move_maybe)
    if move == nil
        return false
    return will_tab(ax+move[1], ay+move[2], bx, by)

have_ranged = () ->
    wp = items.equipped_at("weapon")
    return wp and wp.is_ranged and not wp.is_melded

have_throwing = (no_move) ->
    return (AUTOFIGHT_THROW or no_move and AUTOFIGHT_THROW_NOMOVE) and items.fired_item() ~= nil

get_monster_info = (dx,dy,no_move) ->
    m = monster.get_monster_at(dx,dy)
    name = m\name()
    if not m
        return nil
    info = {}
    info.name = name
    info.distance = (if abs(dx) > abs(dy) then -abs(dx) else -abs(dy))
    if have_ranged()
        info.attack_type = you.see_cell_no_trans(dx, dy) and 3 or 0
    elseif not have_reaching()
        info.attack_type = (if -info.distance < 2 then 2 else 0)
    else
        if -info.distance > 2
            info.attack_type = 0
        elseif -info.distance < 2
            info.attack_type = 2
        else
            info.attack_type = (if view.can_reach(dx, dy) then 1 else 0)
    if info.attack_type == 0 and have_throwing(no_move) and you.see_cell_no_trans(dx, dy)
        info.attack_type = 3
    if info.attack_type == 0 and not will_tab(0,0,dx,dy)
        info.attack_type = -1
    info.can_attack = (if info.attack_type > 0 then 1 else info.attack_type)
    info.safe = m\is_safe() and -1 or 0
    info.constricting_you = (if m\is_constricting_you() then 1 else 0)
    -- Only prioritize good stabs\ sleep and paralysis.
    info.very_stabbable = (if m\stabbability() >= 1 then 1 else 0)
    info.injury = m\damage_level()
    info.threat = m\threat()
    info.orc_priest_wizard = (if name == "orc priest" or name == "orc wizard" then 1 else 0)
    return info

flag_order = {"threat", "can_attack", "safe", "distance", "constricting_you", "very_stabbable", "injury", "orc_priest_wizard"}
compare_monster_info = (m1, m2) ->
    -- flag_order = autofight_flag_order
    -- if flag_order == nil
        -- flag_order = {"can_attack", "safe", "distance", "constricting_you", "very_stabbable", "injury", "threat", "orc_priest_wizard"}
    for i,flag in ipairs(flag_order)
        if m1[flag] > m2[flag]
            return true
        elseif m1[flag] < m2[flag]
            return false
    return false

is_candidate_for_attack = (x,y) ->
    m = monster.get_monster_at(x, y)
    if not m or m\attitude() ~= ATT_HOSTILE
        return false
    if m\name() == "butterfly" or m\name() == "orb of destruction"
        return false
    if m\is_firewood()
        if string.find(m\name(), "ballistomycete")
            return true
        return false
    return true


get_target = (no_move) ->
  local x, y, bestx, besty, best_info, new_info
  los_radius = you.los()
  bestx = 0
  besty = 0
  best_info = nil
  for x = -los_radius,los_radius
    for y = -los_radius,los_radius
      if is_candidate_for_attack(x, y)
        new_info = get_monster_info(x, y, no_move)
        if (not best_info) or compare_monster_info(new_info, best_info)
          bestx = x
          besty = y
          best_info = new_info
  return bestx, besty, best_info


should_confirm_move = (cmd_name, dx, dy) ->
    bestx, besty, best_info = get_target(true)
    if not best_info
        -- Can move freely, no enemies
        return false
    if best_info.threat < 2
        return false
    return true, "#{best_info.name} has threat #{best_info.threat}. Do you do the move #{cmd_name}? [y/n]"

is_safe_or_confirmed_move = (cmd_name, dx, dy) ->
    should_confirm, msg = should_confirm_move(cmd_name, dx, dy)
    if should_confirm
        return crawl.yesno(msg)
    return true

for {func_name, cmd_name, dx, dy} in *{
    {"safe_up", "up", 0, -1}
    {"safe_down", "down", 0, 1}
    {"safe_left", "left", -1, 0}
    {"safe_right", "right", 1, 0}
    {"safe_wait", "to the same square", 0, 0}
    {"safe_up_left", "up-left", -1, -1}
    {"safe_up_right", "up-right", 1, -1}
    {"safe_down_left", "down-left", -1, 1}
    {"safe_down_right", "down-right", 1, 1}
}
    _G[func_name] = () ->
        -- We want to detect these cases...
        -- 1) Confirm running from a fast monster
        -- 2) Confirm moving towards a strong monster
        -- 3) Confirm moving towards enough damage to deal 50% of my health
        -- 4) Confirm moving in range of throwing enemies
        -- 5) Doing ANYTHING while slow
        if not is_safe_or_confirmed_move(cmd_name, dx, dy)
            crawl.mpr("Not moving #{cmd_name}! Think a bit!")
        else
            crawl.do_commands({delta_to_cmd(dx, dy)})

prev_hit_closest = hit_closest
_G.hit_closest = () ->
    bestx, besty, best_info = get_target(true)
    if best_info and best_info.threat >= 2 and not crawl.yesno("Attack monster #{best_info.name} with threat #{best_info.threat}? [y/n]")
        crawl.mpr("Not autoattacking, think!")
        return
    prev_hit_closest()

_G.show_safety = () ->
    bestx, besty, best_info = get_target(true)
    crawl.mpr("Target: ".. tostring(best_info.threat))
     
