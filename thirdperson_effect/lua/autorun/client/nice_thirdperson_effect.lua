local enabled = CreateConVar("cl_nte_enabled", "1", FCVAR_ARCHIVE)
local wish_fov_max = CreateConVar("cl_nte_wish_fov_max", "110", FCVAR_ARCHIVE)
local wish_fov_min = CreateConVar("cl_nte_wish_fov_min", "75", FCVAR_ARCHIVE)
local distance = CreateConVar("cl_nte_distance", "20", FCVAR_ARCHIVE)
local eyetrace_distance = CreateConVar("cl_nte_eyetrace_distance", "500", FCVAR_ARCHIVE)
local mode = CreateConVar("cl_nte_mode", "0", FCVAR_ARCHIVE, "0 - thirdperson, 1 - immersive firstperson")

local visibility_tolerance = CreateConVar("cl_nte_vis_tolerance", "0.8", FCVAR_ARCHIVE)
local reaction_time_div = CreateConVar("cl_nte_reaction_time_div", "8", FCVAR_ARCHIVE)

local box_size_2 = CreateConVar("cl_nte_vischeck_size", "5", FCVAR_ARCHIVE)

local _mins = Vector(-box_size_2:GetFloat(), -box_size_2:GetFloat(), -box_size_2:GetFloat())
local _maxs = Vector(box_size_2:GetFloat(), box_size_2:GetFloat(), box_size_2:GetFloat())

local wish_fov = 75
local lerped_fov = 75

local wish_pos = Vector()
local lerped_pos = Vector()

local wish_fraction = 1
local lerped_fraction = 1

local wish_angle_offset = Angle()
local lerped_angle_offset = Angle()

local cv_ft = 0
local cv_time = 0

local wish_viewbob_factor = 0
local lerped_viewbob_factor = 0
local mult = 1

local samples_ft = {}
local last_systime = SysTime()
local curr_systime = SysTime()

local side = 1
local side_switch_delay = 1
local side_waiting = false
local timer_locked = false
local left = 1
local right = 1
local up = 1

local function approach(n1, n2, factor)
	return math.Approach(n1, n2, math.abs(n1 - n2) * cv_ft * factor + cv_ft)
end

local function approach_vec(v1, v2, factor)
	local temp = Vector()
	temp.x = approach(v1.x, v2.x, factor)
	temp.y = approach(v1.y, v2.y, factor)
	temp.z = approach(v1.z, v2.z, factor)
	return temp
end

local function approach_ang(v1, v2, factor)
	local temp = Angle()
	temp.x = approach(v1.x, v2.x, factor)
	temp.y = approach(v1.y, v2.y, factor)
	temp.z = approach(v1.z, v2.z, factor)
	return temp
end

local function _is_up()
	return up > visibility_tolerance:GetFloat() and left <= visibility_tolerance:GetFloat() and right <= visibility_tolerance:GetFloat()
end

local function _is_right()
	return right > visibility_tolerance:GetFloat() and (left <= visibility_tolerance:GetFloat() or side == 0)
end

local function _is_left()
	return left > visibility_tolerance:GetFloat() and (right <= visibility_tolerance:GetFloat() or side == 0)
end

local function trace_check(ent)
	if ent:IsNPC() or ent:IsPlayer() then return false end
end

local function run_hull_trace(start, endpos)
	return util.TraceHull({
		mins = _mins,
		maxs = _maxs,
		start = start,
		endpos = endpos,
		filter = trace_check,
		mask = MASK_SHOT_PORTAL
	})
end

