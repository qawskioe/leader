return function(args,context)
    local filled=skills.call("fill",{},context)
    if not filled.ok then return filled end
    local arrived=skills.call("go",{object="person/"..args.recipient,distance=1.4},context)
    if not arrived.ok then return arrived end
    return world.request("handover",{object=filled.object,recipient=args.recipient})
end
