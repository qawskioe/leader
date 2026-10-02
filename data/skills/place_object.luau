return function(args, context)
    local object = world.request("observe", {object=args.object})
    if not object.ok then return object end
    if not object.held_by_self then return {ok=false, code="not_held"} end
    local surface = world.request("surface", {target=args.target})
    if not surface.ok then return surface end
    if surface.distance > 0.8 then
        local arrived = world.request("approach", {object=args.target, distance=0.45})
        if not arrived.ok then return arrived end
    end
    local moved = world.request("move_held", {object=args.object, target=args.target, seconds=1.0})
    if not moved.ok then return moved end
    local released = world.request("release", {object=args.object})
    if not released.ok then return released end
    local result = world.request("check_placement", {object=args.object, target=args.target})
    return result
end
