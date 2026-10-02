return function(args,context)
    local seen=world.request("perceive",{})
    if args.source=="hand" then
        return {ok=seen.held_unit.material=="food",code=seen.held_unit.material=="food" and "already_carrying_food" or "no_food_in_hand"}
    end
    if seen.held_unit.material then return {ok=false,code="hand_occupied"} end
    local arrived=skills.call("go",{object=args.source,distance=1.0},context)
    if not arrived.ok then return arrived end
    local refreshed=world.request("perceive",{})
    local entry=refreshed.near.landmarks[args.source] or refreshed.known[args.source]
    local extra=entry and entry.extra or {}
    if (extra.contents or {}).material~="food" and extra.food_count==nil then
        return {ok=false,code="source_not_food"}
    end
    local touched=skills.call("touch",{source=args.source},context)
    if not touched.ok then return touched end
    local taken=world.request("take_unit",{source=args.source})
    return taken
end
