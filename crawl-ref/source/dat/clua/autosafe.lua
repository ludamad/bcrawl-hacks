local ATT_HOSTILE = 0
local ATT_NEUTRAL = 1
local delta_to_cmd
delta_to_cmd = function(dx, dy)
  local d2v = {
    [-1] = {
      [-1] = "CMD_MOVE_UP_LEFT",
      [0] = "CMD_MOVE_LEFT",
      [1] = "CMD_MOVE_DOWN_LEFT"
    },
    [0] = {
      [-1] = "CMD_MOVE_UP",
      [0] = "CMD_WAIT",
      [1] = "CMD_MOVE_DOWN"
    },
    [1] = {
      [-1] = "CMD_MOVE_UP_RIGHT",
      [0] = "CMD_MOVE_RIGHT",
      [1] = "CMD_MOVE_DOWN_RIGHT"
    }
  }
  return d2v[dx][dy]
end
local sign
sign = function(a)
  return a > 0 and 1 or a < 0 and -1 or 0
end
local abs
abs = function(a)
  return a * sign(a)
end
local choose_move_towards
choose_move_towards = function(ax, ay, bx, by, square_func)
  local los_radius = you.los()
  local move = nil
  local dx = bx - ax
  local dy = by - ay
  local try_move
  try_move = function(mx, my)
    if mx == 0 and my == 0 then
      return nil
    elseif abs(ax + mx) > los_radius or abs(ay + my) > los_radius then
      return nil
    elseif square_func(ax + mx, ay + my) then
      return {
        mx,
        my
      }
    else
      return nil
    end
  end
  if abs(dx) > abs(dy) then
    if abs(dy) == 1 then
      move = try_move(sign(dx), 0)
    end
    if move == nil then
      move = try_move(sign(dx), sign(dy))
    end
    if move == nil then
      move = try_move(sign(dx), 0)
    end
    if move == nil and abs(dx) > abs(dy) + 1 then
      move = try_move(sign(dx), 1)
    end
    if move == nil and abs(dx) > abs(dy) + 1 then
      move = try_move(sign(dx), -1)
    end
    if move == nil then
      move = try_move(0, sign(dy))
    end
  elseif abs(dx) == abs(dy) then
    move = try_move(sign(dx), sign(dy))
    if move == nil then
      move = try_move(sign(dx), 0)
    end
    if move == nil then
      move = try_move(0, sign(dy))
    end
  else
    if abs(dx) == 1 then
      move = try_move(0, sign(dy))
    end
    if move == nil then
      move = try_move(sign(dx), sign(dy))
    end
    if move == nil then
      move = try_move(0, sign(dy))
    end
    if move == nil and abs(dy) > abs(dx) + 1 then
      move = try_move(1, sign(dy))
    end
    if move == nil and abs(dy) > abs(dx) + 1 then
      move = try_move(-1, sign(dy))
    end
    if move == nil then
      move = try_move(sign(dx), 0)
    end
  end
  return move
end
local can_move_maybe
can_move_maybe = function(dx, dy)
  if view.feature_at(dx, dy) ~= "unseen" and view.is_safe_square(dx, dy) then
    local m = monster.get_monster_at(dx, dy)
    if not m or not m:is_firewood() then
      return true
    end
  end
  return false
end
local have_reaching
have_reaching = function()
  local wp = items.equipped_at("weapon")
  return wp and wp.reach_range == 2 and not wp.is_melded
end
local will_tab
will_tab = function(ax, ay, bx, by)
  if abs(bx - ax) <= 1 and abs(by - ay) <= 1 or abs(bx - ax) <= 2 and abs(by - ay) <= 2 and have_reaching() then
    return true
  end
  local move = choose_move_towards(ax, ay, bx, by, can_move_maybe)
  if move == nil then
    return false
  end
  return will_tab(ax + move[1], ay + move[2], bx, by)
end
local have_ranged
have_ranged = function()
  local wp = items.equipped_at("weapon")
  return wp and wp.is_ranged and not wp.is_melded
end
local have_throwing
have_throwing = function(no_move)
  return (AUTOFIGHT_THROW or no_move and AUTOFIGHT_THROW_NOMOVE) and items.fired_item() ~= nil
