return function(args,context)
    local seen=world.request("perceive",{})
    local container=nil
    for _,held in ipairs(seen.near.held_objects) do
        if seen.known[held.id] and seen.known[held.id].kind=="water_bag" then container=held.id break end
    end
    if not container then
        local found=skills.call("find",{kind="water_bag"},context)
        if not found.ok then return found end
        container=found.object
        local arrived=skills.call("go",{object=container,distance=1.0},context)
        if not arrived.ok then return arrived end
        local picked=skills.call("hold",{object=container,hand="Hand.R"},context)
        if not picked.ok then return picked end
    end
    local content=world.request("inspect_contents",{object=container})
    if not content.ok then return content end
    if content.quantity<content.capacity then
        local source=skills.call("find",{kind="water_source"},context)
        if not source.ok then return source end
        local arrived=skills.call("go",{object=source.object,distance=0.75},context)
        if not arrived.ok then return arrived end
        local filled=skills.call("align",{object=container,destination=source.object},context)
        if not filled.ok then return filled end
    end
    return {ok=true,object=container,code="holding_water"}
end
