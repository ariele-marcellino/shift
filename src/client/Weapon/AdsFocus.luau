--!strict
-- AK aim-down-sights focus: a light local DepthOfFieldEffect (softens the near gun body) plus a soft
-- radial vignette built from stacked translucent ring strokes (no image assets). Both fade with the
-- ADS alpha. DOF is skipped on low graphics quality and switched off for the session if aiming
-- with it costs frames; the vignette is UI-only and always cheap.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local AdsFocus = {}

local MIN_QUALITY = 5 -- SavedQualityLevel 1-10; Automatic counts as allowed
local SLOW_FRAME = 1 / 40

local USE_DOF = false
local dof: DepthOfFieldEffect? = nil
local dofAllowed = true
local rings: { { Stroke: UIStroke, Alpha: number } } = {}
local gui: ScreenGui
local current = -1
local slowTime, sampleTime = 0, 0

local function qualityOk(): boolean
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if not ok or typeof(level) ~= "EnumItem" then
		return true
	end
	return level == Enum.SavedQualitySetting.Automatic or level.Value >= MIN_QUALITY
end

function AdsFocus.Init()
	local effect = Instance.new("DepthOfFieldEffect")
	effect.Name = "WeaponAdsFocus"
	effect.FocusDistance = 30
	effect.InFocusRadius = 26 -- sharp from ~4 studs out; only the gun body softens
	effect.NearIntensity = 0
	effect.FarIntensity = 0
	effect.Enabled = false
	effect.Parent = Lighting
	dof = effect

	gui = Instance.new("ScreenGui")
	gui.Name = "AdsVignette"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -2 -- under the HUD and the sniper scope
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- outermost ring darkest: stacked strokes make a stepped, soft falloff toward the edges
	for _, spec in
		{ { Size = 1.55, Alpha = 0.22 }, { Size = 1.25, Alpha = 0.16 }, { Size = 1.0, Alpha = 0.1 } }
	do
		local circle = Instance.new("Frame")
		circle.AnchorPoint = Vector2.new(0.5, 0.5)
		circle.Position = UDim2.fromScale(0.5, 0.5)
		circle.Size = UDim2.fromScale(spec.Size, spec.Size)
		circle.SizeConstraint = Enum.SizeConstraint.RelativeYY
		circle.BackgroundTransparency = 1
		circle.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = circle
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1500
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Transparency = 1
		stroke.Parent = circle
		table.insert(rings, { Stroke = stroke, Alpha = spec.Alpha })
	end
	dofAllowed = qualityOk()
end

-- alpha: eased ADS amount for the AK (0 when not aiming / other weapons). Call every frame.
function AdsFocus.Update(alpha: number, dt: number)
	alpha = math.clamp(alpha, 0, 1)
	-- frame-cost guard: if aiming with DOF keeps frames slow, drop DOF for the session
	if dof and dof.Enabled then
		sampleTime += dt
		if dt > SLOW_FRAME then
			slowTime += dt
		end
		if sampleTime > 3 then
			if slowTime / sampleTime > 0.5 then
				dofAllowed = false
				dof.Enabled = false
			end
			sampleTime, slowTime = 0, 0
		end
	end
	if math.abs(alpha - current) < 0.01 then
		return
	end
	current = alpha
	local on = alpha > 0.01
	-- Ring vignette disabled: the stacked ring strokes showed as hard bands (user screenshot).
	gui.Enabled = false
	for _, r in rings do
		r.Stroke.Transparency = 1 - r.Alpha * alpha
	end
	if dof then
		-- Disabled: Roblox's near DoF shimmers on the viewmodel parts closest to the camera
		-- (user report: the near end of the AK looked "wiggly" while aiming). Vignette stays.
		local useDof = USE_DOF and on and dofAllowed
		dof.Enabled = useDof
		if useDof then
			dof.NearIntensity = 0.3 * alpha
		end
	end
end

-- Re-check graphics quality (e.g. on respawn). Never re-enables after the frame guard tripped.
function AdsFocus.RefreshQuality()
	if dofAllowed then
		dofAllowed = qualityOk()
	end
end

return AdsFocus