end
local get_monster_info
get_monster_info = function(dx, dy, no_move)
  local m = monster.get_monster_at(dx, dy)
  local name = m:name()
  if not m then
    return nil
  end
  local info = { }
  info.name = name
  info.distance = ((function()
    if abs(dx) > abs(dy) then
      return -abs(dx)
    else
      return -abs(dy)
    end
  end)())
  if have_ranged() then
    info.attack_type = you.see_cell_no_trans(dx, dy) and 3 or 0
  elseif not have_reaching() then
    info.attack_type = ((function()
      if -info.distance < 2 then
        return 2
      else
        return 0
      end
    end)())
  else
    if -info.distance > 2 then
      info.attack_type = 0
    elseif -info.distance < 2 then
      info.attack_type = 2
    else
      info.attack_type = ((function()
        if view.can_reach(dx, dy) then
          return 1
        else
          return 0
        end
      end)())
    end
  end
  if info.attack_type == 0 and have_throwing(no_move) and you.see_cell_no_trans(dx, dy) then
    info.attack_type = 3
  end
  if info.attack_type == 0 and not will_tab(0, 0, dx, dy) then
    info.attack_type = -1
  end
  info.can_attack = ((function()
    if info.attack_type > 0 then
      return 1
    else
      return info.attack_type
    end
  end)())
  info.safe = m:is_safe() and -1 or 0
  info.constricting_you = ((function()
    if m:is_constricting_you() then
      return 1
    else
      return 0
    end
  end)())
  info.very_stabbable = ((function()
    if m:stabbability() >= 1 then
      return 1
    else
      return 0
    end
  end)())
  info.injury = m:damage_level()
  info.threat = m:threat()
  info.orc_priest_wizard = ((function()
    if name == "orc priest" or name == "orc wizard" then
      return 1
    else
      return 0
    end
  end)())
  return info
end
local flag_order = {
  "threat",
  "can_attack",
  "safe",
  "distance",
  "constricting_you",
  "very_stabbable",
  "injury",
  "orc_priest_wizard"
}
local compare_monster_info
compare_monster_info = function(m1, m2)
  for i, flag in ipairs(flag_order) do
    if m1[flag] > m2[flag] then
      return true
    elseif m1[flag] < m2[flag] then
      return false
    end
  end
  return false
end
local is_candidate_for_attack
is_candidate_for_attack = function(x, y)
  local m = monster.get_monster_at(x, y)
  if not m or m:attitude() ~= ATT_HOSTILE then
    return false
  end
  if m:name() == "butterfly" or m:name() == "orb of destruction" then
    return false
  end
  if m:is_firewood() then
    if string.find(m:name(), "ballistomycete") then
      return true
    end
    return false
  end
  return true
end
local get_target
get_target = function(no_move)
  local x, y, bestx, besty, best_info, new_info
  local los_radius = you.los()
  bestx = 0
  besty = 0
  best_info = nil
  for x = -los_radius, los_radius do
    for y = -los_radius, los_radius do
      if is_candidate_for_attack(x, y) then
        new_info = get_monster_info(x, y, no_move)
        if (not best_info) or compare_monster_info(new_info, best_info) then
          bestx = x
          besty = y
          best_info = new_info
        end
      end
    end
  end
  return bestx, besty, best_info
end
local should_confirm_move
should_confirm_move = function(cmd_name, dx, dy)
  local bestx, besty, best_info = get_target(true)
  if not best_info then
    return false
  end
  if best_info.threat < 2 then
    return false
  end
  return true, tostring(best_info.name) .. " has threat " .. tostring(best_info.threat) .. ". Do you do the move " .. tostring(cmd_name) .. "? [y/n]"
end
local is_safe_or_confirmed_move
is_safe_or_confirmed_move = function(cmd_name, dx, dy)
  local should_confirm, msg = should_confirm_move(cmd_name, dx, dy)
  if should_confirm then
    return crawl.yesno(msg)
  end
  return true
end
local _list_0 = {
  {
    "safe_up",
    "up",
    0,
    -1
  },
  {
    "safe_down",
    "down",
    0,
    1
  },
  {
    "safe_left",
    "left",
    -1,
    0
  },
  {
    "safe_right",
    "right",
    1,
    0
  },
  {
    "safe_wait",
    "to the same square",
    0,
    0
  },
  {
    "safe_up_left",
    "up-left",
    -1,
    -1
  },
  {
    "safe_up_right",
    "up-right",
    1,
    -1
  },
  {
    "safe_down_left",
    "down-left",
    -1,
    1
  },
  {
    "safe_down_right",
    "down-right",
    1,
    1
  }
}
for _index_0 = 1, #_list_0 do
  local _des_0 = _list_0[_index_0]
  local func_name, cmd_name, dx, dy
  func_name, cmd_name, dx, dy = _des_0[1], _des_0[2], _des_0[3], _des_0[4]
  _G[func_name] = function()
    if not is_safe_or_confirmed_move(cmd_name, dx, dy) then
      return crawl.mpr("Not moving " .. tostring(cmd_name) .. "! Think a bit!")
    else
      return crawl.do_commands({
        delta_to_cmd(dx, dy)
      })
    end
  end
end
local prev_hit_closest = hit_closest
_G.hit_closest = function()
  local bestx, besty, best_info = get_target(true)
  if best_info and best_info.threat >= 2 and not crawl.yesno("Attack monster " .. tostring(best_info.name) .. " with threat " .. tostring(best_info.threat) .. "? [y/n]") then
    crawl.mpr("Not autoattacking, think!")
    return 
  end
  return prev_hit_closest()
end
_G.show_safety = function()
  local bestx, besty, best_info = get_target(true)
  return crawl.mpr("Target: " .. tostring(best_info.threat))
end
