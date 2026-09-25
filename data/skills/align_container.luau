return function(args,context)
    for attempt=1,4 do
        local seen=world.request("perceive",{})
        local content=world.request("inspect_contents",{object=args.object})
        local object=world.request("observe",{object=args.object})
        if not content.ok then return content end
        if not object.ok then return object end
        local target
        if args.destination=="mouth" then
            target=world.request("body_point",{point="mouth"})
            if not target.ok then return target end
            target=target.target
        else
            local contact=world.request("contact_point",{source=args.destination})
            if not contact.ok then
                local memory=seen.known[args.destination]
                if contact.code~="not_observed" or not memory or not memory.position then return contact end
                contact={ok=true,position={observation_id=seen.observation_id,position=memory.position}}
            end
            target=contact.position
        end
        local p=target.position
        local opening=content.opening.position
        local grip=object.grip_position
        local hand_target={observation_id=target.observation_id,position={x=p.x+grip.x-opening.x,y=p.y+grip.y-opening.y,z=p.z+grip.z-opening.z}}
        local reached=world.request("reach_point",{hand=object.hand,target=hand_target,seconds=0.7})
        if args.destination=="mouth" then
            local consumed=world.request("consume_contents",{object=args.object})
            if consumed.ok then world.request("relax",{seconds=0.4}) return consumed end
        else
            local filled=world.request("fill_container",{source=args.destination,target=args.object})
            if filled.ok then world.request("relax",{seconds=0.4}) return filled end
        end
        if not reached.ok and attempt<4 then
            world.request("pose",{pose={lower_hips=0.55,Spine={x=60,y=0,z=0},Chest={x=40,y=0,z=0}},seconds=0.4})
        end
    end
    return {ok=false,code="container_contact_failed"}
end
