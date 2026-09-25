return function(args,context)
    local seen=world.request("perceive",{})
    if seen.held_unit.material=="food" then return {ok=true,code="already_carrying_food"} end
    if seen.held_unit.material then return {ok=false,code="hand_occupied"} end
    local source=skills.call("find",{kind="storage"},context)
    if not source.ok then return source end
    local arrived=skills.call("go",{object=source.object,distance=1.0},context)
    if not arrived.ok then return arrived end
    local touched=skills.call("touch",{source=source.object},context)
    if not touched.ok then return touched end
    local taken=world.request("take_unit",{source=source.object})
    world.request("relax",{seconds=0.4})
    return taken
end
