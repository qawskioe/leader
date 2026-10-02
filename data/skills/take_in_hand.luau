return function(args,context)
    local seen=world.request("perceive",{})
    local observed=world.request("observe",{object=args.object})
    if observed.ok and observed.held_by_self then
        if observed.hand==args.hand then return {ok=true,code="already_in_hand",object=args.object} end
        return world.request("change_grip",{object=args.object,hand=args.hand})
    end
    if observed.ok and observed.held then return {ok=false,code="held_by_other",object=args.object} end
    if not seen.available_hands[args.hand] then return {ok=false,code="hand_occupied"} end
    local result=world.request("grasp",{object=args.object,hand=args.hand})
    if result.ok or (result.code~="out_of_reach" and result.code~="not_observed") then return result end
    local arrived=skills.call("go",{object=args.object,distance=1.0},context)
    if not arrived.ok then return arrived end
    world.request("perceive",{})
    return world.request("grasp",{object=args.object,hand=args.hand})
end
