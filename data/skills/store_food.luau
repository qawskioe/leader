return function(args,context)
    local seen=world.request("perceive",{})
    local held=false
    for _,object in ipairs(seen.near.held_objects) do if object.id==args.container then held=true end end
    if not held then
        local arrived=skills.call("go",{object=args.container,distance=1.0},context)
        if not arrived.ok then return arrived end
        local picked=skills.call("hold",{object=args.container,hand="Hand.L"},context)
        if not picked.ok then return picked end
    end
    local found=skills.call("find",{kind="storage"},context)
    if not found.ok then return found end
    local arrived=skills.call("go",{object=found.object,distance=0.65},context)
    if not arrived.ok then return arrived end
    local stored=0
    for index=1,64 do
        local current=world.request("perceive",{})
        if not current.held_unit.material then
            local content=world.request("inspect_contents",{object=args.container})
            if not content.ok then return content end
            if content.quantity==0 then break end
            local touched=skills.call("touch",{source=args.container},context)
            if not touched.ok then return touched end
            local taken=world.request("take_unit",{source=args.container})
            if not taken.ok then return taken end
        end
        local touched=skills.call("touch",{source=found.object},context)
        if not touched.ok then return touched end
        local placed=world.request("put_unit",{target=found.object})
        if not placed.ok then return placed end
        stored+=1
    end
    local released=world.request("release",{object=args.container})
    if not released.ok then return released end
    world.request("relax",{seconds=0.4})
    return {ok=true,code="stored",quantity=stored,target=found.object}
end
