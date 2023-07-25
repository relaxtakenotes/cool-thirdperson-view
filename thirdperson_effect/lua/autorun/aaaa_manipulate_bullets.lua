local mbs_enabled = CreateConVar("sv_nte_manipulate_bullet_source", "0", FCVAR_ARCHIVE, "Tries to modify the bullet source to come out of the actual gun and not your eyes.")

if SERVER then
	util.AddNetworkString("nte_bone_positions")

	net.Receive("nte_bone_positions", function(len, ply)
		local hand_pos = net.ReadVector()
		local vm_radius = math.Clamp(net.ReadFloat(), 0, 72)

		local max_distance = 72 * ply:GetModelScale()
		local distance = hand_pos:Distance(ply:GetShootPos())

		if distance > max_distance then
			hand_pos = hand_pos - ply:GetShootPos() * distance/max_distance
		end

		//print(distance/max_distance)

		ply.hand_pos = hand_pos
		ply.vm_radius = vm_radius
	end)
end

local running_other_hooks = false

hook.Add("EntityFireBullets", "aaaa_nte_manipulate_bullets", function(entity, data)
	if not mbs_enabled:GetBool() then return end
	if running_other_hooks then return end

	running_other_hooks = true
	hook.Run("EntityFireBullets", entity, data)
	running_other_hooks = false

	if not entity:IsPlayer() then return end

	//debugoverlay.Line(data.Src, data.Src + data.Dir * 1000, 5, Color(255, 0, 0), false)

	local offset = entity:EyePos() - entity.hand_pos - data.Dir:Angle():Up() * 2 - data.Dir:Angle():Forward() * entity.vm_radius * 0.75
	local src = data.Src - offset

	if not util.TraceLine({start = src, endpos = src, filter = entity}).StartSolid then
		data.Src = src
	end

	//debugoverlay.Line(data.Src, data.Src + data.Dir * 1000, 5, Color(0, 255, 0), false)

	return true
end)
