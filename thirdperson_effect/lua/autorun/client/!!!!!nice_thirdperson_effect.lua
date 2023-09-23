local vars = {
	enabled = CreateConVar("cl_nte_enabled", "1", FCVAR_ARCHIVE),
	mode = CreateConVar("cl_nte_mode", "0", FCVAR_ARCHIVE, "0 - thirdperson, 1 - immersive firstperson"),
	wish_fov_max = CreateConVar("cl_nte_wish_fov_max", "20", FCVAR_ARCHIVE),
	wish_fov_min = CreateConVar("cl_nte_wish_fov_min", "0", FCVAR_ARCHIVE),
	distance = CreateConVar("cl_nte_distance", "20", FCVAR_ARCHIVE),
	eyetrace_distance = CreateConVar("cl_nte_eyetrace_distance", "500", FCVAR_ARCHIVE),
	visibility_tolerance = CreateConVar("cl_nte_vis_tolerance", "0.8", FCVAR_ARCHIVE),
	reaction_time_div = CreateConVar("cl_nte_reaction_time_div", "8", FCVAR_ARCHIVE),
	viewbob_mult_walk = CreateConVar("cl_nte_viewbob_mult_walk", 1, FCVAR_ARCHIVE),
	viewbob_mult_speed_walk = CreateConVar("cl_nte_viewbob_mult_speed_walk", 1, FCVAR_ARCHIVE),
	viewbob_mult_drunk = CreateConVar("cl_nte_viewbob_mult_drunk", 1, FCVAR_ARCHIVE),
	crosshair_enabled = CreateConVar("cl_nte_crosshair", 1, FCVAR_ARCHIVE),
	crosshair_outline = CreateConVar("cl_nte_crosshair_outline", 1, FCVAR_ARCHIVE),
	crosshair_size = CreateConVar("cl_nte_crosshair_size", 1, FCVAR_ARCHIVE),
	crosshair_color = {
		r = CreateConVar("cl_nte_crosshair_r", 255, FCVAR_ARCHIVE),
		g = CreateConVar("cl_nte_crosshair_g", 255, FCVAR_ARCHIVE),
		b = CreateConVar("cl_nte_crosshair_b", 255, FCVAR_ARCHIVE),
		a = CreateConVar("cl_nte_crosshair_a", 255, FCVAR_ARCHIVE),
	},
	crosshair_color_hidden = {
		r = CreateConVar("cl_nte_crosshair_hidden_r", 100, FCVAR_ARCHIVE),
		g = CreateConVar("cl_nte_crosshair_hidden_g", 100, FCVAR_ARCHIVE),
		b = CreateConVar("cl_nte_crosshair_hidden_b", 100, FCVAR_ARCHIVE),
		a = CreateConVar("cl_nte_crosshair_hidden_a", 255, FCVAR_ARCHIVE),
	},
	render_head = CreateConVar("cl_nte_render_head", 0, FCVAR_ARCHIVE),
	head_offset = CreateConVar("cl_nte_head_offset", "8 -8 0", FCVAR_ARCHIVE),
	predict_head = CreateConVar("cl_nte_predict_head", 0, FCVAR_ARCHIVE),
	autoside_enabled = CreateConVar("cl_nte_autoside_enabled", 1, FCVAR_ARCHIVE),
	default_side = CreateConVar("cl_nte_default_side", -1, FCVAR_ARCHIVE),
	box_size_2 = CreateConVar("cl_nte_vischeck_size", "5", FCVAR_ARCHIVE),
	hybrid_firstperson = CreateConVar("cl_nte_hybrid_firstperson", "0", FCVAR_ARCHIVE),
	thirdperson_offset = CreateConVar("cl_nte_thirdperson_offset", "0 0 0", FCVAR_ARCHIVE),
	fov_thing_was_reset = CreateConVar("cl_nte_fov_thing_was_reset_lol_epic", 0, FCVAR_ARCHIVE),
	znear = CreateConVar("cl_nte_znear", 1, FCVAR_ARCHIVE),
}

