return function(args, context)
    local blocked=0
    local visited={}
    local passed_routes={}
    world.request("recall_locations",{kind="route"})
    for step=1,48 do
        local seen=world.request("walk_options",{})
        local entry=seen.near.landmarks[args.object] or seen.known[args.object]
        if not entry then return {ok=false,code="location_not_in_working_memory"} end
        local p=entry.position or entry.approx_position
        if not p then return {ok=false,code="unknown_location"} end
        local target_distance=math.sqrt(p.x*p.x+p.z*p.z)
        local route=nil
        local best_route_cost=math.huge
        -- 本人记得的来路可以作为中间参照；不是宿主提供的全地图导航。
        if target_distance>6 then
            for id,waypoint in pairs(seen.known) do
                if waypoint.kind=="route" and id~=args.object and not passed_routes[id] then
                    local q=waypoint.position or waypoint.approx_position
                    if q then
                        local distance=math.sqrt(q.x*q.x+q.z*q.z)
                        local remaining=math.sqrt((p.x-q.x)^2+(p.z-q.z)^2)
                        if distance<1.6 then passed_routes[id]=true
                        elseif q.x*p.x+q.z*p.z>0 and remaining<target_distance-2 and distance+remaining<target_distance*1.8 and distance+remaining<best_route_cost then
                            route=id best_route_cost=distance+remaining
                        end
                    end
                end
            end
        end
        if route then p=seen.known[route].position or seen.known[route].approx_position end
        local distance=math.sqrt(p.x*p.x+p.z*p.z)
        -- 先确认到达；外部目标只转向一次，手持物随本人转动，不能追逐其方位。
        if distance<(route and 1.6 or args.distance) then
            if route then passed_routes[route]=true
            else
                local carried=false
                for _,held in ipairs(seen.near.held_objects) do
                    if held.id==args.object then carried=true break end
                end
                if not carried and distance>0.05 then
                    local turned=world.request("look_toward",{target={observation_id=seen.observation_id,position={x=p.x,y=0,z=p.z}}})
                    if not turned.ok then return turned end
                end
                return {ok=true,code="at_remembered_location",object=args.object,message="已接近最后所知位置；外部目标已转向，物品当前状态与接触方式仍需观察确认"}
            end
        -- 粗略记忆会随转身重新量化。视野内允许侧向目标，先选地面前进再观察，
        -- 不把粗略方位当成必须逐步对齐的精确朝向（±45°会来回跳变）。
        elseif distance>0.05 and (p.z<=0 or math.abs(p.x)>p.z*math.sqrt(3)) then
            local scale=math.min(1,5/math.max(distance,0.01))
            local turned=world.request("look_toward",{target={observation_id=seen.observation_id,position={x=p.x*scale,y=0,z=p.z*scale}}})
            if not turned.ok then return turned end
        else
            if blocked>5 then return {ok=false,code="no_route_progress",message="本段多次未接近已知目标，需要重新判断路线"} end
            local best=nil
            local best_score=math.huge
            local best_confirmed=false
            for _,sample in ipairs(seen.near.ground_samples) do
                -- 连续缓坡的终点可以累计升高；跨台阶与碰撞限制由真实身体移动检查。
                if sample.state=="visible_surface" and sample.slope_degrees<35 then
                    local at=sample.position
                    local length=math.sqrt(at.x*at.x+at.z*at.z)
                    if length>0.55 then
                        local remaining=math.sqrt((p.x-at.x)^2+(p.z-at.z)^2)
                        local motion=seen.odometry
                        local mx=motion.position.x+motion.right.x*at.x+motion.forward.x*at.z
                        local mz=motion.position.z+motion.right.z*at.x+motion.forward.z*at.z
                        local key=math.floor(mx/0.75)..":"..math.floor(mz/0.75)
                        local score=remaining+math.abs(at.x)*0.03+(visited[key] or 0)*3
                        if blocked>0 then score-=math.abs(at.x)*0.5 end
                        -- 身体预判是选路线索；未确认的可见地面仍能有限试走，合法性由实际运动决定。
                        local confirmed=sample.path_clear==true
                        if not best or (confirmed and not best_confirmed) or (confirmed==best_confirmed and score<best_score) then
                            best=at best_score=score best_confirmed=confirmed
                        end
                    end
                end
            end
            if not best then return {ok=false,code="no_visible_step"} end
            local motion=seen.odometry
            local mx=motion.position.x+motion.right.x*best.x+motion.forward.x*best.z
            local mz=motion.position.z+motion.right.z*best.x+motion.forward.z*best.z
            local key=math.floor(mx/0.75)..":"..math.floor(mz/0.75)
            visited[key]=(visited[key] or 0)+1
            -- 路径采样可能在目标后方；最后一段在接近范围的近侧停下，避免穿过物品。
            local segment=math.sqrt(best.x*best.x+best.z*best.z)
            local stop_radius=math.max(0.1,(route and 1.6 or args.distance)-0.05)
            local projection=(p.x*best.x+p.z*best.z)/segment
            local perpendicular=p.x*p.x+p.z*p.z-projection*projection
            if perpendicular<stop_radius*stop_radius then
                local entry=projection-math.sqrt(math.max(0,stop_radius*stop_radius-perpendicular))
                if entry>0 and entry+0.25<segment then
                    local scale=(entry+0.25)/segment
                    best={x=best.x*scale,y=best.y*scale,z=best.z*scale}
                end
            end
            local moved=world.request("approach",{object={observation_id=seen.observation_id,position=best},distance=0.25})
            if moved.ok then blocked=0 else
                blocked+=1
                -- 只用刚刚实际碰到的表面法线选择退开/侧移，不读取世界导航图。
                local contact=nil
                for _,hit in pairs(moved.touch_contacts or {}) do contact=hit break end
                if contact then
                    local n=contact.normal
                    local side=blocked%2==1 and 1 or -1
                    local escape={x=n.x*0.8+n.z*1.2*side,y=0,z=n.z*0.8-n.x*1.2*side}
                    local turned=world.request("look_toward",{target={observation_id=moved.selected_target.observation_id,position=escape}})
                    if not turned.ok then return turned end
                    local around=world.request("walk_options",{})
                    local next_step=nil
                    local cost=math.huge
                    local next_confirmed=false
                    for _,sample in ipairs(around.near.ground_samples) do
                        if sample.state=="visible_surface" and sample.slope_degrees<35 then
                            local q=sample.position
                            local candidate=math.abs(q.z-1.5)+math.abs(q.x)
                            local confirmed=sample.path_clear==true
                            if q.z>=0.75 and (not next_step or (confirmed and not next_confirmed) or (confirmed==next_confirmed and candidate<cost)) then
                                next_step=q cost=candidate next_confirmed=confirmed
                            end
                        end
                    end
                    if next_step then
                        world.request("approach",{object={observation_id=around.observation_id,position=next_step},distance=0.25})
                    end
                end
            end
        end
    end
    return {ok=false,code="route_step_budget"}
end
