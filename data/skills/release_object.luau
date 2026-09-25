return function(args, context)
    return world.request("release", {object=args.object})
end