concommand.Add("cl_nte_toggle_state", function()
    local enabled = vars.enabled:GetBool()
    enabled = not enabled
    vars.enabled:SetBool(enabled)
end)

concommand.Add("cl_nte_switch_mode", function()
	local mode = vars.mode:GetInt()
	mode = mode + 1
	if mode > 1 then mode = 0 end
	vars.mode:SetInt(mode)
end)

local _mins = Vector(-vars.box_size_2:GetFloat(), -vars.box_size_2:GetFloat(), -vars.box_size_2:GetFloat())
local _maxs = Vector(vars.box_size_2:GetFloat(), vars.box_size_2:GetFloat(), vars.box_size_2:GetFloat())
local wish_fov = 0
local lerped_fov = 0
local wish_pos = Vector()
local lerped_pos = Vector()
local wish_fraction = 1
local lerped_fraction = 1
local wish_angle_offset = Angle()
local lerped_angle_offset = Angle()
local calcview_running = false

local cv_time = 0
local wish_viewbob_factor = 0
local lerped_viewbob_factor = 0
local side = 1
local side_switch_delay = 1
local side_waiting = false
local timer_locked = false
local left = 1
local right = 1
local up = 1

local function _is_up()
	return up > vars.visibility_tolerance:GetFloat() and left <= vars.visibility_tolerance:GetFloat() and right <= vars.visibility_tolerance:GetFloat()
end

local function _is_right()
	return right > vars.visibility_tolerance:GetFloat() and (left <= vars.visibility_tolerance:GetFloat() or side == 0)
end

local function _is_left()
	return left > vars.visibility_tolerance:GetFloat() and (right <= vars.visibility_tolerance:GetFloat() or side == 0)
end

local function trace_check(ent)
	if ent:IsNPC() or ent:IsPlayer() then return false else return true end
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
	if not vars.autoside_enabled:GetBool() then
		side = vars.default_side:GetInt()
		return
	end

	-- hacky
	-- i'm offsetting the hull start and end positions by their size in the respective directions so that
	-- we can more easily react to visibility changes on corners.
	-- why run hulls? because some grates can cause issues and then our side calculation is wonky as SHIT
	angles:Right() * vars.distance:GetFloat() * side
	local left_startpos = plytrace.StartPos - angles:Right() * vars.distance:GetFloat()
	local left_offset = (left_startpos - plytrace.HitPos):Angle():Right() * vars.box_size_2:GetFloat()
	local tr_to_hitpos_left = run_hull_trace(left_startpos + left_offset, plytrace.HitPos + left_offset)

	local right_startpos = plytrace.StartPos + angles:Right() * vars.distance:GetFloat()
	local right_offset = (right_startpos - plytrace.HitPos):Angle():Right() * vars.box_size_2:GetFloat()
	local tr_to_hitpos_right = run_hull_trace(right_startpos - right_offset, plytrace.HitPos - right_offset)

	local up_startpos = plytrace.StartPos + angles:Up() * vars.distance:GetFloat()
	local up_offset = (up_startpos - plytrace.HitPos):Angle():Up() * vars.box_size_2:GetFloat()
	local tr_to_hitpos_above = run_hull_trace(up_startpos + up_offset, plytrace.HitPos + up_offset)

	left = tr_to_hitpos_left.Fraction
	right = tr_to_hitpos_right.Fraction
	up = tr_to_hitpos_above.Fraction

	side_switch_delay = math.max(side_switch_delay - FrameTime(), 0)
	if side_switch_delay > 0 then return end

	local reaction_time = math.max(math.sqrt(LocalPlayer():GetVelocity():Length()) / vars.reaction_time_div:GetFloat(), 0.3)

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

	if side_waiting and not timer_locked then
		timer_locked = true

		timer.Simple(reaction_time, function()
			side_waiting = false
			timer_locked = false
		end)
	end
end

local wish_speed = 0
local lerped_speed = 0

