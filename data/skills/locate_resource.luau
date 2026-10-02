return function(args,context)
    local recalled=world.request("recall_locations",{kind=args.kind})
    if not recalled.ok then return recalled end
    local tried={}
    local last_failure=nil
    for attempt=1,4 do
        local seen=world.request("perceive",{})
        if not seen.ok then return seen end
        local choices={}
        for id,entry in pairs(seen.known) do choices[id]=entry end
        for id,entry in pairs(seen.near.landmarks) do choices[id]=entry end
        local chosen=nil
        local score=math.huge
        for id,entry in pairs(choices) do
            if entry.kind==args.kind and entry.available~=false and not tried[id] then
                local p=entry.position or entry.approx_position
                if p then
                    local value=p.x*p.x+p.z*p.z
                    if seen.near.landmarks[id] then value-=10000 end
                    if value<score then chosen=id score=value end
                end
            end
        end
        if not chosen then break end
        tried[chosen]=true
        last_failure=skills.call("go",{object=chosen,distance=1.0},context)
        -- 没走到方法自设的距离，不代表目标不可见或不可交互。只报告实际观察，
        -- 是否拿得到仍由调用方的世界操作判断；不伪造物品已找到或位置已空。
        for turn=0,3 do
            seen=world.request("perceive",{})
            if not seen.ok then return seen end
            local entry=seen.near.landmarks[chosen]
            if entry and entry.available~=false then
                return {ok=true,code="resource_observed",object=chosen}
            end
            if turn<3 then
                local turned=world.request("look_toward",{target={observation_id=seen.observation_id,position={x=1,y=0,z=0}}})
                if not turned.ok then return turned end
            end
        end
    end
    return {ok=false,code="no_observed_resource",cause=last_failure,message="已检查有限的本人已知线索，尚未确认可用资源；不代表世界中不存在该资源"}
end
