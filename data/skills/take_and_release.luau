-- 内置技能也是普通Luau源码；不按物体种类或名字选择专用程序。
return function(args, context)
    local observed = world.request("observe", {object=args.object})
    if not observed.ok then return observed end
    local reached = world.request("reach", {object=args.object, hand="Hand.R", seconds=0.8})
    if not reached.ok then return reached end
    local grasped = world.request("grasp", {object=args.object, hand="Hand.R"})
    if not grasped.ok then return grasped end
    local moved = world.request("pose_bones", {
        pose={ ["Hand.R"]={rotation={x=10,y=0,z=0}} }, seconds=0.4
    })
    if not moved.ok then return moved end
    return world.request("release", {object=args.object})
end
