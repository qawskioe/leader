return function(args, context)
    local seen=world.request("perceive",{})
    local choices={}
    for id,entry in pairs(seen.known) do choices[id]=entry end
    local recalled=world.request("recall_locations",{kind=args.kind})
    if recalled.ok then
        for id,entry in pairs(recalled.locations) do if not choices[id] then choices[id]=entry end end
    end
    -- 当前亲眼所见覆盖旧位置、旧可用状态；回忆不会替代当前观察。
    for id,entry in pairs(seen.near.landmarks) do choices[id]=entry end
    local best=nil
    local score=math.huge
    for id,entry in pairs(choices) do
        if entry.kind==args.kind and (entry.available~=false or args.kind=="storage" or args.kind=="forage_area") then
            local p=entry.position or entry.approx_position
            if p then
                local n=p.x*p.x+p.z*p.z
                if seen.near.landmarks[id] then n-=1000 end
                if n<score then best=id score=n end
            end
        end
    end
    return {ok=best~=nil,code=best and "remembered_candidate" or "no_known_candidate",object=best or ""}
end
