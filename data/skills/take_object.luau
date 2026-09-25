return function(args, context)
    local seen=world.request("perceive",{})
    local observed=world.request("observe",{object=args.object})
    if observed.ok and observed.held_by_self then return {ok=true,code="already_in_hand",object=args.object} end
    if observed.ok and observed.held then return {ok=false,code="held_by_other",object=args.object} end
    if not seen.available_hands["Hand.L"] and not seen.available_hands["Hand.R"] then return {ok=false,code="hands_occupied"} end
    -- 只有目标不在视野内才先按记忆接近；可见物直接交给站位规划。
    if not observed.ok then
        local arrived=skills.call("go",{object=args.object,distance=1.2},context)
        if not arrived.ok then return arrived end
        world.request("perceive",{})
        observed=world.request("observe",{object=args.object})
        if not observed.ok then return observed end
    end
    return skills.call("hold",{object=args.object,hand=observed.nearest_free_hand},context)
end
