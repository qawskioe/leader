return function(args,context)
    local filled=skills.call("fill",{},context)
    if not filled.ok then return filled end
    local home=skills.call("find",{kind="storage"},context)
    if not home.ok then return home end
    local arrived=skills.call("go",{object=home.object,distance=1.0},context)
    if not arrived.ok then return arrived end
    return world.request("release",{object=filled.object})
end
