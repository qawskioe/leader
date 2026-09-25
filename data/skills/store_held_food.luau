return function(args,context)
    local seen=world.request("perceive",{})
    if seen.held_unit.material~="food" then return {ok=false,code="no_food_in_hand"} end
    local found=skills.call("find",{kind="storage"},context)
    if not found.ok then return found end
    local moved=skills.call("go",{object=found.object,distance=0.65},context)
    if not moved.ok then return moved end
    local touched=skills.call("touch",{source=found.object},context)
    if not touched.ok then return touched end
    local stored=world.request("put_unit",{target=found.object})
    world.request("relax",{seconds=0.4})
    return stored
end
