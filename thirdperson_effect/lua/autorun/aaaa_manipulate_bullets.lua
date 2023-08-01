local mbs_enabled = CreateConVar("sv_nte_manipulate_bullet_source", "0", FCVAR_ARCHIVE, "Tries to modify the bullet source to come out of the actual gun and not your eyes.")
local mbs_vischeck = CreateConVar("sv_nte_mbs_vischeck", "0", FCVAR_ARCHIVE, "Performs a check to prevent cheaters shooting out of thin walls. Can cause issues with some weapons.")

if SERVER then
	util.AddNetworkString("nte_bone_positions")

	net.Receive("nte_bone_positions", function(len, ply)
		local hand_pos = net.ReadVector()
		local vm_radius = math.Clamp(net.ReadFloat(), 0, 72)
		local active = net.ReadBool()

		ply.head_pos = ply:GetBoneMatrix(ply:LookupBone("ValveBiped.Bip01_Head1")):GetTranslation()

		local max_distance = 72 * ply:GetModelScale()
		local distance = hand_pos:Distance(ply.head_pos)

		if distance > max_distance then
			active = false
		end

		ply.hand_pos = hand_pos
		ply.vm_radius = vm_radius

		if not active then
			ply.head_pos = nil
			ply.hand_pos = nil
			ply.vm_radius = nil
		end
	end)
end

local running_other_hooks = false

hook.Add("EntityFireBullets", "aaaa_nte_manipulate_bullets", function(entity, data)
	if not mbs_enabled:GetBool() or not entity.hand_pos or not entity.vm_radius or not entity.head_pos then return end
	if running_other_hooks then return end

	running_other_hooks = true
	hook.Run("EntityFireBullets", entity, data)
	running_other_hooks = false

	if not entity:IsPlayer() then return end

	debugoverlay.Line(data.Src, data.Src + data.Dir * 1000, 5, Color(255, 0, 0), false)

	local offset = entity:EyePos() - entity.hand_pos - data.Dir:Angle():Up() * 2 - data.Dir:Angle():Forward() * entity.vm_radius * 0.75
	local src = data.Src - offset

	if mbs_vischeck:GetBool() then
		local src_tr = util.TraceLine({start = entity.head_pos, endpos = src, filter = entity})
		debugoverlay.Line( src_tr.StartPos, src_tr.HitPos, 5, Color(0, 0, 255), false)
		data.Src = src_tr.HitPos
	else
		data.Src = src
	end
	
	debugoverlay.Line(data.Src, data.Src + data.Dir * 1000, 5, Color(0, 255, 0), false)

	return true
end)
