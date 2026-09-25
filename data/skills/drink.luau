return function(args,context)
    local seen=world.request("perceive",{})
    if seen.held_unit.material=="water" then return skills.call("consume",{},context) end
    if seen.held_unit.material then return {ok=false,code="hand_occupied"} end
    local source=nil
    for id,entry in pairs(seen.known) do
        if entry.kind=="water_bag" and entry.available~=false and (entry.extra or {}).water and entry.extra.water>0 then source=id break end
    end
    if not source then
        local found=skills.call("find",{kind="water_source"},context)
        if not found.ok then return found end
        source=found.object
    end
    local arrived=skills.call("go",{object=source,distance=1.0},context)
    if not arrived.ok then return arrived end
    local refreshed=world.request("perceive",{})
    if refreshed.known[source] and refreshed.known[source].kind=="water_bag" then
        local held=skills.call("hold",{object=source,hand="Hand.R"},context)
        if not held.ok then return held end
        return skills.call("align",{object=source,destination="mouth"},context)
    end
    local touched=skills.call("touch",{source=source},context)
    if not touched.ok then return touched end
    local taken=world.request("take_unit",{source=source})
    if not taken.ok then return taken end
    return skills.call("consume",{},context)
end