local function calculate_side(angles, plytrace)
	// hacky
	// i'm offsetting the hull start and end positions by their size in the respective directions so that
	// we can more easily react to visibility changes on corners.
	// why run hulls? because some grates can cause issues and then our side calculation is wonky as SHIT
	local left_startpos = plytrace.StartPos - angles:Right() * distance:GetFloat()
	local left_offset = (left_startpos - plytrace.HitPos):Angle():Right() * box_size_2:GetFloat()
	local tr_to_hitpos_left = run_hull_trace(left_startpos + left_offset, plytrace.HitPos + left_offset)

	local right_startpos = plytrace.StartPos + angles:Right() * distance:GetFloat()
	local right_offset = (right_startpos - plytrace.HitPos):Angle():Right() * box_size_2:GetFloat()
	local tr_to_hitpos_right = run_hull_trace(right_startpos - right_offset, plytrace.HitPos - right_offset)

	local up_startpos = plytrace.StartPos + angles:Up() * distance:GetFloat()
	local up_offset = (up_startpos - plytrace.HitPos):Angle():Up() * box_size_2:GetFloat()
	local tr_to_hitpos_above = run_hull_trace(up_startpos + up_offset, plytrace.HitPos + up_offset)

	debugoverlay.SweptBox(tr_to_hitpos_above.StartPos, tr_to_hitpos_above.HitPos, _mins, _maxs, Angle(), cv_ft, Color(255, 255, 255, 128))
	debugoverlay.SweptBox(tr_to_hitpos_right.StartPos, tr_to_hitpos_right.HitPos, _mins, _maxs, Angle(), cv_ft, Color(255, 255, 255, 128))
	debugoverlay.SweptBox(tr_to_hitpos_left.StartPos, tr_to_hitpos_left.HitPos, _mins, _maxs, Angle(), cv_ft, Color(255, 255, 255, 128))

	left = tr_to_hitpos_left.Fraction
	right = tr_to_hitpos_right.Fraction
	up = tr_to_hitpos_above.Fraction

	side_switch_delay = math.max(side_switch_delay - FrameTime(), 0)
	if side_switch_delay > 0 then return end

	local reaction_time = math.max(math.sqrt(LocalPlayer():GetVelocity():Length()) / reaction_time_div:GetFloat(), 0.3)

	//print("----------------")
	//print(_is_up(), _is_right(), _is_left(), side_waiting)
	//print(above, right, left, "___")
	//print("----------------")

	if _is_up() and not side_waiting then
		side_waiting = true
		timer.Simple(reaction_time, function()
			if _is_up() then
				side = 0
				side_switch_delay = reaction_time
			end
		end)
	end

	if _is_right() and (not side_waiting or side == 0) then
		side_waiting = true
		timer.Simple(reaction_time, function()
			if _is_right() then
				side = -1
				side_switch_delay = reaction_time
			end
		end)
	end

	if _is_left() and (not side_waiting or side == 0) then
		side_waiting = true
		timer.Simple(reaction_time, function()
			if _is_left() then
				side = 1
				side_switch_delay = reaction_time
			end
		end)
	end

	if side_waiting and not timer_locked then timer_locked = true timer.Simple(reaction_time, function() side_waiting = false timer_locked = false end) end
end

local function calculate_ft()
	last_systime = curr_systime
	curr_systime = SysTime()

	table.insert(samples_ft, curr_systime - last_systime)

	if table.Count(samples_ft) > 10 then
		table.remove(samples_ft, 1)
	end

	local summ = 0

	for i, num in ipairs(samples_ft) do
		summ = summ + num
	end

	cv_ft = math.Round(summ / table.Count(samples_ft), 4)

	// math fuckery where instead of being able to multiply cv_time by some factor i have to do this shit to speed up viewbobbing.
	// maybe i'm just bad.
	local speed = LocalPlayer():GetMaxSpeed()

	if LocalPlayer():GetVelocity():Length() <= 50 then
		speed = 0
	end

	local speed_factor = math.sqrt(speed) / 10
	cv_time = cv_time + cv_ft * speed_factor
end

local function generate_random_vec(f1, f2, f3, f4, f5, f6, time)
	return Vector(math.sin(time / f1) / f4,
				  math.cos(time / f2) / f5,
	              math.sin(time / f3) / f6)
end

local function generate_random_ang(f1, f2, f3, f4, f5, f6, time)
	return Angle(math.sin(time / f1) / f4,
				 math.cos(time / f2) / f5,
	             math.sin(time / f3) / f6)
end

local crosshair = Material("nte/crosshair.png")

hook.Add("RenderScreenspaceEffects", "nte_crosshair", function()
	if not enabled:GetBool() then return end
	local tr = LocalPlayer():GetEyeTrace()

	local visibilitytr = util.TraceLine({
		start = wish_pos,
		endpos = tr.HitPos,
		filter = LocalPlayer(),
		mask = MASK_SHOT_PORTAL
	})

	if visibilitytr.Fraction > 0.99 then
		surface.SetDrawColor(255, 255, 255, 255)
	else
		surface.SetDrawColor(100, 100, 100, 255)
	end

	surface.SetMaterial(crosshair)
	local tos = tr.HitPos:ToScreen()
	surface.DrawTexturedRect(tos.x - 16, tos.y - 16, 32, 32)
end)

