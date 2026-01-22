-- Copyright © Platunov I. M., 2020 All rights reserved
local time = CurTime()
local EyePos = debug.getregistry().Entity.EyePos
local GetPos = debug.getregistry().Entity.GetPos
local IsInWorld = debug.getregistry().Entity.IsInWorld
local BoundingRadius = debug.getregistry().Entity.BoundingRadius
local WorldSpaceCenter = debug.getregistry().Entity.WorldSpaceCenter
local Angle = debug.getregistry().Vector.Angle
local DistToSqr = debug.getregistry().Vector.DistToSqr
local function NormalizeSegments(segments)
	local i = 1
	while true do
		local s1 = segments[i]
		if not s1 then break end
		local j = 1
		while true do
			if i == j then
				j = j + 1
				continue
			end

			local s2 = segments[j]
			if not s2 then break end
			local remove = false
			if s2[1] < s1[1] and s2[2] >= s1[1] then
				s1[1] = s2[1]
				remove = true
			end

			if s2[2] > s1[2] and s2[1] <= s1[2] then
				s1[2] = s2[2]
				remove = true
			end

			if s2[1] >= s1[1] and s2[2] <= s1[2] then remove = true end
			if remove then
				table.remove(segments, j)
				j = 1
			else
				j = j + 1
			end
		end

		i = i + 1
	end

	table.sort(segments, function(a, b) return a[1] < b[1] end)
end

local function SubtractSegments(segments1, segments2)
	local i = 1
	while true do
		local s1 = segments1[i]
		if not s1 then break end
		for j = 1, #segments2 do
			local s2 = segments2[j]
			if s2[1] >= s1[1] and s2[2] <= s1[2] then
				if s2[2] < s1[2] then table.insert(segments1, i + 1, {s2[2], s1[2]}) end
				s1[2] = s2[1]
			else
				if s2[2] > s1[1] and s2[1] <= s1[1] then
					s1[1] = s2[2]
				elseif s2[1] < s1[2] and s2[2] >= s1[2] then
					s1[2] = s2[1]
				end
			end

			if s1[2] - s1[1] <= 0 then break end
		end

		if s1[2] - s1[1] <= 0 then
			table.remove(segments1, i)
		else
			i = i + 1
		end
	end
end

local function PrepareSpawnSegments(spawnsegments, nospawnsegments)
	if #spawnsegments == 0 then return nospawnsegments end
	NormalizeSegments(spawnsegments)
	if #nospawnsegments == 0 then return spawnsegments end
	NormalizeSegments(nospawnsegments)
	SubtractSegments(spawnsegments, nospawnsegments)
end

local function findAllVehicleEntities()
	local isVehicle = isVehicle or {}
	for _, ent in ipairs(ents.Iterator()) do
		if ent:IsVehicle() then table.insert(isVehicle, ent) end
	end
	return isVehicle
end

local function dontSpawnInSpecifiedEntitiesList(ent)
	if Trolleybus_System.AvoidSpawnInEntClass then return Trolleybus_System.AvoidSpawnInEntClass[ent] end
	return false
end

local function constructEntitiesToAvoid()
	local entities = entities or {}
	for _, ent in ipairs(ents.Iterator()) do
		if dontSpawnInSpecifiedEntitiesList(ent) then table.insert(entities, ent) end
	end
	return entities
end

local function getVehiclePositionsAndRadii()
	local vehPos = {}
	local vehRad = {}
	local busPos = {}
	local busRad = {}
	local oVehPos = {}
	local oVehRad = {}
	local entPos = {}
	local entRad = {}
	local finalPos = {}
	local finalRad = {}
	for j = 1, #vehicles do -- get trolleybus AI card
		vehPos[j] = WorldSpaceCenter(vehicles[j])
		vehRad[j] = BoundingRadius(vehicles[j])
	end

	local tbuses = ents.FindByClass("trolleybus_ent_*") -- get trolleybus entities
	for j = 1, #tbuses do
		busPos[busPos] = WorldSpaceCenter(tbuses[j])
		busRad[busRad] = BoundingRadius(tbuses[j])
	end

	for j = 1, #otherVehicles do -- get regular vehicle entities
		oVehPos[j] = WorldSpaceCenter(otherVehicles[j])
		oVehRad[j] = BoundingRadius(otherVehicles[j])
	end

	for j = 1, #avoidEntities do -- get any manually registered entities
		entPos[j] = WorldSpaceCenter(otherVehicles[j])
		entRad[j] = BoundingRadius(otherVehicles[j])
	end

	table.Merge(finalPos, vehPos)
	table.Merge(finalPos, busPos)
	table.Merge(finalPos, oVehPos)
	table.Merge(finalPos, entPos)
	table.Merge(finalRad, vehRad)
	table.Merge(finalRad, busRad)
	table.Merge(finalRad, oVehRad)
	table.Merge(finalRad, entRad)
