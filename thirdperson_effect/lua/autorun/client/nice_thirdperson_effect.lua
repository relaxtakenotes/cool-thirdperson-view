local enabled = CreateConVar("cl_nte_enabled", "1", FCVAR_ARCHIVE)
local wish_fov_max = CreateConVar("cl_nte_wish_fov_max", "110", FCVAR_ARCHIVE)
local wish_fov_min = CreateConVar("cl_nte_wish_fov_min", "75", FCVAR_ARCHIVE)
local distance = CreateConVar("cl_nte_distance", "20", FCVAR_ARCHIVE)
local eyetrace_distance = CreateConVar("cl_nte_eyetrace_distance", "500", FCVAR_ARCHIVE)
local mode = CreateConVar("cl_nte_mode", "0", FCVAR_ARCHIVE, "0 - thirdperson, 1 - immersive firstperson")
local visibility_tolerance = CreateConVar("cl_nte_vis_tolerance", "0.8", FCVAR_ARCHIVE)
local reaction_time_div = CreateConVar("cl_nte_reaction_time_div", "8", FCVAR_ARCHIVE)
local viewbob_mult_walk = CreateConVar("cl_nte_viewbob_mult_walk", 1, FCVAR_ARCHIVE)
local viewbob_mult_drunk = CreateConVar("cl_nte_viewbob_mult_drunk", 1, FCVAR_ARCHIVE)
local crosshair_enabled = CreateConVar("cl_nte_crosshair", 1, FCVAR_ARCHIVE)

local render_head = CreateConVar("cl_nte_render_head", 0, FCVAR_ARCHIVE)
local head_offset = CreateConVar("cl_nte_head_offset", "8 -8 0", FCVAR_ARCHIVE)
local predict_head = CreateConVar("cl_nte_predict_head", 0, FCVAR_ARCHIVE)

local autoside_enabled = CreateConVar("cl_nte_autoside_enabled", 1, FCVAR_ARCHIVE)
local default_side = CreateConVar("cl_nte_default_side", -1, FCVAR_ARCHIVE)

local box_size_2 = CreateConVar("cl_nte_vischeck_size", "5", FCVAR_ARCHIVE)

local ft_samples_limit = CreateConVar("cl_nte_frametime_avg_limit", 10, FCVAR_ARCHIVE, "amount of samples used to average the frametime, if used.")
local ft_mode = CreateConVar("cl_nte_frametime_mode", 0, FCVAR_ARCHIVE, "0 - engine.AbsoluteFrameTime(), 1 - an average over 10 samples")

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

local move_back = false

local ft_samples = {}
cvars.AddChangeCallback(ft_samples_limit:GetName(), function()
	ft_samples = {}
end)
local cv_ft = 0
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

