--!strict
-- Touch controls (v2). A right-thumb arc around a large FIRE button:
--
--                        SMOKE  FRAG  RELOAD
--        LIGHT   PRIMARY       AIM
--        CROUCH  KNIFE         JUMP          FIRE
--
-- plus a small LOADOUT button top-right (next to SETTINGS). The bottom-center slot bar is also
-- tappable (EquipSlot). The left half of the screen stays free for Roblox's thumbstick.
-- FIRE is a non-Active Frame tracked through UserInputService.TouchStarted/TouchEnded so the same
-- touch still drags the camera (fire and look with one thumb). FIRE does what the held item does:
-- primary / held grenade -> SetFiring (grenades charge while held), knife -> Melee,
-- FRAG / SMOKE -> BeginThrow on press, ReleaseThrow on lift.
-- Roblox's default jump button is hidden because JUMP sits in the cluster instead.
-- WeaponController is reached through UI/Weapon (lazy, guarded).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local UIKit = require(UI:WaitForChild("UIKit"))
local MatchStore = require(UI:WaitForChild("MatchStore"))
local Weapon = require(UI:WaitForChild("Weapon"))

local MobileController = {}

type Button = { Root: GuiObject, Label: TextLabel, Stroke: UIStroke }

local gui: ScreenGui
local cluster: Frame
local loadoutButton: TextButton
local buttons: { [string]: Button } = {}
local fire: Button
local firingTouch: InputObject? = nil
local firingPrimary = false
local touchMode = false

-- Centers measured from the bottom-right corner of the cluster, at the 1000x500 reference size.
local LAYOUT = {
	Fire = { X = 80, Y = 90, D = 104 },
	Jump = { X = 190, Y = 46, D = 62 },
	Aim = { X = 190, Y = 140, D = 66 },
	Reload = { X = 80, Y = 196, D = 54 },
	Frag = { X = 150, Y = 232, D = 50 },
	Smoke = { X = 222, Y = 240, D = 50 },
	Primary = { X = 288, Y = 150, D = 56 },
	Knife = { X = 288, Y = 62, D = 56 },
	Light = { X = 376, Y = 114, D = 46 },
	Crouch = { X = 376, Y = 40, D = 48 },
}

local function setActive(b: Button, active: boolean, color: Color3?)
	local c = color or Theme.Colors.White
	b.Root.BackgroundColor3 = if active then c else Theme.Colors.Panel
	b.Root.BackgroundTransparency = if active then 0.75 else 0.5
	b.Stroke.Color = if active then c else Theme.Colors.White
	b.Stroke.Transparency = if active then 0.15 else 0.65
	b.Label.TextColor3 = if active then Theme.Colors.White else Theme.Colors.Text
	b.Label.TextTransparency = 0
end

local function setLocked(b: Button, locked: boolean)
	if locked then
		b.Root.BackgroundTransparency = 0.8
		b.Stroke.Transparency = 0.85
		b.Label.TextTransparency = 0.6
	end
end

local function makeButton(name: string, text: string, isFire: boolean?): Button
	local spec = (LAYOUT :: any)[name]
	local props = {
		Name = "Btn_" .. name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -spec.X, 1, -spec.Y),
		Size = UDim2.fromOffset(spec.D, spec.D),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Parent = cluster,
	}
	local root: GuiObject
	if isFire then
		root = UIKit.new("Frame", props)
		root.Active = false
	else
		root = UIKit.new("TextButton", props)
		local tb = root :: TextButton
		tb.Text = ""
		tb.AutoButtonColor = false
	end
	UIKit.corner(UDim.new(0.5, 0)).Parent = root
	local stroke = UIKit.stroke(Theme.Colors.White, 0.65, if isFire then 2 else 1)
	stroke.Parent = root
	local label = UIKit.text(text, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 0.4),
		TextSize = if isFire then Theme.TextSize.Body else Theme.TextSize.Tiny,
		FontFace = Theme.Fonts.Bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 1,
		Parent = root,
	})
	local b = { Root = root, Label = label, Stroke = stroke }
	buttons[name] = b
	return b
end