hook.Add("CalcView", "nte_calcview", function(ply, pos, angles, fov, znear, zfar)
	// todo: maybe port this to that calcview priority system... or figure out how to support other calcview hooks manually..
	calculate_ft()

	if cv_ft <= 0 then print("wtf?") return end

	if GetViewEntity():GetPos():Distance(LocalPlayer():GetPos()) > 5 or LocalPlayer():Health() <= 0 or not enabled:GetBool() then
		wish_pos = Vector()
		lerped_pos = Vector()
	 	return
	end

	if wish_pos:IsZero() or lerped_pos:IsZero() then
		wish_pos = pos
		lerped_pos = pos
	end

	local af = cv_ft * (0.3 / cv_ft) * 30

	local speed = ply:GetMaxSpeed()
	if ply:GetVelocity():Length() <= 50 then speed = 0 end
	wish_viewbob_factor = math.Remap(speed, 0, ply:GetRunSpeed(), 0, 1)
	lerped_viewbob_factor = math.Round(approach(lerped_viewbob_factor, wish_viewbob_factor, af), 2)

	local drunk_view = generate_random_ang(0.9, 0.8, 0.5, 3, 3.6, 3.3, CurTime()) * mult
	local drunk_pos = generate_random_vec(1.2, 0.7, 0.8, 3.2, 3, 2, CurTime()) * mult
	local walk_viewbob = generate_random_ang(0.22, 0.15, 0.1, 2, 3.6, 3.3, cv_time) * mult * lerped_viewbob_factor
	local walk_viewbob_pos = generate_random_vec(0.5, 0.4, 0.3, 2, 3.6, 3.3, cv_time) * mult * lerped_viewbob_factor * 10

	local plytrace = util.TraceLine({
		start = ply:GetShootPos(),
		endpos = ply:GetShootPos() + ply:EyeAngles():Forward() * eyetrace_distance:GetFloat(),
		filter = ply,
		mask = MASK_SHOT_PORTAL
	})
	if not ply:KeyDown(IN_ATTACK) then calculate_side(angles, plytrace) else side_switch_delay = 1 end

	local side_offset = angles:Right() * distance:GetFloat() * side
	wish_angle_offset = Angle(0, -2 * side, 0)
	if side == 0 then
		side_offset = -angles:Up() * distance:GetFloat()
		wish_angle_offset = Angle(-2, 0, 0)
	end
	lerped_angle_offset = approach_ang(lerped_angle_offset, wish_angle_offset, af)

	local zoom_offset = Vector()
	local zoom_fov_offset = 0
	if ply:KeyDown(IN_ATTACK2) then
		zoom_fov_offset = 20
		zoom_offset = angles:Forward() * 20
	end

	local crouch_offset = Vector()
	if ply:Crouching() then crouch_offset.z = crouch_offset.z + 18 end

	local tr = {}

	// i'm not gonna spend my time trying to figure out what variable, function or whatever is needed or not for each mode
	// receive this instead.
	// todo: figure out a way to smoothly get rid of the head or smth
	ply:ManipulateBoneScale(ply:LookupBone("ValveBiped.Bip01_Head1"), Vector(1,1,1))
	if mode:GetInt() == 0 then
		tr = run_hull_trace(pos,
							pos - angles:Forward() * distance:GetFloat() * 3
							+
							LocalPlayer():GetVelocity() * cv_ft * (0.015 / cv_ft) * 5
							+
							walk_viewbob_pos + drunk_pos + crouch_offset - side_offset - zoom_offset)
	elseif mode:GetInt() == 1 then
		local headpos, headang = ply:GetBonePosition(ply:LookupBone("ValveBiped.Bip01_Head1"))
		local c_headpos, _ = LocalToWorld(Vector(5,-5,0), Angle(0,-90,-90), headpos, headang)
		tr = run_hull_trace(pos,
							c_headpos + LocalPlayer():GetVelocity() * cv_ft * (0.015 / cv_ft) * 7
							+
							walk_viewbob_pos + drunk_pos)
		ply:ManipulateBoneScale(ply:LookupBone("ValveBiped.Bip01_Head1"), Vector())
	end

	wish_fraction = math.Clamp(tr.Fraction, 0.2, 0.6)
	lerped_fraction = approach(lerped_fraction, wish_fraction, af)

	// doesnt work well with custom models. why?
	LocalPlayer():SetRenderMode(RENDERMODE_TRANSCOLOR)
	LocalPlayer():SetColor(Color(255, 255, 255, math.Remap(lerped_fraction, 0.2, 0.6, 50, 255)))

	wish_fov = math.Remap(tr.Fraction, 0, 1, wish_fov_max:GetFloat(), wish_fov_min:GetFloat()) - zoom_fov_offset
	wish_pos = tr.HitPos

	lerped_fov = approach(lerped_fov, wish_fov, af)
	lerped_pos = approach_vec(lerped_pos, wish_pos, af)

	znear = 1

	local view = {
		origin = lerped_pos,
		angles = angles + walk_viewbob + drunk_view,
		fov = lerped_fov,
		drawviewer = true,
		znear = znear,
		zfar = zfar
	}

	return view
end)