return function(args,context)
    local own=world.request("perceive",{})
    local observed=world.request("observe",{object=args.object})
    if observed.ok and observed.held_by_self then
        if observed.hand==args.hand then return {ok=true,code="already_in_hand",object=args.object} end
        local reached=world.request("reach",{object=args.object,hand=args.hand,seconds=0.6})
        if not reached.ok then return reached end
        return world.request("change_grip",{object=args.object,hand=args.hand})
    end
    if observed.ok and observed.held then return {ok=false,code="held_by_other",object=args.object} end
    if not own.available_hands[args.hand] then return {ok=false,code="hand_occupied"} end
    if not observed.ok or math.sqrt(observed.body_position.x^2+observed.body_position.z^2)>2.5 then
        local arrived=skills.call("go",{object=args.object,distance=1.2},context)
        if not arrived.ok then return arrived end
    end
    local last=nil
    for attempt=1,2 do
        local plan=world.request("plan_grasp",{object=args.object,hand=args.hand,exclude_current=attempt>1})
        if not plan.ok then return plan end
        if plan.needs_move then
            if attempt>1 then
                local restored=world.request("relax",{seconds=0.5})
                if not restored.ok then return restored end
            end
            local moved=world.request("approach",{object=plan.stance,distance=0})
            if not moved.ok then return {ok=false,code="grasp_route_blocked",detail=moved} end
        end
        local turned=world.request("look_toward",{target=plan.look_target})
        if not turned.ok then return turned end
        last=world.request("reach_with_body",{object=args.object,hand=args.hand,seconds=1.8})
        if last.ok then return world.request("grasp",{object=args.object,hand=args.hand}) end
        if last.code~="body_out_of_reach" then return last end
    end
    return {ok=false,code="grasp_unreachable",detail=last,attempts=2}
end
