--!strict
-- Center-of-screen elements: per-weapon crosshair (AK spread lines hidden while ADS; sniper dot,
-- hidden when scoped; knife / grenade dot; nothing while dead), hit
-- markers (head = larger red-orange, kill = longer hold) and damage direction arcs that keep
-- pointing at the attacker's position while you turn. (No throw-strength meter: owner, 2026-10-16.)
-- Mounted in a full-screen gui (IgnoreGuiInset) so screen center == camera center. Pixel sizes are
-- multiplied by the UIKit scale by hand (no UIScale: the crosshair gap must stay in true pixels).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Theme = require(script.Parent.Parent.Theme)
local UIKit = require(script.Parent.Parent.UIKit)
local Weapon = require(script.Parent.Parent.Weapon)

local Crosshair = {}

local LINE_LEN = 7
local LINE_THICK = 2
local MIN_GAP = 4
local DAMAGE_SECONDS = 1.4
local MAX_DAMAGE_ARCS = 4

type Arc = { Bar: Frame, From: Vector3, Until: number }

function Crosshair.mount(gui: ScreenGui)
	local root: Frame = UIKit.new("Frame", {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Parent = gui,
	})

	-- Four spread lines + center dot ----------------------------------------------------------
	local lines: { Frame } = {}
	local dirs = { Vector2.new(0, -1), Vector2.new(0, 1), Vector2.new(-1, 0), Vector2.new(1, 0) }
	for i, d in dirs do
		local vertical = d.X == 0
		lines[i] = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Theme.Colors.White,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Size = if vertical
				then UDim2.fromOffset(LINE_THICK, LINE_LEN)
				else UDim2.fromOffset(LINE_LEN, LINE_THICK),
			Parent = root,
		}, { UIKit.stroke(Theme.Colors.Black, 0.6) })
	end
	local dot: Frame = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Colors.White,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(2, 2),
		Parent = root,
	})
	UIKit.corner(UDim.new(0.5, 0)).Parent = dot

	-- Hit marker: four diagonal ticks ------------------------------------------------------------
	local hit: Frame = UIKit.new("Frame", {
		Name = "HitMarker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local ticks: { Frame } = {}
	for i = 1, 4 do
		ticks[i] = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Theme.Colors.White,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(8, 2),
			Rotation = 45 + (i - 1) * 90,
			Parent = hit,
		})
	end
	local hitToken = 0

	local function showHit(kind: string, killed: boolean)
		hitToken += 1
		local token = hitToken
		local scale = UIKit.getScale()
		local head = kind == "Head"
		local color = if head then Theme.Colors.Head else Theme.Colors.White
		local len = (if head then 11 else 8) * (if killed then 1.35 else 1) * scale
		local dist = (if head then 13 else 10) * scale
		local thick = math.max(2, math.floor((if head then 3 else 2) * scale + 0.5))
		for i, t in ticks do
			local angle = math.rad(45 + (i - 1) * 90)
			t.Size = UDim2.fromOffset(len, thick)
			t.Position = UDim2.fromOffset(math.cos(angle) * dist, math.sin(angle) * dist)
			t.BackgroundColor3 = color
			t.BackgroundTransparency = 0
		end
		task.delay(if killed then 0.28 else 0.1, function()
			if token ~= hitToken then
				return
			end
			for _, t in ticks do
				UIKit.tween(t, 0.18, { BackgroundTransparency = 1 })
			end
		end)
	end

	Remotes.Get("HitConfirm").OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" then
			return
		end
		showHit(tostring(data.Kind), data.Killed == true)
	end)

	-- Damage direction arcs ---------------------------------------------------------------------
	local arcs: { Arc } = {}
	for i = 1, MAX_DAMAGE_ARCS do
		local bar: Frame = UIKit.new("Frame", {
			Name = "DamageArc" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Theme.Colors.Damage,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(90, 4),
			Visible = false,
			Parent = gui,
		}, {
			UIKit.new("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
		arcs[i] = { Bar = bar, From = Vector3.zero, Until = 0 }
	end
	local nextArc = 1

	Remotes.Get("Damaged").OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" or typeof(data.FromPosition) ~= "Vector3" then
			return
		end
		local arc = arcs[nextArc]
		nextArc = nextArc % MAX_DAMAGE_ARCS + 1
		arc.From = data.FromPosition
		local amount = tonumber(data.Amount) or 20
		arc.Until = os.clock() + DAMAGE_SECONDS + math.clamp(amount / 100, 0, 0.6)
		arc.Bar.Visible = true
	end)

	-- Per-frame update --------------------------------------------------------------------------
	local gap = MIN_GAP
	local visible = false
	local function isAlive(): boolean
		local character = Players.LocalPlayer.Character
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		return hum ~= nil and hum.Health > 0
	end

	RunService.RenderStepped:Connect(function(dt: number)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local vp = camera.ViewportSize
		local s = Weapon.state()
		local scale = UIKit.getScale()

		-- Per weapon: AK = spread lines (hidden while ADS); Sniper = dot only, hidden when scoped
		-- (Combat draws the scope overlay); Knife / grenades = small dot.
		local held = s.Held
		local scoped = s.Scoped or (held == "Sniper" and s.Aiming)
		local want = gui.Enabled and isAlive() and not (held == "AK" and s.Aiming) and not scoped
		if want ~= visible then
			visible = want
			root.Visible = want
		end
		if visible then
			local showLines = held == "AK"
			local halfFov = math.rad(camera.FieldOfView / 2)
			local target = (vp.Y / 2) * math.tan(math.rad(s.Spread)) / math.tan(halfFov)
			target = math.max(MIN_GAP * scale, target)
			gap += (target - gap) * math.min(1, dt * 18)
			local len = LINE_LEN * scale
			local thick = math.max(2, math.floor(LINE_THICK * scale + 0.5))
			for i, d in dirs do
				local line = lines[i]
				line.Visible = showLines
				local offset = gap + len / 2
				line.Position = UDim2.fromOffset(d.X * offset, d.Y * offset)
				line.Size = if d.X == 0 then UDim2.fromOffset(thick, len) else UDim2.fromOffset(len, thick)
			end
			local dotSize = if held == "AK" then 2 else math.max(3, math.floor(3 * scale + 0.5))
			dot.Size = UDim2.fromOffset(dotSize, dotSize)
			dot.BackgroundTransparency = if held == "AK" then 0.35 else 0.15
			dot.Visible = not s.Reloading
		end

		-- Damage arcs
		local now = os.clock()
		local radius = math.min(vp.X, vp.Y) * 0.2
		for _, arc in arcs do
			if arc.Bar.Visible then
				local remaining = arc.Until - now
				if remaining <= 0 then
					arc.Bar.Visible = false
				else
					local rel = camera.CFrame:PointToObjectSpace(arc.From)
					local angle = math.atan2(rel.X, -rel.Z)
					arc.Bar.Position =
						UDim2.new(0.5, math.sin(angle) * radius, 0.5, -math.cos(angle) * radius)
					arc.Bar.Rotation = math.deg(angle)
					arc.Bar.Size = UDim2.fromOffset(110 * scale, math.max(3, 4 * scale))
					arc.Bar.BackgroundTransparency = 1 - math.clamp(remaining / 0.6, 0, 1) * 0.75
				end
			end
		end
	end)
end

return Crosshair