local function calculate_ft()
	local ply = LocalPlayer()

	wish_speed = ply:GetMaxSpeed()

	if not (ply:KeyDown(IN_FORWARD) or ply:KeyDown(IN_MOVELEFT) or ply:KeyDown(IN_MOVERIGHT) or ply:KeyDown(IN_BACK)) then
		wish_speed = 0
	end

	lerped_speed = Lerp(engine.AbsoluteFrameTime() * 5, lerped_speed, wish_speed)
	local speed_factor = math.Remap(lerped_speed, 0, LocalPlayer():GetRunSpeed(), 1, 2) * vars.viewbob_mult_speed_walk:GetFloat()
	cv_time = cv_time + FrameTime() * speed_factor
end

local function generate_random_vec(f1, f2, f3, f4, f5, f6, time)
	return Vector(math.sin(time / f1) / f4, math.cos(time / f2) / f5, math.sin(time / f3) / f6)
end

local function generate_random_ang(f1, f2, f3, f4, f5, f6, time)
	return Angle(math.sin(time / f1) / f4, math.cos(time / f2) / f5, math.sin(time / f3) / f6)
end

local function draw_circle(x, y, radius, seg)
	local cir = {}

	table.insert(cir, {
		x = x,
		y = y,
		u = 0.5,
		v = 0.5
	})

	for i = 0, seg do
		local a = math.rad((i / seg) * -360)

		table.insert(cir, {
			x = x + math.sin(a) * radius,
			y = y + math.cos(a) * radius,
			u = math.sin(a) / 2 + 0.5,
			v = math.cos(a) / 2 + 0.5
		})
	end

	local a = math.rad(0)

	table.insert(cir, {
		x = x + math.sin(a) * radius,
		y = y + math.cos(a) * radius,
		u = math.sin(a) / 2 + 0.5,
		v = math.cos(a) / 2 + 0.5
	})

	draw.NoTexture()
	surface.DrawPoly(cir)
end

hook.Add("RenderScreenspaceEffects", "nte_crosshair", function()
	if not vars.enabled:GetBool() or not vars.crosshair_enabled:GetBool() or not calcview_running then return end

	local lp = LocalPlayer()

	local tr = lp:GetEyeTrace()
	local angles = EyeAngles()

	if GetConVar("sv_nte_manipulate_bullet_source"):GetBool() and not (vars.hybrid_firstperson:GetBool() and vars.mode:GetInt() == 1) and lp.hand_pos != nil and lp.vm_radius != nil then
		local offset = lp:EyePos() - lp.hand_pos - angles:Up() * 2 - angles:Forward() * lp.vm_radius * 0.75 
		tr = util.TraceLine({start = lp:EyePos() - offset, endpos = (lp:EyePos() - offset) + angles:Forward() * 99999 - offset, filter = lp})
		debugoverlay.Line(tr.StartPos, tr.HitPos, FrameTime(), Color(0, 255, 0), false)
	end

	local visibilitytr = util.TraceLine({
		start = lerped_pos,
		endpos = tr.HitPos,
		filter = lp
	})

	local color = nil

	if visibilitytr.Fraction <= 0.99 then
		color = Color(vars.crosshair_color_hidden.r:GetFloat(), vars.crosshair_color_hidden.g:GetFloat(), vars.crosshair_color_hidden.b:GetFloat(), vars.crosshair_color_hidden.a:GetFloat())
	else
		color = Color(vars.crosshair_color.r:GetFloat(), vars.crosshair_color.g:GetFloat(), vars.crosshair_color.b:GetFloat(), vars.crosshair_color.a:GetFloat())
	end

	local tos = tr.HitPos:ToScreen()

	if vars.crosshair_outline:GetBool() then
		surface.SetDrawColor(0, 0, 0, color.a)
		draw_circle(tos.x, tos.y, 4 * vars.crosshair_size:GetFloat(), 10 * vars.crosshair_size:GetFloat())
	end

	surface.SetDrawColor(color:Unpack())
	draw_circle(tos.x, tos.y, 2 * vars.crosshair_size:GetFloat(), 10 * vars.crosshair_size:GetFloat())
end)

local wish_limit_upper = -80
local wish_limit_lower = 65
local lerped_limit_upper = -80
local lerped_limit_lower = 65

