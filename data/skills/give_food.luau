return function(args,context)
    local taken=skills.call("fetch",{source=args.source},context)
    if not taken.ok then return taken end
    local arrived=skills.call("go",{object="person/"..args.recipient,distance=1.4},context)
    if not arrived.ok then return arrived end
    return world.request("give_unit",{recipient=args.recipient})
end
