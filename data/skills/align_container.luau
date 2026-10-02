return function(args,context)
    if args.destination=="mouth" then
        return world.request("consume_contents",{object=args.object})
    end
    local accessible=skills.call("access",{source=args.destination},context)
    if not accessible.ok then return accessible end
    return world.request("fill_container",{source=args.destination,target=args.object})
end