hook.Add("CreateMove", "nte_get_away_from_the_wall", function(cmd)
	local lp = LocalPlayer()
	local headpos, headang = lp:GetBonePosition(lp:LookupBone("ValveBiped.Bip01_Head1"))
	
	local ang = lp:EyeAngles()
	ang.x = 0
	ang.z = 0

	local data = {
		start = headpos - ang:Forward() * 10,
		endpos = headpos,
		maxs = Vector(3,3,3),
		mins = Vector(-3,-3,-3),
		filter = lp
	}

	local tr = util.TraceHull(data)
	
	if (tr.Hit or tr.StartSolid) and lp:GetMoveType() == MOVETYPE_WALK then
		local diff = (tr.StartPos - tr.HitPos):GetNormalized()
		diff.z = 0
		cmd:SetForwardMove(diff.x * 10000)
		cmd:SetSideMove(diff.y * 10000)
	end

	if vars.hybrid_firstperson:GetBool() and vars.mode:GetInt() == 1 then
		local ang = cmd:GetViewAngles()
		wish_limit_upper = -80
		wish_limit_lower = 65
		if lp:KeyDown(IN_DUCK) then
			wish_limit_upper = wish_limit_upper + 15
			wish_limit_lower = wish_limit_lower - 15
		end
		
		lerped_limit_upper = Lerp(FrameTime() * 10, lerped_limit_upper, wish_limit_upper)
		lerped_limit_lower = Lerp(FrameTime() * 10, lerped_limit_lower, wish_limit_lower)

		ang.x = math.Clamp(ang.x, lerped_limit_upper, lerped_limit_lower)
		cmd:SetViewAngles(ang)
	end
end)

local last_head_pos = Vector()
local curr_head_pos = Vector()

NTE_CALC = false