end

hook.Add("Think", "Trolleybus_System_Traffic", function()
	if CurTime() - time < 60 / Trolleybus_System.GetAdminSetting("trolleybus_traffic_updaterate") then return end
	time = CurTime()
	if not next(Trolleybus_System.TrafficVehiclesTypes) then return end
	local plys = player.GetAll()
	local vehicles = ents.FindByClass("trolleybus_traffic_car")
	local otherVehicles = findAllVehicleEntities()
	local avoidEntities = constructEntitiesToAvoid()
	local SPAWN_DISTANCE_MAX = Trolleybus_System.GetAdminSetting("trolleybus_traffic_distancemax")
	local SPAWN_DISTANCE_MIN = Trolleybus_System.GetAdminSetting("trolleybus_traffic_distancemin")
	local VEHICLE_LIMIT_PER_PLAYER = Trolleybus_System.GetAdminSetting("trolleybus_traffic_player_limit")
	local VEHICLE_LIMIT = Trolleybus_System.GetAdminSetting("trolleybus_traffic_limit")
	local SPAWNS_PER_UPDATE = Trolleybus_System.GetAdminSetting("trolleybus_traffic_spawns_per_second")
	local plys_eyepos = {}
	local plys_inworld = {}
	local plys_vehcount = {}
	local veh_pos = {}
	local oVeh_pos = {}
	for i = 1, #plys do
		local ply = plys[i]
		plys_eyepos[i] = EyePos(ply)
		plys_inworld[i] = IsInWorld(ply)
	end

	for i = 1, #vehicles do
		veh_pos[i] = GetPos(vehicles[i])
	end

	for i = 1, #otherVehicles do
		oVeh_pos[i] = GetPos(vehicles[i])
	end

	if Trolleybus_System.GetAdminSetting("trolleybus_traffic_enable") and #vehicles < VEHICLE_LIMIT and #vehicles < VEHICLE_LIMIT_PER_PLAYER * #plys then
		local add = {}
		for k, v in pairs(Trolleybus_System.GetTrafficTracks()) do
			local chance = v.SpawnChance or 100
			if math.random() * 100 >= chance then continue end
			local dist = DistToSqr(v.End, v.Start)
			local ang = Angle(v.End - v.Start)
			local length = math.sqrt(dist)
			local spawnsegments, nospawnsegments = {}, {}
			for i = 1, #plys do
				if not plys_inworld[i] then continue end
				local eye = plys_eyepos[i]
				if not plys_vehcount[i] then
					local count = 0
					for j = 1, #vehicles do
						if DistToSqr(veh_pos[j], eye) <= SPAWN_DISTANCE_MAX * SPAWN_DISTANCE_MAX then count = count + 1 end
					end

					plys_vehcount[i] = count
				end

				local p = WorldToLocal(eye, angle_zero, v.Start, ang)
				local d = p.y * p.y + p.z * p.z
				if plys_vehcount[i] >= VEHICLE_LIMIT_PER_PLAYER then
					if d <= SPAWN_DISTANCE_MAX * SPAWN_DISTANCE_MAX then -- no spawn inside sphere with max radius
						local maxlen = math.sqrt(SPAWN_DISTANCE_MAX * SPAWN_DISTANCE_MAX - d)
						local from = math.Clamp(p.x - maxlen, 0, length)
						local to = math.Clamp(p.x + maxlen, 0, length)
						local tlen = to - from
						if tlen > 0 then nospawnsegments[#nospawnsegments + 1] = {from, to} end
					end
				else
					if d <= SPAWN_DISTANCE_MAX * SPAWN_DISTANCE_MAX then -- spawn inside sphere with max radius
						local maxlen = math.sqrt(SPAWN_DISTANCE_MAX * SPAWN_DISTANCE_MAX - d)
						local from = math.Clamp(p.x - maxlen, 0, length)
						local to = math.Clamp(p.x + maxlen, 0, length)
						local tlen = to - from
						if tlen > 0 then spawnsegments[#spawnsegments + 1] = {from, to} end
					end

					if d <= SPAWN_DISTANCE_MIN * SPAWN_DISTANCE_MIN then -- no spawn inside sphere with min radius
						local maxlen = math.sqrt(SPAWN_DISTANCE_MIN * SPAWN_DISTANCE_MIN - d)
						local from = math.Clamp(p.x - maxlen, 0, length)
						local to = math.Clamp(p.x + maxlen, 0, length)
						local tlen = to - from
						if tlen > 0 then nospawnsegments[#nospawnsegments + 1] = {from, to} end
					end
				end
			end

			PrepareSpawnSegments(spawnsegments, nospawnsegments)
			add[k] = spawnsegments
		end

		local allveh_pos, allveh_radius
		local new_vehs
		for i = 1, math.min(SPAWNS_PER_UPDATE, VEHICLE_LIMIT - #vehicles) do
			local selected, weights = {}, 0
			for trackid, spawnsegments in pairs(add) do
				local track = Trolleybus_System.GetTrafficTracks()[trackid]
				local dist = DistToSqr(track.End, track.Start)
				local ang = Angle(track.End - track.Start)
				local length = math.sqrt(dist)
				local nospawnsegments = {}
				if not allveh_pos then
					allveh_pos = {}
					allveh_radius = {}
					getVehiclePositionsAndRadii() -- patch in new function to construct a list of all trolleybusses, trolleybus AI, and custom entities
				end

				for j = 1, #allveh_pos do
					local pos = allveh_pos[j]
					local dist = allveh_radius[j] + 500 -- add new vehicle's average radius
					local p = WorldToLocal(pos, angle_zero, track.Start, ang)
					local d = p.y * p.y + p.z * p.z
					if d <= dist * dist then -- no spawn inside sphere with another vehicle's bounding radius
						local maxlen = math.sqrt(dist * dist - d)
						local from = math.Clamp(p.x - maxlen, 0, length)
						local to = math.Clamp(p.x + maxlen, 0, length)
						local tlen = to - from
						if tlen > 0 then nospawnsegments[#nospawnsegments + 1] = {from, to} end
					end
				end

				PrepareSpawnSegments(spawnsegments, nospawnsegments)
				for j = 1, #spawnsegments do
					local from, to = spawnsegments[j][1], spawnsegments[j][2]
					selected[#selected + 1] = {trackid, to - from, from, to}
					weights = weights + to - from
				end
			end

			local rand = math.random() * weights
			for j = 1, #selected do
				local dt = selected[j]
				rand = rand - dt[2]
				if rand < 0 then
					local track = Trolleybus_System.GetTrafficTracks()[dt[1]]
					local ang = Angle(track.End - track.Start)
					local ent = ents.Create("trolleybus_traffic_car")
					ent.CurTrack = dt[1]
					ent:SetupVehicleClass()
					ent:SelectNextTrack()
					ent:SetPos(track.Start + ang:Forward() * math.Rand(dt[3], dt[4]) + ang:Up() * ent:GetVehicleData().SpawnHeightOffset)
					ent:SetAngles(ang)
					ent:Spawn()
					new_vehs = new_vehs or {}
					new_vehs[#new_vehs + 1] = ent
					allveh_pos[#allveh_pos + 1] = WorldSpaceCenter(ent)
					allveh_radius[#allveh_radius + 1] = BoundingRadius(ent)
					break
				end
			end
		end

		if new_vehs then
			for i = 1, #new_vehs do
				local ent = new_vehs[i]
				ent:SetupJamTrace()
				local track = Trolleybus_System.GetTrafficTracks()[ent.CurTrack]
				local speed = ent:GetAllowedSpeed(track.End)
				ent:GetPhysicsObject():SetVelocity((track.End - track.Start):GetNormalized() * speed)
				for k, v in ipairs(ent.Wheels) do
					for k, v in ipairs(v.Wheels) do
						v:GetPhysicsObject():SetVelocity(ent:GetPhysicsObject():GetVelocity())
						v:SetRotationSpeed(v:MovementSpeedToRotationSpeed(speed))
					end
				end
			end
		end
	end

	for i = 1, #vehicles do
		local veh = vehicles[i]
		local remove = true
		for j = 1, #plys do
			if DistToSqr(plys_eyepos[j], veh_pos[i]) <= SPAWN_DISTANCE_MAX ^ 2 then
				remove = false
				break
			end
		end

		if remove then veh:Remove() end
	end
end)