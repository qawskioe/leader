return function(args, context)
    return world.request("handover", {object=args.object, recipient=args.recipient})
end
