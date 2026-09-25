return function(args,context)
    local mouth=world.request("body_point",{point="mouth"})
    if not mouth.ok then return mouth end
    local reached=world.request("reach_point",{hand="Hand.R",target=mouth.target,seconds=0.8})
    if not reached.ok then return reached end
    local consumed=world.request("consume_unit",{})
    world.request("relax",{seconds=0.5})
    return consumed
end
