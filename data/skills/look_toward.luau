return function(args, context)
    return world.request("look_toward", {target=args.target})
end
