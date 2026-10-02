return function(args,context)
    local seen=world.request("perceive",{})
    local accessible=world.request("access_source",{source=args.source})
    if accessible.ok then return accessible end
    if accessible.code~="not_observed" and accessible.code~="out_of_reach" then return accessible end
    -- 记忆仅用于寻找，不能伪造当前可见或可操作的回执。
    local arrived=skills.call("go",{object=args.source,distance=1.0},context)
    if not arrived.ok then return arrived end
    world.request("perceive",{})
    return world.request("access_source",{source=args.source})
end