local function bind(name: string, onPress: () -> (), onRelease: (() -> ())?)
	local root = buttons[name].Root :: TextButton
	root.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			onPress()
			buttons[name].Root.BackgroundTransparency = 0.3
			task.delay(0.12, function()
				MobileController:Refresh()
			end)
		end
	end)
	if onRelease then
		-- track the pressing touch globally: it may slide off the button before lifting
		local pressing: InputObject? = nil
		root.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch then
				pressing = input
			end
		end)
		UserInputService.TouchEnded:Connect(function(input: InputObject)
			if input == pressing then
				pressing = nil
				onRelease()
			end
		end)
	end
end

local function humanoid(): Humanoid?
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function stopFiring()
	if firingTouch then
		firingTouch = nil
		if firingPrimary then
			Weapon.call("SetFiring", false)
		end
		firingPrimary = false
	end
	if fire then
		setActive(fire, false)
	end
end

local function startFiring(touch: InputObject)
	firingTouch = touch
	setActive(fire, true)
	local held = Weapon.state().Held
	firingPrimary = false
	if held == "Knife" then
		if not Weapon.call("Melee") then
			Weapon.call("SetFiring", true) -- in case Combat routes the knife through SetFiring
			firingPrimary = true
		end
	else
		-- gun fires; a held grenade charges until the touch ends (stopFiring releases it)
		Weapon.call("SetFiring", true)
		firingPrimary = true
	end
end

local function insideFire(pos: Vector3): boolean
	local root = fire.Root
	if not (cluster.Visible and gui.Enabled) then
		return false
	end
	local center = root.AbsolutePosition + root.AbsoluteSize / 2
	local radius = root.AbsoluteSize.X / 2 * 1.15 -- slightly generous for thumbs
	return (Vector2.new(pos.X, pos.Y) - center).Magnitude <= radius
end

-- Keep Roblox's own jump button hidden (we provide JUMP in the cluster).
local function hideDefaultJump()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
	local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
	local jump = frame and frame:FindFirstChild("JumpButton")
	if jump and jump:IsA("GuiObject") then
		jump.Visible = false
		if not jump:GetAttribute("ShiftHidden") then
			jump:SetAttribute("ShiftHidden", true)
			jump:GetPropertyChangedSignal("Visible"):Connect(function()
				if touchMode and jump.Visible then
					jump.Visible = false
				end
			end)
		end
	end
end

local function hud(): any
	local mod = script.Parent:FindFirstChild("HudController")
	if not mod then
		return nil
	end
	local ok, result = pcall(require, mod)
	return if ok then result else nil
end

function MobileController:Refresh()
	if not fire then
		return
	end
	local s = Weapon.state()
	local carrying = s.Carrying ~= nil
	local primaryHeld = s.Held == "AK" or s.Held == "Sniper"

	setActive(buttons.Aim, s.Aiming or s.Scoped)
	buttons.Aim.Label.Text = if s.Primary == "Sniper" then "SCOPE" else "AIM"
	setLocked(buttons.Aim, not primaryHeld)
	setActive(buttons.Light, s.Flashlight, Theme.Colors.Amber)
	setActive(buttons.Crouch, s.Crouched)
	setActive(buttons.Reload, s.Reloading)
	setLocked(buttons.Reload, not primaryHeld)
	setActive(buttons.Jump, false)

	buttons.Primary.Label.Text = if s.Primary == "Sniper" then "BOLT-7" else s.Primary
	setActive(buttons.Primary, primaryHeld)
	setLocked(buttons.Primary, carrying)
	setActive(buttons.Knife, s.Held == "Knife", if carrying then Theme.teamColor(s.Carrying) else nil)

	buttons.Frag.Label.Text = if carrying then "DROP" else "FRAG " .. tostring(s.Frags)
	setActive(buttons.Frag, s.Held == "Frag" and not carrying)
	setLocked(buttons.Frag, not carrying and s.Frags <= 0)
	buttons.Smoke.Label.Text = "SMOKE " .. tostring(s.Smokes)
	setActive(buttons.Smoke, s.Held == "Smoke")
	setLocked(buttons.Smoke, carrying or s.Smokes <= 0)

	if not firingTouch then
		setActive(fire, false)
	end
	fire.Label.Text = if s.Held == "Knife"
		then "SLASH"
		elseif s.Held == "Frag" or s.Held == "Smoke" then "THROW"
		else "FIRE"
end