local function approach(n1, n2, factor)
	return math.Approach(n1, n2, math.abs(n1 - n2) * factor * cv_ft + cv_ft)
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
	if not autoside_enabled:GetBool() then side = default_side:GetInt() return end
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

	left = tr_to_hitpos_left.Fraction
	right = tr_to_hitpos_right.Fraction
	up = tr_to_hitpos_above.Fraction

	side_switch_delay = math.max(side_switch_delay - FrameTime(), 0)
	if side_switch_delay > 0 then return end

	local reaction_time = math.max(math.sqrt(LocalPlayer():GetVelocity():Length()) / reaction_time_div:GetFloat(), 0.3)

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
	local _ft = engine.AbsoluteFrameTime()

	table.insert(ft_samples, _ft)
	local ft_sum = 0
	for i, ft in ipairs(ft_samples) do
		ft_sum = ft_sum + ft
	end
	if table.Count(ft_samples) > ft_samples_limit:GetInt() then
		table.remove(ft_samples, 1)
	end

	if ft_mode:GetInt() == 1 then
		cv_ft = ft_sum / table.Count(ft_samples)
	else
		cv_ft = _ft
	end

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
	if not enabled:GetBool() or not crosshair_enabled:GetBool() then return end

	local tr = LocalPlayer():GetEyeTrace()

	local visibilitytr = util.TraceLine({
		start = lerped_pos,
		endpos = tr.HitPos,
		filter = LocalPlayer()
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

hook.Add("CreateMove", "nte_get_away_from_the_wall", function(cmd)
	if move_back and LocalPlayer():GetMoveType() == MOVETYPE_WALK then cmd:SetForwardMove(-100000) end
end)

local last_head_pos = Vector()
local curr_head_pos = Vector()

local function main(ply, pos, angles, fov, znear, zfar)
	calculate_ft()

	if GetViewEntity():GetPos():Distance(LocalPlayer():GetPos()) > 5 or LocalPlayer():Health() <= 0 then
		wish_pos = Vector()
		lerped_pos = Vector()
		return {
			origin = pos,
			angles = angles,
			fov = fov,
			drawviewer = false,
			znear = znear,
			zfar = zfar
		}
	end

	if wish_pos:IsZero() or lerped_pos:IsZero() then
		wish_pos = pos
		lerped_pos = pos
	end

	local af = 10

	local mult_walk = viewbob_mult_walk:GetFloat()
	local mult_drunk = viewbob_mult_drunk:GetFloat()
	local speed = ply:GetMaxSpeed()
	if ply:GetVelocity():Length() <= 50 then speed = 0 end
	wish_viewbob_factor = math.Remap(speed, 0, ply:GetRunSpeed(), 0, 1)
	lerped_viewbob_factor = math.Round(approach(lerped_viewbob_factor, wish_viewbob_factor, af), 2)

	local drunk_view = generate_random_ang(0.9, 0.8, 0.5, 3, 3.6, 3.3, CurTime()) * mult_drunk
	local drunk_pos = generate_random_vec(1.2, 0.7, 0.8, 3.2, 3, 2, CurTime()) * mult_drunk
	local walk_viewbob = generate_random_ang(0.22, 0.15, 0.1, 2, 3.6, 3.3, cv_time) * mult_walk * lerped_viewbob_factor
	local walk_viewbob_pos = generate_random_vec(0.5, 0.4, 0.3, 2, 3.6, 3.3, cv_time) * mult_walk * lerped_viewbob_factor * 10

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

	// i'm not gonna spend my time trying to figure out what variable, function or whatever is needed or not for each mode
	// receive this instead.
	// todo: figure out a way to smoothly get rid of the head or smth

	ply:ManipulateBoneScale(ply:LookupBone("ValveBiped.Bip01_Head1"), Vector(1, 1, 1))
	local headpos, headang = ply:GetBonePosition(ply:LookupBone("ValveBiped.Bip01_Head1"))
	local offset = string.Split(head_offset:GetString(), " ")
	local c_headpos, _ = LocalToWorld(Vector(offset[1], offset[2], offset[3]), Angle(0, -90, -90), headpos, headang)
	last_head_pos = curr_head_pos
	curr_head_pos = c_headpos

	local weird_magic_number = ((1 / cv_ft) - af) / af // used to compensate for player/head velocity, so that the camera is still smooth but is stuck to the player

	local player_velocity = LocalPlayer():GetVelocity()
	local head_velocity = curr_head_pos - last_head_pos - player_velocity * cv_ft

	local tr = {}
	if mode:GetInt() == 0 then
		tr = run_hull_trace(pos, pos - angles:Forward() * distance:GetFloat() * 3 + player_velocity * cv_ft * weird_magic_number * 0.6 + walk_viewbob_pos + drunk_pos - side_offset - zoom_offset)
		move_back = false
	elseif mode:GetInt() == 1 then
		local head_prediction = Vector()
		if predict_head:GetBool() then head_prediction = head_velocity * cv_ft * weird_magic_number * 100 end
		tr = run_hull_trace(pos, c_headpos + player_velocity * cv_ft * weird_magic_number + walk_viewbob_pos + drunk_pos + head_prediction)
		move_back = tr.Fraction < 0.92
		if not render_head:GetBool() then ply:ManipulateBoneScale(ply:LookupBone("ValveBiped.Bip01_Head1"), Vector()) end
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

	local view = {
		origin = lerped_pos,
		angles = angles + walk_viewbob + drunk_view,
		fov = lerped_fov,
		drawviewer = true,
		znear = znear,
		zfar = zfar
	}

	return view
end

// this would the the preferred way to do it, but sadly due to mod loading order sometimes it can |not execute|	
//hook.Add("CalcViewPS_Initialized", "nte_load", function()
//		CalcViewPS.AddToTop("nte_main", main)
//end)

// note: cause of the priority system hot reloading this script will cause errors.
//		 either switch to using raw calcview or rejoin the server everytime you change something
local _init = false
hook.Add("InitPostEntity", "nte_load", function()
	timer.Simple(1, function()
		if enabled:GetBool() and CalcViewPS then CalcViewPS.AddToTop("nte_main", main, CalcViewPS.PerspectiveENUM.THIRDPERSON) end
		_init = true
	end)
end)

cvars.AddChangeCallback(enabled:GetName(), function()
	if not CalcViewPS or not _init then return end
	if enabled:GetBool() then CalcViewPS.AddToTop("nte_main", main, CalcViewPS.PerspectiveENUM.THIRDPERSON) end
	if not enabled:GetBool() then CalcViewPS.Remove("nte_main") end
end)
//hook.Add("CalcView", "nte_dev_main", main)

concommand.Add("cl_nte_reset", function()
	enabled:Revert()
	wish_fov_max:Revert()
	wish_fov_min:Revert()
	distance:Revert()
	eyetrace_distance:Revert()
	mode:Revert()
	visibility_tolerance:Revert()
	reaction_time_div:Revert()
	viewbob_mult_walk:Revert()
	viewbob_mult_drunk:Revert()
	crosshair_enabled:Revert()
	render_head:Revert()
	head_offset:Revert()
	predict_head:Revert()
	autoside_enabled:Revert()
	default_side:Revert()
	box_size_2:Revert()
end)


local function preferences(Panel)
	Panel:CheckBox("Enabled", enabled:GetName())
	Panel:NumSlider("Mode", mode:GetName(), 0, 1, 0)
	Panel:ControlHelp("1 - immersive firstperson, 0 - thirdperson")
	Panel:CheckBox("Crosshair Enabled", crosshair_enabled:GetName())

	Panel:ControlHelp("")

	Panel:CheckBox("Render Head", render_head:GetName())
	Panel:ControlHelp("Renders your head when you're in firstperson mode. (mode: 1)")
	Panel:CheckBox("Predict Head Movement", predict_head:GetName())
	Panel:ControlHelp("This accounts for your head movement when you're in firstperson, recommended for use with render head on, otherwise keep this off. (mode: 1)")

	Panel:ControlHelp("")

	Panel:NumSlider("Max wish fov", wish_fov_max:GetName(), 75, 120)
	Panel:NumSlider("Min wish fov", wish_fov_min:GetName(), 75, 120)
	Panel:NumSlider("Camera distance", distance:GetName(), 0, 200)

	Panel:ControlHelp("")

	Panel:NumSlider("Walk Viewbob multiplier", viewbob_mult_walk:GetName(), 0, 10, 1)
	Panel:NumSlider("Idle Viewbob multiplier", viewbob_mult_drunk:GetName(), 0, 10, 1)

	Panel:ControlHelp("")

	Panel:CheckBox("Autoside Enabled", autoside_enabled:GetName())
	Panel:ControlHelp("System that automatically determines on which side the camera should be.")
	Panel:NumSlider("Default side", default_side:GetName(), -1, 1, 0)
	Panel:ControlHelp("If autoside is disabled, this will decide the side. (-1 - right, 0 - up, 1 - left)")
	Panel:NumSlider("AutoSide distance", eyetrace_distance:GetName(), 0, 9999)
	Panel:ControlHelp("At what distance should the auto side system kick in.")
	Panel:NumSlider("AutoSide Trace Fraction tolerance", visibility_tolerance:GetName(), 0, 1, 2)
	Panel:ControlHelp("Too much to explain. Leave it at default or play around with it until you're satisfied.")
	Panel:NumSlider("AutoSide Reaction time DIV", reaction_time_div:GetName(), 0, 100, 1)
	Panel:ControlHelp("Part of a magic formula that determines how fast autoside should react. Higher - faster, lower - slower.")
	Panel:ControlHelp("\n\n")
	Panel:Button("Reset settings", "cl_nte_reset")

end

hook.Add("PopulateToolMenu", "dwr_clientsettings", function()
	spawnmenu.AddToolMenuOption("Options", "CTV", "CTV_preferences", "Options", "", "", preferences, {})
end)