local function main(ply, pos, angles, fov, znear, zfar)
	if NTE_CALC then return end

	calculate_ft()

	if GetViewEntity():GetPos():Distance(LocalPlayer():GetPos()) > 5 or LocalPlayer():Health() <= 0 or not vars.enabled:GetBool() then
		wish_pos = Vector()
		lerped_pos = Vector()
		return
	end

	NTE_CALC = true
	local base_view = hook.Run("CalcView", ply, pos, angles, fov, znear, zfar)
	pos, angles, fov, znear, zfar = base_view.origin or pos, base_view.angles or angles, base_view.fov or fov, base_view.znear or znear, base_view.zfar or zfar
	NTE_CALC = false

	calcview_running = true
	timer.Simple(FrameTime()*2, function() calcview_running = false end)

	if wish_pos:IsZero() or lerped_pos:IsZero() then
		wish_pos = pos
		lerped_pos = pos
	end

	local af = 10
	local mult_walk = vars.viewbob_mult_walk:GetFloat()
	local mult_drunk = vars.viewbob_mult_drunk:GetFloat()
	local speed = ply:GetMaxSpeed()

	if ply:GetVelocity():Length() <= 50 then
		speed = 0
	end

	wish_viewbob_factor = math.Remap(speed, 0, ply:GetRunSpeed(), 0, 1)
	lerped_viewbob_factor = Lerp(FrameTime() * af, lerped_viewbob_factor, wish_viewbob_factor)
	local drunk_view = generate_random_ang(0.9, 0.8, 0.5, 3, 3.6, 3.3, CurTime()) * mult_drunk
	local drunk_pos = generate_random_vec(1.2, 0.7, 0.8, 3.2, 3, 2, CurTime()) * mult_drunk
	local walk_viewbob = generate_random_ang(0.22, 0.15, 0.1, 2, 3.6, 3.3, cv_time) * mult_walk * lerped_viewbob_factor / 2
	local walk_viewbob_pos = generate_random_vec(0.5, 0.4, 0.3, 2, 3.6, 3.3, cv_time) * mult_walk * lerped_viewbob_factor * 5

	local plytrace = util.TraceLine({
		start = ply:GetShootPos(),
		endpos = ply:GetShootPos() + ply:EyeAngles():Forward() * vars.eyetrace_distance:GetFloat(),
		filter = ply,
		mask = MASK_SHOT_PORTAL
	})

	if not ply:KeyDown(IN_ATTACK) then
		calculate_side(angles, plytrace)
	else
		side_switch_delay = 1
	end

	local side_offset = angles:Right() * vars.distance:GetFloat() * side
	wish_angle_offset = Angle(0, -2 * side, 0)

	if side == 0 then
		side_offset = -angles:Up() * vars.distance:GetFloat()
		wish_angle_offset = Angle(-2, 0, 0)
	end
	
	lerped_angle_offset = LerpAngle(FrameTime() * af, lerped_angle_offset, wish_angle_offset)

	local head1_bone = ply:LookupBone("ValveBiped.Bip01_Head1")

	ply:ManipulateBoneScale(head1_bone, Vector(1, 1, 1))
	local head_matrix = ply:GetBoneMatrix(head1_bone)
	local offset = string.Split(vars.head_offset:GetString(), " ")
	local c_headpos, _ = LocalToWorld(Vector(offset[1], offset[2], offset[3]), Angle(0, -90, -90), head_matrix:GetTranslation(), head_matrix:GetAngles())
	last_head_pos = curr_head_pos
	curr_head_pos = c_headpos

	local weird_magic_number = 1
	if FrameTime() > 0 then
		weird_magic_number = ((1 / FrameTime()) - af) / af -- used to compensate for player/head velocity, so that the camera is still smooth but is stuck to the player
	end

	local player_velocity = LocalPlayer():GetVelocity()
	local head_velocity = ((curr_head_pos - last_head_pos) - (player_velocity * FrameTime())) * weird_magic_number

	local tr = {}
	local head_prediction = Vector()
	if vars.mode:GetInt() == 0 then
		local _offset = string.Split(vars.thirdperson_offset:GetString(), " ")
		local t_offset, _ = LocalToWorld(Vector(_offset[1], _offset[2], _offset[3]) , Angle(0, -90, -90), pos, angles)

		tr = run_hull_trace(pos, t_offset - angles:Forward() * vars.distance:GetFloat() * 3 + player_velocity * FrameTime() * weird_magic_number * 0.6 + walk_viewbob_pos + drunk_pos - side_offset)
	elseif vars.mode:GetInt() == 1 then

		if vars.predict_head:GetBool() then
			head_prediction = head_velocity
		end

		tr = run_hull_trace(pos, c_headpos + player_velocity * FrameTime() * weird_magic_number + walk_viewbob_pos + drunk_pos + head_prediction)

		if not vars.render_head:GetBool() then
			ply:ManipulateBoneScale(head1_bone, Vector())
		end
	end

	wish_pos = tr.HitPos
	if vars.hybrid_firstperson:GetBool() and ply:KeyDown(IN_ATTACK2) and (vars.hybrid_firstperson:GetBool() and vars.mode:GetInt() == 1) then
		wish_pos = pos
	end

	lerped_pos = LerpVector(FrameTime() * af, lerped_pos, wish_pos)

	wish_fov = math.Remap(tr.Fraction, 0, 1, vars.wish_fov_max:GetFloat(), vars.wish_fov_min:GetFloat())
	
	lerped_fov = Lerp(FrameTime() * af, lerped_fov, wish_fov)

	wish_fraction = math.Clamp(tr.Fraction, 0.2, 0.6)
	lerped_fraction = Lerp(FrameTime() * af, lerped_fraction, wish_fraction)

	local remapped_fraction = math.Remap(lerped_fraction, 0.2, 0.6, 50, 255)

	if remapped_fraction >= 254.9 then
		remapped_fraction = 255
	end

	-- doesnt work well with custom models. why?
	LocalPlayer():SetRenderMode(RENDERMODE_TRANSCOLOR)
	LocalPlayer():SetColor(Color(255, 255, 255, remapped_fraction))

	if lerped_pos:Distance(LocalPlayer():EyePos()) > 512 + player_velocity:Length() then
		lerped_pos = wish_pos
	end

	local view = {
		origin = lerped_pos,
		angles = angles + walk_viewbob + drunk_view,
		fov = math.Clamp(fov + lerped_fov, 0.01, 179),
		drawviewer = not (vars.hybrid_firstperson:GetBool() and vars.mode:GetInt() == 1),
		znear = vars.znear:GetFloat(),
		zfar = zfar
	}

	return view
