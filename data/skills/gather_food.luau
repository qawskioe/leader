return function(args,context)
    local container=nil
    local seen=world.request("perceive",{})
    for _,held in ipairs(seen.near.held_objects) do
        if seen.known[held.id] and seen.known[held.id].kind=="basket" then container=held.id break end
    end
    if not container then
        local found=skills.call("locate",{kind="basket"},context)
        if not found.ok then return found end
        container=found.object
        local picked=skills.call("hold",{object=container,hand="Hand.L"},context)
        if not picked.ok then return picked end
    end
    local grove=skills.call("find",{kind="forage_area"},context)
    if not grove.ok then return grove end
    local arrived=skills.call("go",{object=grove.object,distance=1.5},context)
    if not arrived.ok then return arrived end
    local tried={}
    for attempt=1,24 do
        local contents=world.request("inspect_contents",{object=container})
        if not contents.ok then return contents end
        if contents.quantity>=contents.capacity then break end
        seen=world.request("perceive",{})
        local chosen=nil
        local nearest=math.huge
        for id,entry in pairs(seen.known) do
            if entry.kind=="fruit" and entry.available~=false and not tried[id] then
                local p=entry.position or entry.approx_position
                if p and p.x*p.x+p.z*p.z<nearest then chosen=id nearest=p.x*p.x+p.z*p.z end
            end
        end
        if not chosen then break end
        tried[chosen]=true
        arrived=skills.call("go",{object=chosen,distance=1.0},context)
        if arrived.ok then
            local touched=skills.call("touch",{source=chosen},context)
            if touched.ok then
                local taken=world.request("take_unit",{source=chosen})
                if taken.ok then
                    local touched_basket=skills.call("touch",{source=container},context)
                    if not touched_basket.ok then return touched_basket end
                    local loaded=world.request("put_unit",{target=container})
                    if not loaded.ok then return loaded end
                end
            end
        end
    end
    local stored=skills.call("store",{container=container},context)
    if not stored.ok then return stored end
    if stored.quantity==0 then return {ok=false,code="no_food_collected",quantity=0,target=stored.target} end
    return stored
end
