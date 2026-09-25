return function(args,context)
    for attempt=1,3 do
        local seen=world.request("perceive",{})
        -- 左手把持有的容器送到胸前，再让右手接触；弯腰不会缩短两手横向距离。
        for _,held in ipairs(seen.near.held_objects) do
            if held.id==args.source and held.hand=="Hand.L" then
                local relaxed=world.request("relax",{seconds=0.3})
                if not relaxed.ok then return relaxed end
                local mouth=world.request("body_point",{point="mouth"})
                if not mouth.ok then return mouth end
                local p=mouth.target.position
                local centered=world.request("reach_point",{hand="Hand.L",target={observation_id=mouth.target.observation_id,position={x=p.x,y=p.y-0.45,z=p.z+0.3}},seconds=0.6})
                if not centered.ok then return centered end
            end
        end
        local point=world.request("contact_point",{source=args.source})
        if not point.ok then
            local memory=seen.known[args.source]
            if point.code~="not_observed" or not memory or not memory.position then return point end
            point={ok=true,position={observation_id=seen.observation_id,position=memory.position}}
        end
        local reached=world.request("reach_point",{hand="Hand.R",target=point.position,seconds=0.6})
        if reached.ok then return reached end
        if attempt<3 then
            local posed=world.request("pose",{pose={lower_hips=attempt==1 and 0.35 or 0.55,Spine={x=45,y=0,z=0},Chest={x=30,y=0,z=0}},seconds=0.4})
            if not posed.ok then return posed end
        else return reached end
    end
end