end

local wish_dir = Vector()
local lerped_dir = Vector()

local function get_viewmodel_radius()
	local lp = LocalPlayer()

	local vm = lp:GetViewModel(0)
	local weapon = lp:GetActiveWeapon()
	local wm = NULL

	if isfunction(weapon.GetWM) then
		return weapon:GetWM()
	end

	if vm and isfunction(lp.GetModelRadius) then
		return vm:GetModelRadius()
	end

	if wm then
		return wm:GetModelRadius()
	end

	if IsValid(weapon) and isfunction(weapon.GetModelRadius) then
		return weapon:GetModelRadius() * 1.25
	end

	return 0
end

local function main_vm(wep, vm, oldpos, oldang, pos, ang)
	if not vars.hybrid_firstperson:GetBool() or not vars.enabled:GetBool() or not calcview_running then return end

	pos:Sub(oldpos - lerped_pos)

	local radius = get_viewmodel_radius()

	if radius <= 0 then
		radius = 1
	end

	local tr = util.TraceLine({
		start = oldpos,
		endpos = oldpos + ang:Forward() * 100000,
		filter = LocalPlayer()
	})

	local frac = math.Remap(tr.Fraction, 0, 1, 1, 0)

	local hitpos = Vector(LocalPlayer():GetEyeTrace().HitPos:Unpack()) + ang:Forward() * frac * radius * 0.7

	wish_dir = (hitpos - pos):GetNormalized()
	
	lerped_dir = LerpVector(FrameTime() * 20, lerped_dir, wish_dir)

	ang:Set(lerped_dir:Angle())
end

// aaaa_ probably does nothing lol
hook.Add("CalcView", "aaaa_nte_main", main)
hook.Add("CalcViewModelView", "aaaa_nte_main_vm", main_vm)

local invalidated = false

local function invalidate_vm_data(force)
	if ((vars.hybrid_firstperson:GetBool() and vars.mode:GetInt() == 1) or not vars.enabled:GetBool() or force) and not invalidated then
		local lp = LocalPlayer()
		net.Start("nte_bone_positions")
		net.WriteVector(lp.hand_pos or Vector())
		net.WriteFloat(lp.vm_radius or 0)
		net.WriteBool(false)
		net.SendToServer()
		invalidated = true
	end
end

hook.Add("PostPlayerDraw", "nte_send_vm_data", function(ply)
	if not vars.enabled:GetBool() or not calcview_running then
		invalidate_vm_data(true)
		return 
	end

	local lp = LocalPlayer()
	if ply != lp then return end

	local bone_matrix = lp:GetBoneMatrix(lp:LookupBone("ValveBiped.Bip01_R_Hand"))

	lp.hand_pos = bone_matrix:GetTranslation() or Vector()

	lp.vm_radius = get_viewmodel_radius()

	net.Start("nte_bone_positions")
	net.WriteVector(lp.hand_pos)
	net.WriteFloat(lp.vm_radius)
	net.WriteBool(true)
	net.SendToServer()

	invalidated = false
end)

cvars.AddChangeCallback(vars.hybrid_firstperson:GetName(), invalidate_vm_data)
cvars.AddChangeCallback(vars.mode:GetName(), invalidate_vm_data)
cvars.AddChangeCallback(vars.enabled:GetName(), invalidate_vm_data)

hook.Add("InitPostEntity", "nte_load", function()
	timer.Simple(1, function()
		if not vars.fov_thing_was_reset:GetBool() then
			vars.wish_fov_max:Revert()
			vars.wish_fov_min:Revert()
			vars.fov_thing_was_reset:SetBool(true)
		end
	end)
end)

