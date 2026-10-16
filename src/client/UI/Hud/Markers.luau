--!strict
-- World-space Core markers, drawn in screen space each frame and clamped to the screen edge when
-- off-screen or behind the camera:
--   * your team's carrier (enemy Core carried by a teammate)  -> "ESCORT · name"
--   * your Flag stolen (carried by an enemy)                   -> "YOUR FLAG"
--   * any dropped Core                                          -> "RETURN 14" (yours) / "TAKE 14" (theirs)
-- No marker for a Core at home or when you are the carrier. At most two markers, so the per-frame
-- cost is two WorldToViewportPoint calls.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Theme = require(script.Parent.Parent.Theme)
local UIKit = require(script.Parent.Parent.UIKit)
local MatchStore = require(script.Parent.Parent.MatchStore)

local Markers = {}

local EDGE_MARGIN = 36
local LIFT = Vector3.new(0, 3, 0)

type Marker = {
	Root: Frame,
	Diamond: Frame,
	Label: TextLabel,
	Shown: Vector3?,
}

-- Live position of the carrier (player by UserId, else a bot model in workspace.Bots by name).
local function carrierPosition(userId: number?, name: string?): Vector3?
	local character: Instance? = nil
	if userId then
		local player = Players:GetPlayerByUserId(userId)
		character = player and player.Character
	end
	if not character and name then
		local bots = workspace:FindFirstChild("Bots")
		character = bots and bots:FindFirstChild(name)
	end
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

function Markers.mount(gui: ScreenGui)
	local function make(team: string): Marker
		local root: Frame = UIKit.new("Frame", {
			Name = "Marker_" .. team,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(120, 34),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = gui,
		})
		UIKit.autoScale(root)
		local diamond: Frame = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 7),
			Size = UDim2.fromOffset(9, 9),
			Rotation = 45,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			Parent = root,
		}, { UIKit.stroke(Theme.Colors.White, 0.4) })
		local label = UIKit.text("", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 15),
			Size = UDim2.new(1, 0, 0, 14),
			TextSize = Theme.TextSize.Tiny,
			FontFace = Theme.Fonts.Medium,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTransparency = 0.15,
			TextStrokeTransparency = 0.6,
			Parent = root,
		})
		return { Root = root, Diamond = diamond, Label = label, Shown = nil }
	end

	local markers: { [string]: Marker } = { Blue = make("Blue"), Red = make("Red") }

	RunService.RenderStepped:Connect(function(dt: number)
		local camera = workspace.CurrentCamera
		if not camera or not gui.Enabled then
			return
		end
		local vp = camera.ViewportSize
		local mine = MatchStore.localTeam()
		local me = Players.LocalPlayer

		for team, marker in markers do
			local core = MatchStore.Cores[team]
			local target: Vector3? = nil
			local text = ""
			local color = Theme.teamColor(team)

			if core and MatchStore.Phase ~= "Ended" and mine then
				if core.State == "Carried" and core.CarrierUserId ~= me.UserId then
					target = (carrierPosition(core.CarrierUserId, core.CarrierName) or core.Position) + LIFT
					if team == mine then
						text = "YOUR FLAG"
					else
						text = "ESCORT  ·  " .. (core.CarrierName or "")
						color = Theme.teamColor(mine)
					end
				elseif core.State == "Dropped" then
					target = core.Position + LIFT
					local t = MatchStore.returnIn(team)
					local suffix = if t then string.format("  %d", math.ceil(t)) else ""
					text = (if team == mine then "RETURN" else "TAKE") .. suffix
				end
			end

			if not target then
				marker.Root.Visible = false
				marker.Shown = nil
				continue
			end

			-- Smooth between 1-4 Hz MatchState updates (snap on big jumps).
			local shown = marker.Shown
			if not shown or (shown - target).Magnitude > 30 then
				shown = target
			else
				shown = shown:Lerp(target, math.min(1, dt * 10))
			end
			marker.Shown = shown

			local p, onScreen = camera:WorldToViewportPoint(shown :: Vector3)
			local x, y = p.X, p.Y
			local margin = EDGE_MARGIN * UIKit.getScale()
			if p.Z < 0 then
				-- Behind the camera: mirror and push to the bottom edge direction.
				x = vp.X - x
				y = vp.Y - margin
			end
			if not onScreen or p.Z < 0 then
				x = math.clamp(x, margin, vp.X - margin)
				y = math.clamp(y, margin, vp.Y - margin)
			end
			marker.Root.Position = UDim2.fromOffset(x, y)
			marker.Diamond.BackgroundColor3 = color
			marker.Label.TextColor3 = color
			marker.Label.Text = text
			marker.Root.Visible = true
		end
	end)
end

return Markers