local function applyVisibility()
	local hum = humanoid()
	local alive = hum ~= nil and hum.Health > 0
	local show = touchMode and alive and MatchStore.Phase ~= "Ended"
	gui.Enabled = touchMode
	cluster.Visible = show
	loadoutButton.Visible = touchMode and MatchStore.Phase ~= "Ended"
	if not show then
		stopFiring()
	end
	if touchMode then
		hideDefaultJump()
	end
end

function MobileController:Init()
	gui = UIKit.screenGui("ShiftMobile", 8)
	gui.Enabled = false
	cluster = UIKit.new("Frame", {
		Name = "Cluster",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -6, 1, -6),
		Size = UDim2.fromOffset(410, 270),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.autoScale(cluster)

	fire = makeButton("Fire", "FIRE", true)
	makeButton("Jump", "JUMP")
	makeButton("Aim", "AIM")
	makeButton("Reload", "RELOAD")
	makeButton("Frag", "FRAG")
	makeButton("Smoke", "SMOKE")
	makeButton("Primary", "AK")
	makeButton("Knife", "KNIFE")
	makeButton("Light", "LIGHT")
	makeButton("Crouch", "CROUCH")

	-- LOADOUT sits left of SettingsController's SETTINGS button (same anchor and scale, so they
	-- line up at any screen size).
	local top: Frame = UIKit.new("Frame", {
		Name = "TopRight",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(180, 26),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.autoScale(top)
	loadoutButton = UIKit.button("LOADOUT", {
		Name = "LoadoutButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -92, 0, 0),
		Size = UDim2.fromOffset(84, 26),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colors.TextDim,
		BackgroundTransparency = 0.6,
		Parent = top,
	}, function()
		local h = hud()
		if h and type(h.ToggleLoadout) == "function" then
			h:ToggleLoadout()
		end
	end)
end

function MobileController:Start()
	bind("Aim", function()
		local s = Weapon.state()
		Weapon.call("SetAiming", not (s.Aiming or s.Scoped))
	end)
	bind("Reload", function()
		Weapon.call("Reload")
	end)
	-- hold to charge, release to throw; while carrying the flag this button is DROP
	bind("Frag", function()
		if Weapon.state().Carrying then
			Weapon.call("DropFlag")
		else
			Weapon.call("BeginThrow", "Frag")
		end
	end, function()
		Weapon.call("ReleaseThrow")
	end)
	bind("Smoke", function()
		Weapon.call("BeginThrow", "Smoke")
	end, function()
		Weapon.call("ReleaseThrow")
	end)
	bind("Primary", function()
		Weapon.call("EquipSlot", "Primary")
	end)
	bind("Knife", function()
		Weapon.call("EquipSlot", "Knife")
	end)
	bind("Light", function()
		Weapon.call("ToggleFlashlight")
	end)
	bind("Crouch", function()
		Weapon.call("ToggleCrouch")
	end)
	bind("Jump", function()
		local hum = humanoid()
		if hum then
			hum.Jump = true
		end
	end)

	UserInputService.TouchStarted:Connect(function(touch: InputObject)
		if firingTouch == nil and insideFire(touch.Position) then
			startFiring(touch)
		end
	end)
	UserInputService.TouchEnded:Connect(function(touch: InputObject)
		if touch == firingTouch then
			stopFiring()
		end
	end)

	-- Touch mode follows the last input device (phones, tablets, Studio's device emulator).
	touchMode = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	UserInputService.LastInputTypeChanged:Connect(function(t: Enum.UserInputType)
		if t == Enum.UserInputType.Touch then
			touchMode = true
		elseif
			t == Enum.UserInputType.Keyboard
			or t == Enum.UserInputType.MouseMovement
			or t == Enum.UserInputType.MouseButton1
			or t.Name:match("^Gamepad")
		then
			touchMode = false
		end
		applyVisibility()
	end)

	local function onCharacter(character: Model)
		local hum = character:WaitForChild("Humanoid", 10)
		if hum and hum:IsA("Humanoid") then
			hum.Died:Connect(applyVisibility)
		end
		applyVisibility()
		MobileController:Refresh()
	end
	Players.LocalPlayer.CharacterAdded:Connect(onCharacter)
	if Players.LocalPlayer.Character then
		task.spawn(onCharacter, Players.LocalPlayer.Character)
	end

	Weapon.Changed:Connect(function()
		MobileController:Refresh()
	end)
	MatchStore.PhaseChanged:Connect(applyVisibility)
	applyVisibility()
	MobileController:Refresh()
end

return MobileController