concommand.Add("cl_nte_reset", function()
	for name, element in pairs(vars) do
		if type(element) == "table" then
			for _name, cvar in pairs(element) do
				if isfunction(cvar.Revert) then cvar:Revert() end
				print(tostring(_name) .. " was reset.")
			end
			continue
		end
		if isfunction(element.Revert) then element:Revert() end
		print(tostring(name) .. " was reset.")
	end
end)

local function preferences(Panel)
	Panel:CheckBox("Enabled", vars.enabled:GetName())
	Panel:NumSlider("Mode", vars.mode:GetName(), 0, 1, 0)
	Panel:ControlHelp("1 - immersive firstperson, 0 - thirdperson")
	Panel:CheckBox("Hybrid Immersive Firstperson", vars.hybrid_firstperson:GetName())
	Panel:ControlHelp("")
	Panel:CheckBox("Crosshair Enabled", vars.crosshair_enabled:GetName())
	Panel:CheckBox("Crosshair Black Outline", vars.crosshair_outline:GetName())
	Panel:ColorPicker("Crosshair Color", vars.crosshair_color.r:GetName(), vars.crosshair_color.g:GetName(), vars.crosshair_color.b:GetName(), vars.crosshair_color.a:GetName())
	Panel:ColorPicker("Crosshair Hidden Color", vars.crosshair_color_hidden.r:GetName(), vars.crosshair_color_hidden.g:GetName(), vars.crosshair_color_hidden.b:GetName(), vars.crosshair_color_hidden.a:GetName())
	Panel:NumSlider("Crosshair Size", vars.crosshair_size:GetName(), 0.5, 10, 2)
	Panel:ControlHelp("")
	Panel:CheckBox("Render Head", vars.render_head:GetName())
	Panel:ControlHelp("Renders your head when you're in firstperson mode. (mode: 1)")
	Panel:CheckBox("Predict Head Movement", vars.predict_head:GetName())
	Panel:ControlHelp("This accounts for your head movement when you're in firstperson, recommended for use with render head on, otherwise keep this off. (mode: 1)")
	Panel:ControlHelp("")
	Panel:NumSlider("Max wish fov", vars.wish_fov_max:GetName(), 0, 65)
	Panel:NumSlider("Min wish fov", vars.wish_fov_min:GetName(), 0, 65)
	Panel:NumSlider("Camera distance", vars.distance:GetName(), 0, 200)
	Panel:ControlHelp("")
	Panel:NumSlider("Walk Viewbob multiplier", vars.viewbob_mult_walk:GetName(), 0, 10, 1)
	Panel:NumSlider("Walk Viewbob Speed multiplier", vars.viewbob_mult_speed_walk:GetName(), 0, 10, 1)
	Panel:NumSlider("Idle Viewbob multiplier", vars.viewbob_mult_drunk:GetName(), 0, 10, 1)
	Panel:ControlHelp("")
	Panel:CheckBox("Autoside Enabled", vars.autoside_enabled:GetName())
	Panel:ControlHelp("System that automatically determines on which side the camera should be.")
	Panel:NumSlider("Default side", vars.default_side:GetName(), -1, 1, 0)
	Panel:ControlHelp("If autoside is disabled, this will decide the side. (-1 - right, 0 - up, 1 - left)")
	Panel:NumSlider("AutoSide distance", vars.eyetrace_distance:GetName(), 0, 9999)
	Panel:ControlHelp("At what distance should the auto side system kick in.")
	Panel:NumSlider("AutoSide Trace Fraction tolerance", vars.visibility_tolerance:GetName(), 0, 1, 2)
	Panel:ControlHelp("Too much to explain. Leave it at default or play around with it until you're satisfied.")
	Panel:NumSlider("AutoSide Reaction time DIV", vars.reaction_time_div:GetName(), 0, 100, 1)
	Panel:ControlHelp("Part of a magic formula that determines how fast autoside should react. Higher - faster, lower - slower.")
	Panel:ControlHelp("\n\n")
	Panel:Button("Reset settings", "cl_nte_reset")
end

hook.Add("PopulateToolMenu", "ctv_clientsettings", function()
	spawnmenu.AddToolMenuOption("Options", "CTV", "CTV_preferences", "Options", "", "", preferences, {})
end)