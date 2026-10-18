return function(args, context)
    local target = args.target
    local radius = args.distance or 2.5
    if type(target) ~= "string" or target == "" then
        return {ok=false, completed=false, code="target_required"}
    end
    if type(radius) ~= "number" or radius ~= radius or radius < 1 or radius > 5 then
        return {ok=false, completed=false, code="invalid_arrival_distance"}
    end
    local limit = args.max_segments or 40
    if type(limit) ~= "number" or limit % 1 ~= 0 or limit < 1 or limit > 60 then
        return {ok=false, code="invalid_segment_limit", message="每次分段上限须为1至60的整数"}
    end
    -- Resume at the actual body position with a fresh observation.
    -- Past host movement receipts affect bounded search, never current visibility
    -- or the coordinates of a new world operation.
    local segments, blocked = 0, 0
    local stagnant, progress_balance, failed_since_progress = 0, 0, 0
    local search_observations = 0
    local visited = {}
    local explored_edges = {}
    local pending_from
    local failed_routes = {}
    local route_heading
    local travelled, detour, outward = 0, 0, 0
    -- 仅返回最近几项摘要；完整观察和移动回执由宿主保存，避免超出返回容量。
    local observations, route = {}, {}
    local observation_count = 0
    local target_seen_this_call, changed_vantage = false, false
    local last_move, last_player, last_seen, destination_hint
    local function length(p)
        return math.sqrt(p.x*p.x + p.z*p.z)
    end
    local request_point
    local debug_choices={}
    local route_aim
    local route_error
    local route_started=false
    local anchors,frontiers={},{}
    local current_anchor
    local last_confirmed_position
    local history_gap_rebased=false
    local detour_goal
    local initial_distance
    local function cross(a,b) return a.x*b.z-a.z*b.x end
    local function dot(a,b) return a.x*b.x+a.z*b.z end
    local function destination(seen)
        local entry = seen.near.landmarks[target] or seen.known[target]
        local hint = entry and (entry.position or entry.approx_position)
        local m = seen.request_odometry
        -- Freeze a coarse clue in the request frame, so yaw quantization cannot
        -- invent progress or reverse the intended route. Current sightings win.
        -- This estimate is only for steering, never a ground or arrival proof.
        local error=entry and (entry.position and 0 or entry.position_error_per_axis_m or 5)
        if hint and (not route_aim or entry.visible_now==true or error<route_error) then
            local next_aim=request_point(m,hint)
            if route_started and route_aim and
                math.sqrt((next_aim.x-route_aim.x)^2+(next_aim.z-route_aim.z)^2)>0.25 then
                stagnant,progress_balance,failed_since_progress=0,0,0
                detour_goal=nil
            end
            route_aim = next_aim
            route_error=error
        end
        if not route_aim then return nil end
        local dx,dz = route_aim.x-m.position.x,route_aim.z-m.position.z
        return {x=dx*m.right.x+dz*m.right.z,y=route_aim.y-m.position.y,
            z=dx*m.forward.x+dz*m.forward.z}
    end
    local request_id = context.task_execution.request_id
    local imported_movements = 0
    request_point = function(m, p)
        assert(m and m.request_id==request_id, "request_odometry does not match this request")
        return {x=m.position.x+m.right.x*p.x+m.forward.x*p.z,
            y=m.position.y+m.right.y*p.x+(p.y or 0)+m.forward.y*p.z,
            z=m.position.z+m.right.z*p.x+m.forward.z*p.z}
    end
    local function distance(a,b)
        return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)
    end
    local stop_distance = 0.25
    local function horizontal(a,b)
        return math.sqrt((a.x-b.x)^2+(a.z-b.z)^2)
    end
    local function local_goal(m)
        if not route_aim then return nil end
        local dx,dz=route_aim.x-m.position.x,route_aim.z-m.position.z
        return {x=dx*m.right.x+dz*m.right.z,y=route_aim.y-m.position.y,
            z=dx*m.forward.x+dz*m.forward.z}
    end
    local function anchor(at,parent)
        if current_anchor and horizontal(anchors[current_anchor].at,at)<0.25 then return current_anchor end
        local selected
        for i,node in ipairs(anchors) do
            if horizontal(node.at,at)<0.25 then selected=i break end
        end
        if selected then return selected end
        local g=parent and anchors[parent].g+horizontal(anchors[parent].at,at) or 0
        table.insert(anchors,{at=at,parent=parent,g=g,scanned=false})
        return #anchors
    end
    local function sync_position(at)
        -- An interrupted/missing receipt cannot certify a return corridor.
        -- Keep cumulative actual travel, but start a new local search component.
        if last_confirmed_position and horizontal(at,last_confirmed_position)>0.25 then
            anchors,frontiers={},{}
            current_anchor=nil
            history_gap_rebased=true
        end
        if not current_anchor then current_anchor=anchor(at,nil) end
        last_confirmed_position=at
    end
    local function begin_move(frame,p)
        pending_from=frame.request_odometry.position
        sync_position(pending_from)
        if not route_started then
            route_aim=nil
            destination(frame)
            route_started=true
            initial_distance=length(local_goal(frame.request_odometry))
        end
    end
    local function finish_move(at)
        if pending_from and horizontal(pending_from,at)>0.1 then
            table.insert(explored_edges,{from=pending_from,to=at})
            table.insert(visited,at)
            current_anchor=anchor(at,current_anchor)
        end
        last_confirmed_position=at
        pending_from=nil
    end
    local function already_stood(at)
        for _,node in ipairs(anchors) do
            if horizontal(node.at,at)<0.35 then return true end
        end
        return false
    end
    local function frontier_reached(f)
        if already_stood(f.at) then return true end
        if f.target then
            for _,node in ipairs(anchors) do
                if horizontal(node.at,f.target)<=stop_distance+0.05 and math.abs(node.at.y-f.target.y)<=0.3 then return true end
            end
        end
        return false
    end
    local function select_frontier(at,cursor,deferred)
        cursor=cursor or current_anchor
        deferred=deferred or {}
        local chosen,score,hint,target_node,target_point
        for key,f in pairs(frontiers) do
            if frontier_reached(f) then frontiers[key]=nil else
                local h=horizontal(f.at,route_aim)
                local value=f.g+h
                if not deferred[key] and (not chosen or value<score-0.05 or (math.abs(value-score)<=0.05 and h<hint)) then
                    chosen,score,hint=key,value,h
                    target_node,target_point=f.parent,f.target or f.at
                end
            end
        end
        for i,node in ipairs(anchors) do
            if not node.scanned and not deferred["rescan/"..i] then
                local h=horizontal(node.at,route_aim)
                local value=node.g+h
                if not chosen or value<score-0.05 or (math.abs(value-score)<=0.05 and h<hint) then
                    chosen,score,hint="rescan/"..i,value,h
                    target_node,target_point=i,nil
                end
            end
        end
        if not chosen then return nil end
        if not target_point and horizontal(at,anchors[target_node].at)<0.45 then
            -- These four fresh views were taken at this actual nearby body
            -- position. This marks a search region, never a completed journey.
            anchors[target_node].scanned=true
            return select_frontier(at,cursor,deferred)
        end
        if target_node==cursor then return target_point or anchors[target_node].at,chosen,target_point or anchors[target_node].at end
        local ancestors={}
        local ancestor=cursor
        while ancestor do ancestors[ancestor]=true ancestor=anchors[ancestor].parent end
        local path={}
        ancestor=target_node
        while ancestor and not ancestors[ancestor] do
            table.insert(path,ancestor)
            ancestor=anchors[ancestor].parent
        end
        assert(ancestor,"Actual anchor tree must stay connected")
        local next_index=cursor~=ancestor and anchors[cursor].parent or path[#path]
        if not next_index then return target_point or anchors[target_node].at,chosen,target_point or anchors[target_node].at end
        -- A nearby old standing point only changes the planning cursor. The
        -- observed current body position is never replaced or moved here.
        if horizontal(at,anchors[next_index].at)<0.45 then
            return select_frontier(at,next_index,deferred)
        end
        return anchors[next_index].at,chosen,target_point or anchors[target_node].at
    end
    local function attempt(seen,p)
        return {from=seen.request_odometry.position,to=request_point(seen.request_odometry,p)}
    end
    local function record_progress(goal, displacement, ok, code)
        if not displacement or length(goal)<=0.05 then return end
        local after = {x=goal.x-displacement.x,z=goal.z-displacement.z}
        local gain = length(goal)-length(after)
        travelled += length(displacement)
        detour += math.max(0, length(displacement)-gain)
        outward += math.max(0, -gain)
        progress_balance += gain
        stagnant += 1
        if not ok and code~="cancelled" then failed_since_progress += 1 end
        if progress_balance>=0.75 then progress_balance, stagnant, failed_since_progress = 0, 0, 0 end
    end
    local function budget_exhausted()
        if not initial_distance then return false end
        local no_progress_limit=math.max(8,math.ceil(initial_distance*1.5))
        return stagnant>=no_progress_limit or detour>initial_distance*2+8 or outward>initial_distance+8
    end
    for _, call in ipairs(context.task_execution.calls) do
        if call.arguments and call.arguments.target==target then
            for _, movement in ipairs(call.movements or {}) do
                local m = movement.request_odometry
                if movement.evidence_complete and movement.observation_immediately_preceded and
                    m and m.request_id==request_id then
                    local point = movement.requested_target.position
                    local at = request_point(m,point)
                    -- This receipt is in its matching pre-move observation frame.
                    -- An attempted endpoint is not an actually visited position.
                    local reference=movement.references and movement.references[target]
                    local frame={request_odometry=m,near={landmarks={}},known={}}
                    if reference then frame.known[target]=reference end
                    if route_started then destination(frame) end
                    begin_move(frame,point)
                    local goal=local_goal(m)
                    finish_move(request_point(m,movement.standing_position.position))
                    imported_movements += 1
                    if not movement.ok and movement.code~="cancelled" then
                        table.insert(failed_routes,{from=m.position,to=at,
                            actual_end=request_point(m,movement.standing_position.position)})
                    end
                    local shift = movement.standing_position.position
                    if length(shift)>0.4 then
                        local endpoint = request_point(m,shift)
                        route_heading = {x=(endpoint.x-m.position.x)/length(shift),
                            z=(endpoint.z-m.position.z)/length(shift)}
                    end
                    if goal then record_progress(goal,movement.standing_position.position,movement.ok,movement.code) end
                end
            end
        end
    end
    local function same_failure(seen,point)
        local tried = attempt(seen,point)
        for _, old in ipairs(failed_routes) do
            -- Directed endpoints in one request frame; tolerance is smaller
            -- than ground sample spacing. Also reject retrying the remaining
            -- suffix from the actual stopped position to that same point.
            if distance(tried.to,old.to)<=0.25 and
                (distance(tried.from,old.from)<=0.25 or distance(tried.from,old.actual_end)<=0.25) then return true end
            if distance(tried.from,old.actual_end)<=0.25 then
                local a = {x=old.to.x-old.actual_end.x,y=old.to.y-old.actual_end.y,z=old.to.z-old.actual_end.z}
                local b = {x=tried.to.x-tried.from.x,y=tried.to.y-tried.from.y,z=tried.to.z-tried.from.z}
                local aa, bb = a.x*a.x+a.y*a.y+a.z*a.z, b.x*b.x+b.y*b.y+b.z*b.z
                local ab = a.x*b.x+a.y*b.y+a.z*b.z
                -- An endpoint shifted along the same narrow forward corridor
                -- still retries the suffix which actually stopped here.
                if aa>0.0001 and ab>0 and math.max(0,bb-ab*ab/aa)<=0.25^2 then return true end
            end
        end
        return false
    end
    local function stop(code, message)
        return {debug_choices=debug_choices,ok=false, completed=false, code=code, message=message,
            segments_this_call=segments, last_move=last_move,
            search_observations=search_observations, no_progress_segments=stagnant,
            progress_balance_m=progress_balance, failures_since_progress=failed_since_progress,
            travelled_m=travelled, detour_m=detour, outward_m=outward,
            imported_host_movements=imported_movements,
            route_history_gap_rebased=history_gap_rebased,
            observations=observations, route_this_call=route,
            destination=target, arrival_distance=radius, destination_hint=destination_hint,
            stopped_odometry=last_seen and last_seen.odometry,
            player_observation=last_player, observation_id=last_seen and last_seen.observation_id,
            resume_arguments={target=target, distance=radius, max_segments=limit}}
    end
    -- A resumed call must honour the cumulative receipts before observing or
    -- moving again; waiting for the player cannot postpone this bound.
    if budget_exhausted() then return stop("no_progress", "累计绕行或连续无进展已达到有限边界；停在实际位置，请提供路线线索。") end
    local function turn(seen, p)
        return world.request("look_toward", {target={observation_id=seen.observation_id,
            position={x=p.x,y=0,z=p.z}}})
    end
    local function see(operation)
        local seen = world.request(operation, {})
        last_seen = seen
        local current_target = seen.near and seen.near.landmarks[target]
        if current_target and current_target.visible_now and current_target.position then
            target_seen_this_call = true
        end
        observation_count += 1
        local entry = seen.near and seen.near.landmarks["person/player"]
        local visible = entry ~= nil and entry.visible_now == true and entry.position ~= nil
        observations[tostring(observation_count)] = {
            operation=operation, observation_id=seen.observation_id,
            segments_completed=segments, odometry=seen.odometry,
            player_visible=visible, player_position=visible and entry.position or nil,
            player_distance_m=visible and length(entry.position) or nil}
        observations[tostring(observation_count-6)] = nil
        return seen
    end
    local function player(seen)
        local entry = seen.near.landmarks["person/player"]
        if entry and entry.visible_now and entry.position then
            last_player = {observation_id=seen.observation_id, position=entry.position,
                visible_now=true, distance_m=length(entry.position)}
            return entry.position
        end
        last_player = {observation_id=seen.observation_id, visible_now=false}
        return nil
    end
    local function together(seen)
        local p = player(seen)
        if not p or length(p)>4 then return nil end
        local entry = seen.near.landmarks[target]
        if entry and entry.visible_now == true and entry.position then
            local q = entry.position
            local pd = math.sqrt((q.x-p.x)^2+(q.z-p.z)^2)
            if length(q)<=radius and pd<=radius then
                return {ok=true, completed=true, code="arrived_together", destination=target,
                    arrival_distance=radius, self_distance_m=length(q), player_distance_m=pd,
                    observation_id=seen.observation_id, target_position=q, player_position=p,
                    segments_this_call=segments, observations=observations, route_this_call=route}
            end
        end
        return nil
    end
    local function check_player()
        local seen = see("perceive")
        local p = player(seen)
        -- 旧位置只决定转头的方向，必须转头后重新目击才能算跟上。
        if not p then
            local remembered = seen.known["person/player"]
            local hint = remembered and (remembered.position or remembered.approx_position)
            if hint and length(hint)>0.05 then
                local r = turn(seen, hint)
                if not r.ok then return nil, r end
                seen = see("perceive")
                p = player(seen)
            end
        end
        for scan=1,4 do
            if p then break end
            local r = turn(seen, {x=3,z=0})
            if not r.ok then return nil, r end
            seen = see("perceive")
            p = player(seen)
        end
        -- 不靠移动来等人；有限观察后仍未跟上就交回现场等候。
        for observation=1,3 do
            if p and length(p)<=4 then return seen end
            seen = see("perceive")
            p = player(seen)
        end
        if p and length(p)<=4 then return seen end
        return nil
    end
    -- 观察朝向最多偏离当前玩家方向75度，给80度半视角留出余量。
    -- 这只是选择朝向，转身后的实际可见性必须再次确认。
    local turn_side
    local function shared_heading(p, goal)
        local a = math.atan2(p.x, p.z)
        local b = math.atan2(goal.x, goal.z)
        local delta = math.atan2(math.sin(b-a), math.cos(b-a))
        -- 玩家在身后时固定绕行侧，避免微小角度变化使下一段反向折返。
        if math.abs(delta)>math.rad(150) then
            turn_side = turn_side or (delta>=0 and 1 or -1)
            delta = turn_side*math.abs(delta)
        else
            turn_side = delta>=0 and 1 or -1
        end
        -- 平分玩家与道路的夹角，减少移动后玩家滑出视野的情况。
        local angle = a + math.clamp(delta/2, -math.rad(75), math.rad(75))
        return {x=3*math.sin(angle),z=3*math.cos(angle)}
    end
    local function safe_options()
        local seen = see("walk_options")
        local p = player(seen)
        if p and length(p)<=4 then return seen end
        -- 任一新观察丢失玩家就停止选路，原地寻找并等候。
        local found, failure = check_player()
        if not found then return nil, failure end
        seen = see("walk_options")
        p = player(seen)
        if p and length(p)<=4 then return seen end
        return nil
    end
    local function leaves_blind_spot(seen,goal,q)
        local view=seen.near.view
        local minimum=math.abs(goal.y-view.eye.y)/math.tan(math.rad(view.half_angle_degrees))
        -- The endpoint may stop this far short. Require the whole stopping
        -- region to leave the near vertical blind spot, then observe again.
        return length(q)>math.max(minimum,length(goal))+stop_distance+0.04
    end
    local function change_vantage()
        if budget_exhausted() then return nil, {code="no_progress"} end
        if segments>=limit then return nil, {code="segment_budget"} end
        local seen, failure = safe_options()
        if not seen then return nil, failure end
        local p, goal = player(seen), destination(seen)
        if not goal then return nil, {code="target_unconfirmed"} end
        local best, score
        for _, sample in ipairs(seen.near.ground_samples) do
            if sample.state=="visible_surface" and sample.slope_degrees<35 and sample.path_clear then
                local step = sample.position
                local d = length(step)
                local q = {x=goal.x-step.x,z=goal.z-step.z}
                local peer = {x=p.x-step.x,z=p.z-step.z}
                -- Move away from the blind spot, using actual visible ground.
                -- A lateral view can expose both people and the nearby target.
                if d>=0.65 and d<=1.5 and length(q)>=0.5 and length(q)<=radius and
                    length(peer)>0.05 and leaves_blind_spot(seen,goal,q) then
                    local angle_score = math.abs((q.x*peer.x+q.z*peer.z)/(length(q)*length(peer)))+d*0.05
                    if not best or angle_score<score then best=step score=angle_score end
                end
            end
        end
        if not best then return nil, {code="no_visible_vantage"} end
        changed_vantage = true
        begin_move(seen,best)
        goal=destination(seen)
        if budget_exhausted() then return nil, {code="no_progress"} end
        last_move = world.request("approach", {object={observation_id=seen.observation_id,position=best},distance=stop_distance,keep_heading=true})
        if last_move.standing_position then
            finish_move(request_point(seen.request_odometry,last_move.standing_position.position))
        end
        record_progress(goal,last_move.standing_position and last_move.standing_position.position,last_move.ok,last_move.code)
        segments += 1
        route[tostring(segments)] = {from_odometry=seen.odometry,receipt=last_move}
        route[tostring(segments-4)] = nil
        if budget_exhausted() then return nil, {code="no_progress"} end
        if not last_move.ok then return nil, last_move end
        local after
        after, failure = check_player()
        route[tostring(segments)].after_odometry = last_seen and last_seen.odometry
        if not after then return nil, failure or {code="waiting_for_player"} end
        goal = destination(after)
        if not goal then return nil, {code="target_unconfirmed"} end
        local turned = turn(after, shared_heading(player(after),goal))
        if not turned.ok then return nil, turned end
        after = see("perceive")
        p = player(after)
        if not p or length(p)>4 then return nil, {code="waiting_for_player"} end
        return after
    end
    local following, failure
    for step=1,limit do
        if segments>=limit then return stop("segment_budget", "本轮有限步数已耗尽，仍未核实共同抵达。") end
        -- 上段结束后已观察；没有新世界操作时沿用同一最新回执。
        if not following then following, failure = check_player() end
        if not following then
            if failure then return stop(failure.code, "转身观察受阻，已停下，尚未共同到达。") end
            return stop("waiting_for_player", "我停在这里等你；请跟上并进入我的视野，再从这里继续去指定目标。尚未共同到达。")
        end
        local done = together(following)
        if done then return done end
        local seen = following
        local goal = destination(seen)
        if not goal then return stop("unknown_target_location", "没有可用的指定目标位置线索，尚未到达。") end
        -- At the remembered area, inspect without walking around an obsolete point.
        -- A turn is only a search direction; each result must actually show the target.
        if not seen.near.landmarks[target] and length(goal)<=math.max(radius, 3) then
            local found = false
            for scan=1,4 do
                local r = turn(seen, scan==1 and goal or {x=3,z=0})
                if not r.ok then return stop(r.code, "原地核查目标受阻，已停下。") end
                seen = see("perceive")
                search_observations += 1
                local entry = seen.near.landmarks[target]
                if entry and entry.visible_now and entry.position then found=true break end
            end
            if not found and target_seen_this_call and not changed_vantage then
                local view = seen.near.view
                -- Pure yaw cannot expose a point directly below the eye.
                -- This call must have actually seen the target before the blind spot.
                if math.abs(goal.y-view.eye.y)>length(goal)*math.tan(math.rad(view.half_angle_degrees)) then
                    seen, failure = change_vantage()
                    if not seen then return stop(failure and failure.code or "waiting_for_player", "换观察位置未能完成，已保留现场并停止。") end
                    local entry = seen.near.landmarks[target]
                    found = entry and entry.visible_now and entry.position
                    local arrived = together(seen)
                    if arrived then return arrived end
                end
            end
            if not found then
                return stop("target_not_found", "已到最后所知区域并有限核查，仍未找到目标；停止接近旧位置，等待新线索。")
            end
            seen, failure = check_player()
            if not seen then return stop("waiting_for_player", "核查目标后未确认你跟上，原地等候。") end
            goal = destination(seen)
            if not goal then return stop("target_not_found", "核查后没有有效目标线索，已停止。") end
        end
        -- Examine the existing view first. A useful visible step needs no turn.
        seen, failure = safe_options()
        if not seen then
            return stop(failure and failure.code or "waiting_for_player", "当前观察未确认你跟上，已原地停等。")
        end
        goal = destination(seen)
        done = together(seen)
        if done then return done end
        if not goal then return stop("target_unconfirmed", "重新观察后未能定位指定目标，尚未到达。") end
        destination_hint = {observation_id=seen.observation_id, position=goal,
            meaning="仅为本次寻路线索；续办必须重新观察，不作为抵达证明"}
        sync_position(seen.request_odometry.position)
        local views={}
        local rays={}
        local function add_options(frame)
            table.insert(views,frame)
            for _,sample in ipairs(frame.near.ground_samples) do
                if sample.state=="visible_surface" and sample.slope_degrees<35 and sample.path_clear then
                    local p=sample.position
                    local d=length(p)
                    local scale=d>0 and math.max(0,1-stop_distance/d) or 0
                    if d>0.65 and d<=5.5 and not same_failure(frame,p) then
                        local at=request_point(frame.request_odometry,{x=p.x*scale,y=p.y,z=p.z*scale})
                        local target_point=request_point(frame.request_odometry,p)
                        local dx,dz=target_point.x-frame.request_odometry.position.x,target_point.z-frame.request_odometry.position.z
                        local bearing=math.floor(math.atan2(dx,dz)/math.rad(10)+0.5)
                        local old=rays[bearing]
                        if not old or d>old.distance then
                            local g=anchors[current_anchor].g+horizontal(anchors[current_anchor].at,at)
                            rays[bearing]={at=at,target=target_point,parent=current_anchor,g=g,distance=d}
                        end
                    end
                end
            end
        end
        local function choose(frame,aim_point)
            local m=frame.request_odometry
            local dx,dz=aim_point.x-m.position.x,aim_point.z-m.position.z
            local aim={x=dx*m.right.x+dz*m.right.z,z=dx*m.forward.x+dz*m.forward.z}
            local peer=player(frame)
            local point,score
            for _,sample in ipairs(frame.near.ground_samples) do
                if sample.state=="visible_surface" and sample.slope_degrees<35 and sample.path_clear then
                    local p=sample.position
                    local d=length(p)
                    local scale=d>0 and math.max(0,1-stop_distance/d) or 0
                    local remaining=length({x=aim.x-p.x*scale,z=aim.z-p.z*scale})
                    local peer_after={x=peer.x-p.x*scale,z=peer.z-p.z*scale}
                    if d>0.65 and d<=2.4 and length(peer_after)<=4.8 and
                        remaining<length(aim)-0.15 and not same_failure(frame,p) and (not point or remaining<score) then
                        point,score=p,remaining
                    end
                end
            end
            return point,score
        end
        local function visible_choice(aim_point)
            local best,best_score,best_heading
            for _,frame in ipairs(views) do
                local point,score=choose(frame,aim_point)
                if point and (not best or score<best_score) then
                    best,best_score,best_heading=point,score,frame.request_odometry.forward
                end
            end
            return best,best_score,best_heading
        end
        local function actual_best(frame)
            local result=horizontal(frame.request_odometry.position,route_aim)
            for _,at in ipairs(visited) do result=math.min(result,horizontal(at,route_aim)) end
            for _,node in ipairs(anchors) do result=math.min(result,horizontal(node.at,route_aim)) end
            return result
        end
        local function fast_choice(frame)
            local point,score=choose(frame,route_aim)
            if point and score<actual_best(frame)-0.15 then
                return point,score,route_aim,"new_actual_progress"
            end
            if detour_goal and horizontal(frame.request_odometry.position,detour_goal)>stop_distance+0.1 then
                point,score=choose(frame,detour_goal)
                if point then return point,score,detour_goal,"observed_detour" end
            end
            return nil
        end
        local best,best_score,best_heading
        local waypoint,frontier_key
        local used_fast_view,scan_complete=false,false
        for scan=1,4 do
            local current_player=player(seen)
            if not current_player or length(current_player)>4 then
                return stop("waiting_for_player","选路前未确认你跟上，已停止。")
            end
            add_options(seen)
            -- Only the current fresh view may skip the rest of the scan.
            -- A partial scan never reaches old-frontier/rescan selection.
            if scan<=2 then
                best,best_score,waypoint,frontier_key=fast_choice(seen)
                if best then
                    best_heading=seen.request_odometry.forward
                    used_fast_view=true
                    if frontier_key=="new_actual_progress" then detour_goal=nil end
                    break
                end
            end
            if scan==4 then scan_complete=true break end
            local direction
            if scan==1 then direction=shared_heading(current_player,goal) else
                local a=math.atan2(current_player.x,current_player.z)+math.rad(scan==2 and -65 or 65)
                direction={x=3*math.sin(a),z=3*math.cos(a)}
            end
            local turned=turn(seen,direction)
            if not turned.ok then return stop(turned.code,"原地查看分支受阻。") end
            seen,failure=safe_options()
            if not seen then return stop("waiting_for_player","查看分支时未确认你跟上，已停止。") end
            goal=destination(seen)
        end
        -- Internal visible cells already have an observation. Explore the far
        -- end of each observed clear ray, rather than walking on every sample.
        -- Planning may use the full visible range; every actual step below is
        -- still <=2.4m and freshly checks the player's distance and ground.
        for _,f in pairs(rays) do
            if not frontier_reached(f) then
                local key=tostring(current_anchor).."/"..math.floor(f.at.x/0.75+0.5).."/"..math.floor(f.at.z/0.75+0.5)
                local old=frontiers[key]
                if not old or f.g<old.g then frontiers[key]=f end
            end
        end
        if scan_complete then anchors[current_anchor].scanned=true end
        if not used_fast_view then
            local best_actual=actual_best(seen)
            best,best_score,best_heading=visible_choice(route_aim)
            if best and best_score<best_actual-0.15 then
                -- A fresh clear step beyond all actual previous progress is useful
                -- immediately. Search expansion is a fallback at an obstacle, not
                -- a reason to return to cheaper but less advanced old viewpoints.
                waypoint,frontier_key=route_aim,"new_actual_progress"
                detour_goal=nil
            else best,best_score,best_heading=nil,nil,nil end
            if not best and detour_goal then
                if horizontal(seen.request_odometry.position,detour_goal)>stop_distance+0.1 then
                    best,best_score,best_heading=visible_choice(detour_goal)
                    if best then waypoint,frontier_key=detour_goal,"observed_detour" else detour_goal=nil end
                else detour_goal=nil end
            end
            if not best then
                local origin=seen.request_odometry.position
                local gx,gz=route_aim.x-origin.x,route_aim.z-origin.z
                local gd=math.sqrt(gx*gx+gz*gz)
                local selected,selected_tier,selected_alignment,selected_heading
                for _,f in pairs(rays) do
                    if f.distance>2.4 and not frontier_reached(f) then
                        local dx,dz=f.target.x-origin.x,f.target.z-origin.z
                        local d=math.sqrt(dx*dx+dz*dz)
                        local alignment=(dx*gx+dz*gz)/(d*gd)
                        local continuity=route_heading and (dx*route_heading.x+dz*route_heading.z)/d or 0
                        local tier=0
                        -- This only ranks exploration. Past endpoint chords never
                        -- grant permission or permanently close a possible branch.
                        for _,edge in ipairs(explored_edges) do
                            local ex,ez=edge.to.x-edge.from.x,edge.to.z-edge.from.z
                            local square=ex*ex+ez*ez
                            if square>0.01 then
                                local t=((f.target.x-edge.from.x)*ex+(f.target.z-edge.from.z)*ez)/square
                                if t>=0 and t<=1 and horizontal(f.target,{x=edge.from.x+t*ex,z=edge.from.z+t*ez})<0.65 then tier=1 break end
                            end
                        end
                        local point,score,heading=visible_choice(f.target)
                        if point and (not selected or tier<selected_tier or (tier==selected_tier and
                            (alignment>selected_alignment+0.02 or (math.abs(alignment-selected_alignment)<=0.02 and continuity>selected_heading)))) then
                            selected,selected_tier,selected_alignment,selected_heading=f,tier,alignment,continuity
                            best,best_score,best_heading=point,score,heading
                        end
                    end
                end
                if selected then detour_goal=selected.target;waypoint,frontier_key=detour_goal,"new_observed_detour" end
            end
            local deferred={}
            for alternative=1,64 do
                if best then break end
                local local_target
                waypoint,frontier_key,local_target=select_frontier(seen.request_odometry.position,nil,deferred)
                if not waypoint then break end
                -- Newly observed clear ground can connect to a nearby old branch.
                -- This shortcut uses the same fresh permission as every movement;
                -- the old tree never forces an otherwise unnecessary return.
                if local_target then
                    best,best_score,best_heading=visible_choice(local_target)
                    if best then waypoint=local_target end
                end
                if not best then best,best_score,best_heading=visible_choice(waypoint) end
                if best then break end
                -- A currently blocked return edge does not disprove all branches.
                -- Defer only this plan in this observation, then try a different one.
                deferred[frontier_key]=true
            end
        end
        if not best then return stop("route_segment_unobserved","有限核对当前候选后，仍未确认可走短段；停在实际位置，请提供路线线索。") end
        local m=seen.request_odometry
        local facing={x=3*(best_heading.x*m.right.x+best_heading.z*m.right.z),z=3*(best_heading.x*m.forward.x+best_heading.z*m.forward.z)}
        -- A fast choice belongs to this exact current frame: no turn or world
        -- request may stale it before the final same-frame reselect below.
        if not used_fast_view and facing.z<2.99 then
            local turned=turn(seen,facing)
            if not turned.ok then return stop(turned.code,"转回当前通道受阻。") end
            seen,failure=safe_options()
            if not seen then return stop("waiting_for_player","转回通道后未确认你跟上，原地等候。") end
        end
        best,best_score=choose(seen,waypoint)
        goal=destination(seen)
        if not best or not goal then return stop("route_segment_unobserved","最新观察未确认计划短段可走，保留实际位置。") end
        if segments>=limit then return stop("segment_budget", "本轮有限步数已耗尽，仍未核实共同抵达。") end
        -- 普通行进位移入口：所用地面和玩家必须属于同一最新观察。
        local current_player = player(seen)
        if seen~=last_seen or not current_player or length(current_player)>4 then
            return stop("waiting_for_player", "最新观察未确认你跟上，已停止前进。")
        end
        if segments>=30 then debug_choices[tostring(segments+1)]={position=seen.request_odometry.position,route_aim=route_aim,waypoint=waypoint,frontier=frontier_key,fast=used_fast_view,best=best,score=best_score,history_best=actual_best(seen),detour_goal=detour_goal,stagnant=stagnant} end
        local attempted = attempt(seen,best)
        begin_move(seen,best)
        goal=destination(seen)
        if budget_exhausted() then return stop("no_progress", "累计绕行或连续无进展已达到有限边界；停在实际位置，请提供路线线索。") end
        last_move = world.request("approach", {object={observation_id=seen.observation_id,position=best},distance=stop_distance,keep_heading=true})
        if last_move.standing_position then
            finish_move(request_point(seen.request_odometry,last_move.standing_position.position))
        end
        segments += 1
        route[tostring(segments)] = {from_odometry=seen.odometry, receipt=last_move}
        route[tostring(segments-4)] = nil
        if not last_move.ok then
            attempted.actual_end = last_move.standing_position and
                request_point(seen.request_odometry,last_move.standing_position.position) or attempted.from
            table.insert(failed_routes,attempted)
        end
        -- Measure actual forward displacement; coarse recalled target bins are
        -- not suitable for deciding whether successive steps made progress.
        local displacement = last_move.standing_position and last_move.standing_position.position
        if displacement and length(displacement)>0.4 then
            local endpoint = request_point(seen.request_odometry,displacement)
            local start = seen.request_odometry.position
            local d = length(displacement)
            route_heading = {x=(endpoint.x-start.x)/d,z=(endpoint.z-start.z)/d}
        end
        record_progress(goal,displacement,last_move.ok,last_move.code)
        if budget_exhausted() then return stop("no_progress", "累计绕行或连续无进展已达到有限边界；停在实际位置，请提供路线线索。") end
        -- 包括失败后的实际位移，都先核实玩家；不直接追加绕行动作。
        local after, after_failure = check_player()
        route[tostring(segments)].after_odometry = last_seen and last_seen.odometry
        if not after then
            if after_failure then return stop(after_failure.code, "移动后观察受阻，已停下。") end
            return stop("waiting_for_player", "我已停下等你跟上；尚未共同到达指定目标，下次从这里继续。")
        end
        done = together(after)
        if done then return done end
        following = after
        if last_move.ok then blocked=0 else blocked+=1 end
        if blocked>=3 then return stop("route_blocked", "连续三个短段尝试仍受阻，保留当前位置，尚未到达。") end
    end
    return stop("segment_budget", "本轮已走完有限短段；尚未确认共同到达，下次从实际位置继续。")
end
