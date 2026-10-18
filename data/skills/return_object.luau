return function(args, context)
    local taken=skills.call("take",{object=args.object},context)
    if not taken.ok then return taken end
    local arrived=skills.call("go",{object="person/"..args.recipient,distance=1.4},context)
    if not arrived.ok then return arrived end
    return skills.call("give",{object=args.object,recipient=args.recipient},context)
end
