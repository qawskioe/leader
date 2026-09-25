return function(args,context)
    for phase=1,4 do
        local seen=world.request("perceive",{})
        local turned=world.request("look_toward",{target={observation_id=seen.observation_id,position={x=3,y=0,z=0}}})
        if not turned.ok then return turned end
    end
    local seen=world.request("perceive",{})
    local choice=nil
    for _,sample in ipairs(seen.near.ground_samples) do
        if sample.state=="visible_surface" and sample.slope_degrees<35 and sample.position.z>3 then choice=sample.position end
    end
    if not choice then return {ok=false,code="no_visible_step"} end
    local moved=world.request("approach",{object={observation_id=seen.observation_id,position=choice},distance=0.25})
    if not moved.ok then return moved end
    world.request("perceive",{})
    return {ok=true,code="local_search_finished",scope="local_search_only"}
end
