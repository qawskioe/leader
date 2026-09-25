return function(args,context)
    local taken=skills.call("fetch",{},context)
    if not taken.ok then return taken end
    return skills.call("consume",{},context)
end
