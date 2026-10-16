# SHIFT — One-Week Test Build: Workstream Contract

Read `docs/GAME_DESIGN.md` for the vision (§3 lighting, §4 changing facility, §5 weapons, §11 MVP).
This file is the **binding contract** for the four parallel workstreams. Only edit files you own
(§7). If something here is unworkable, build the closest sensible thing and list it under
"Contract issues" in your final report.

**The test answers two questions:** does the AK feel good in dim corridors, and is lasting damage
plus darkness fun? Polish shooting feel and lighting mood over breadth. No saving, shop or
progression.

## 1. Rules recap

- 3v3, Blue vs Red (Roblox `Teams`), bots fill empty slots; a real player joining replaces a bot.
- First-person (`CameraMode = LockFirstPerson`, set in project file). R15 characters.
- Core Run: steal the enemy Core from its base pedestal, carry it to your own base pedestal while
  your Core is home → capture. First to 3 or 12 min. Dropped Core returns after 20 s or when a
  defender touches it. Carrier dies → Core drops where they died.
- **Carrier movement:** AK drawn → `Tuning.Movement.CarrierDrawn` (very slow); holstered →
  normal speed, can't fire. Toggle with [1] / [Q] / mobile button. Not carrying: holstering just
  lowers the gun (rarely useful).
- Every capture → 5 s `ShiftAnnounce` → the next shift hinge state applies (§4).
- All numbers: `src/shared/Config/Tuning.luau` (coordinator-owned).

## 2. Remotes (`src/shared/Remotes.luau`, done)

Client → Server:
| Remote | Args |
|---|---|
| ClientReady | — |
| Fire | `shotId: number, origin: Vector3, direction: Vector3, clientTime: number` (one per bullet; server re-casts and validates: ammo, fire rate, drawn, alive, origin within 6 studs of head, direction unit) |
| Reload | — |
| SetWeaponDrawn | `drawn: boolean` |
| ThrowSmoke | `origin: Vector3, direction: Vector3` |
| SetFlashlight | `on: boolean` |
| SetAiming | `aiming: boolean` (affects speed + server spread) |

Server → Client:
| Remote | Args |
|---|---|
| MatchState | `{ Phase: "Warmup"\|"Live"\|"Ended", TimeLeft, Score: {Blue, Red}, CaptureLimit, Cores: { Blue: CoreInfo, Red: CoreInfo } }` with `CoreInfo = { State: "Home"\|"Carried"\|"Dropped", CarrierName: string?, CarrierUserId: number?, Position: Vector3, ReturnIn: number? }` — all clients, 4×/s while anything moves, else 1×/s |
| ShotFx | `shooterId: string, origin: Vector3, hitPos: Vector3, hitKind: "World"\|"Player"\|"Lamp"\|"Smoke"?` — to all except shooter (tracer, muzzle flash light, sound at origin) |
| HitConfirm | `{ Kind: "Body"\|"Head", Killed: boolean }` — to shooter |
| Damaged | `{ Amount, FromPosition: Vector3, Health }` — to victim |
| KillFeed | `{ Killer: string, KillerTeam: string, Victim: string, VictimTeam: string, Headshot: boolean, CarrierKill: boolean }` — all |
| ShiftAnnounce | `{ Seconds: number, Title: string, Detail: string }` — all (e.g. "FACILITY SHIFT", "Sector C sealed · Maintenance tunnel open") |
| FacilityReport | `{ Winner: string?, Score, BrokenLamps: {string}, TotalLamps: number, Shifts: { {Title, Detail} }, Mvp: {Name, Kills, Captures}?, Players: { {Name, Team, Kills, Deaths, Captures, Returns} }, MapSnapshot: { Lamps: { {Id, Position: Vector3, Broken: boolean} }, Hinges: { {Id, Position: Vector3, Size: Vector3, Open: boolean} }, Bounds: {Min: Vector3, Max: Vector3} } }` — all, at match end |
| RespawnTimer | `seconds: number` — to the dead player |
| Announce | `text: string, kind: "Info"\|"Good"\|"Bad"` |
| AmmoSync | `{ Mag, Reserve, Smokes }` — to owner after reload/respawn/server correction |

Character attributes (server-set, replicated): `Team` ("Blue"/"Red"), `WeaponDrawn` (bool),
`CarryingCore` (string? enemy team name), `Flashlight` (bool), `Aiming` (bool), `SpawnProtected`
(bool), `Bot` (bool on bot models). Names in every payload (KillFeed, CarrierName, report) are the
player's DisplayName or the bot's name. Bots are R15 NPC models in `workspace.Bots`, tagged `"Combatant"` like player characters
(server tags player characters too) so hit detection treats them the same.

## 3. Combat (owner: Combat)

- **Server** `CombatService`: validates `Fire`, raycasts with lag tolerance (simple: accept the
  client's hit if a server ray from the same origin/direction hits that target within a 4-stud
  tolerance of its current position), applies damage (head/body/limb from hit part name),
  falloff, kills (`Humanoid.Health = 0`), `HitConfirm`, `Damaged`, `KillFeed`, `ShotFx`,
  health regen, ammo state per combatant, reload timing, smoke clouds (server-spawned parts so all
  clients see them; smoke blocks bot vision via `CombatService:IsSmoked(a, b)`), flashlight as a
  replicated `SpotLight` on the character's head, muzzle light. Lamps: a ray hitting a part
  tagged `"BreakableLamp"` calls `WorldService:BreakLamp(lampId)`.
  **API for bots:** `CombatService:BotFire(botModel, targetPosition)` (applies Tuning.Bots error,
  fire rate, ammo, reload) and `CombatService:OnDeath: Signal(victimModel, killerModel?, headshot)`;
  `CombatService:GiveLoadout(model)` on spawn; `CombatService:SetDrawn(model, drawn)`.
- **Client** `WeaponController`: first-person viewmodel AK built from parts (recognisable AK
  silhouette: curved mag, wooden furniture, receiver), sway, bob, ADS (RMB / mobile button),
  recoil with recovery, spread, muzzle flash + local light, tracers, hit markers, reload and draw
  animations (CFrame-tweened), sounds (use pcall'd sound ids you can verify; otherwise leave a
  `Sounds` config table with `0` placeholders and no errors), smoke throw [G], flashlight [F],
  holster [1]/[Q], crouch [C]/[Ctrl]. Renders others' `ShotFx`. Mobile: fire, aim, reload, smoke,
  flashlight, holster buttons (UI owns layout; Combat exposes `WeaponController:Fire(down)` etc.
  — see §6).

## 4. World (owner: World)

- Greybox **half of "Level 0 — Office Annex"**, mirrored for Blue/Red, 3 lanes (Cubicle Maze /
  Long Hall / Maintenance with dark rooms and a shallow flooded section), base rooms with team
  colored light + Core pedestal, 3 spawn points per team inside each base, unbreakable emergency
  lights in bases/spawn corridors. Ceiling, so it's indoors. Modular pieces in
  `src/server/World/Pieces.luau`.
- **Lighting** per GAME_DESIGN §3: lit corridors (weak, slightly flickering fluorescents,
  non-shadow `SurfaceLight`/`PointLight`), dim rooms, **dark rooms lit only by doorway lamps**
  (shadow-casting `SpotLight`/`PointLight` above each doorway, green exit-sign tone or caged
  bulb). Atmosphere: `Atmosphere`/fog, dust particles near light shafts, ambient hum sounds
  (verified ids or placeholders). Flicker capped (≤ 2 Hz, subtle).
- `BreakableLamp` parts (tag, attribute `LampId`, contain the Light): `WorldService:BreakLamp(id)`
  → light off, glass "broken" look, spark particles once, stays broken for the match.
  `WorldService:ResetMatch()` restores everything.
- **Shift hinges** (2 per side, mirrored): pre-built models with states (e.g. security door
  sealed/open, maintenance tunnel closed/open, corridor power on/off). `WorldService:ApplyNextShift()
  -> { Title, Detail }` advances a balanced, mirrored sequence; never seals the last route to a
  Core; pushes any combatant out of a sealing volume. `WorldService:GetSnapshot()` returns the
  FacilityReport `MapSnapshot`.
- Navigation for bots: `WorldService:GetNavPoints() -> { {Id, Position, Links: {Id}, Dark: boolean} }`
  graph covering all three lanes (update links when hinges change) and
  `WorldService:IsDark(position) -> boolean`. Also `GetSpawns(team)`, `GetPedestal(team) -> CFrame`.
- Performance: anchored, part count under ~1500, shadow-casting lights under ~30.

## 5. Mode + Bots (owner: Mode)

- `TeamService`/`MatchService`: Teams, assignment (balance, real players replace bots), warmup →
  live → ended → reset loop, scoring, Core state machine (pickup by touching the pedestal Core /
  dropped Core within `PickupRadius`, carry welded glowing Core model on the carrier's back with a
  `PointLight`, drop on death, return, capture with own Core home), carrier speed rules
  (`WeaponDrawn` + `CarryingCore` → WalkSpeed per Tuning; also ADS/crouch speeds for everyone),
  capture → `ShiftAnnounce` → `WorldService:ApplyNextShift()`, respawn timers + spawn protection,
  `MatchState` broadcasts, `FacilityReport`, stats (kills/deaths/captures/returns), team uniforms
  (body colors / simple team-colored shirt parts so teams read in the dark; small team-colored
  shoulder light).
- `BotService`: R15 NPC bots (`Players:CreateHumanoidModelFromDescription` with a plain
  description, pcall + fallback rig) with `Bot` attribute; simple, honest AI: roles per bot
  (attacker / defender / roamer), move along World nav graph with `Humanoid:MoveTo`, perceive
  enemies by line of sight within `ViewDistanceLit/Dark` (dark rooms: only close, or if target's
  flashlight/muzzle flash/Core glow is visible), react after `ReactionSeconds`, shoot via
  `CombatService:BotFire`, use flashlight in dark rooms, steal/return/escort Cores, holster when
  carrying and no enemy is visible. Cheap: think at 5–10 Hz, not every frame.

## 6. UI (owner: UI)

Style: tactical, minimal, readable in the dark — thin white/grey text, team colors only for team
info, no cartoon styling, no emoji. Reuse `src/client/UI/UIKit.luau` + `Theme.luau` (copied
from the Airport Security project; UI may edit both here).
- HUD: crosshair (spread-aware, hidden while ADS), hit marker (head = distinct), damage direction
  indicator, health bar, ammo `Mag / Reserve`, smoke count, flashlight icon, holster state
  ("HOLSTERED — FULL SPEED" / "DRAWN — SLOW" when carrying), team score + capture pips, match
  timer, Core status for both teams (Home/Carried by X/Dropped + return countdown) with on-screen
  markers (enemy Core when dropped, your carrier, your stolen Core), kill feed, respawn timer,
  spawn protection, team list (Tab).
- Shift announcement: PA-style banner with countdown and detail line.
- End screen **Facility Report**: winner, scoreboard, MVP, and a top-down map drawn from
  `MapSnapshot` (lamps as dots: lit / broken; hinges open/sealed), plus "x of y lights destroyed",
  shift list. Screenshot-worthy.
- Warmup screen ("3v3 · first to 3 captures"), controls help overlay ([H]).
- Mobile: fire, aim, reload, smoke, flashlight, holster, crouch, jump buttons wired to
  `WeaponController` methods: `:SetFiring(bool)`, `:SetAiming(bool)`, `:Reload()`,
  `:ThrowSmoke()`, `:ToggleFlashlight()`, `:ToggleHolster()`, `:ToggleCrouch()` (Combat
  implements these; UI requires the controller lazily). Combat exposes local state via
  `WeaponController.State` (`Mag`, `Reserve`, `Smokes`, `Drawn`, `Aiming`, `Spread`, `Reloading`)
  and `WeaponController.Changed: Signal()`.
- Settings overlay: mouse/touch sensitivity, FOV slider (70–90), reduce flicker. Settings are
  local attributes on the LocalPlayer: `Setting_ReduceFlicker` (bool, read by World's client
  `AmbienceController`, which runs all light flicker client-side on lights with attribute
  `Flicker = true`), `Setting_Sensitivity` (number, read by WeaponController), `Setting_FOV`
  (number, read by WeaponController).

## 7. File ownership

| Workstream | Owns |
|---|---|
| World | `src/server/World/**`, `src/server/Services/WorldService.luau`, `src/client/Controllers/AmbienceController.luau` (client flicker/ambience) |
| Combat | `src/server/Services/CombatService.luau`, `src/server/Systems/Combat/**`, `src/client/Controllers/WeaponController.luau`, `src/client/Weapon/**` |
| Mode | `src/server/Services/MatchService.luau`, `TeamService.luau`, `BotService.luau`, `src/server/Systems/Mode/**`, `src/server/Systems/Bots/**` |
| UI | `src/client/Controllers/HudController.luau`, `ReportController.luau`, `MobileController.luau`, `SettingsController.luau`, `src/client/UI/**` |
| Coordinator | `docs/**`, `default.project.json`, `src/shared/**`, bootstraps |

Server bootstrap requires every ModuleScript in `src/server/Services` (Init all, then Start all).
Client bootstrap does the same for `src/client/Controllers` and then fires `ClientReady`.

---

# v2 CHANGES (2026-10-10) — these override anything above

User playtest feedback. Same ownership as §7. All numbers in `Tuning.luau` (updated: Movement,
Primaries, Sniper, Knife, Frag, Penetration, LightEvents, respawn 3 s, smoke 1 per life).

## V1. Weapons and loadout (Combat + Mode + UI)

- Slots: **[1] Primary** (AK or BOLT-7 Sniper, chosen in the loadout menu), **[2] Knife**,
  **[3] Frag**, **[4] Smoke**; [G] quick-throws frag, [T] quick-throws smoke, [Q] swaps to the last
  weapon, mouse wheel cycles. **The holster mechanic is removed** (remote `SetWeaponDrawn` is gone;
  use `EquipSlot(slot: "Primary"|"Knife"|"Frag"|"Smoke")`).
- Character attribute **`HeldWeapon`**: `"AK" | "Sniper" | "Knife" | "Frag" | "Smoke"` (server-set
  on validated EquipSlot). Plus `Scoped` (bool) for the sniper.
- **Movement speed by weapon** (Mode `Movement`, slowest applicable wins): Knife 20, AK 16, Sniper
  14, scoped 7, AK aiming 10, crouch 8, wading 10.
- **Knife:** `Melee()` remote; server does a short cone check (Range 6) for the closest enemy;
  45 damage front, instant kill from behind (backstab). Viewmodel knife + slash animation.
- **Sniper (AWP-style):** bolt-action, scope overlay with black vignette and crosshair (RMB),
  FOV `ScopeFOV`, near-zero spread scoped, big spread unscoped/moving, one-shot body/head, bolt
  animation, unscopes after each shot (re-scope on hold). Strong muzzle flash.
- **Frag grenade:** `ThrowFrag(origin, direction)`; server-simulated bouncing canister, explodes
  after `FuseSeconds`, radial damage with falloff, needs line of sight from blast centre (walls
  block; Penetrable walls do not transmit), breaks BreakableLamps in radius, self damage on, no team
  damage, KillFeed with `Weapon = "Frag"`. 1 per life.
- **Wallbanging:** bullets pass through parts tagged **`Penetrable`** (World tags thin drywall
  panels, wooden doors, cubicle partitions) up to `Penetration[weapon].MaxWalls`, losing damage
  per wall. Other walls stop bullets. ShotFx shows an exit hole/impact on both sides.
- KillFeed gets `Weapon: "AK"|"Sniper"|"Knife"|"Frag"` and `Wallbang: boolean`.
- **Loadout menu:** `SelectLoadout(primary)` (validated against `Tuning.Primaries`).
  Server→Client `LoadoutState { Primary, Options: {string}, AppliesNow: boolean }`. The choice
  applies **immediately if the player is alive, inside their spawn room and within 10 s of
  spawning**, otherwise on next spawn. UI shows the menu **once automatically** (first spawn of the
  session / first warmup) and otherwise **only when the player presses [B]** (mobile: LOADOUT
  button). It must never pop up on every spawn. Bots choose randomly (`Tuning.Bots.SniperChance`).

## V2. Core carrier (Mode + Combat + UI)

- Picking up a Core **forces the Knife** and **locks** weapon switching (Combat refuses EquipSlot
  other than Knife while `CarryingCore` is set; frag/smoke also locked). Carrier speed =
  `Tuning.Movement.Carrier` (18). Capture or drop restores the previous slot.
- The carrier can still knife. HUD carrier line: "CARRYING CORE · KNIFE ONLY".

## V3. Respawn (Mode)

Flat 3 s (Tuning). Spawn protection stays (2 s, cancelled by firing).

## V4. Map (World)

- **No direct face-off between teams:** there must be no straight line of sight from any spawn
  room or Core room to the enemy's spawn room or Core room, and the Long Hall must not be one
  straight sightline from base to base. Break it with offsets, L-bends, a staggered centre,
  pillars, a raised mezzanine or blockers. Add a startup check that raycasts between all spawn
  points / pedestals of opposite teams and warns if any ray is clear.
- **Keep the overall map size.**
- **Spawn further from Core:** each team's spawn room is moved away from its own Core room (a
  longer path, not just distance through a wall) so a 3 s respawn doesn't let defenders instantly
  re-defend; enemy spawns stay far from your Core too.
- **Tactical cover:** add many more objects that create shooter tactics: chest-high crates and
  desks for **head glitches** (stand behind, only head exposed when peeking over), stacked boxes
  you can jump onto (boost spots), half walls, pillars for peeking, a few windows/railings between
  rooms, a short raised walkway/stairs in the hall, doorway corners for jiggle peeks, vents that
  are jumpable shortcuts. Mirror everything.
- **Penetrable walls:** tag thin drywall sections, wooden doors and cubicle partitions
  `Penetrable` (visually distinct: lighter drywall / visible seams) — "only some walls".
- **Dynamic lights:** server `LightDirector` per `Tuning.LightEvents`: zones randomly switch
  On / Dim / Off with short flicker transitions, mirrored between halves, never below
  `MinLitShare`, never affecting base/spawn emergency lights; broken lamps stay broken.
  Broadcast `LightState { [zoneId]: "On"|"Dim"|"Off" }` (on change + on ClientReady) so the client
  AmbienceController and bots (`IsDark`) agree. Nav graph `Dark` flags update live.
  *(2026-10-13)* Map default is 25% dimmer (`Style.LightScale = 0.75`, fills exempt). Each change
  rolls a random level in its state's range (`LightEvents.Levels`); `LightState` now carries
  numbers `{ [zoneId]: level }`. Per-lamp drift (`LightEvents.Drift`, lamp attribute `Scale`,
  mirrored B/R) keeps single lamps sliding brighter/duller, weighted to Hall/Atrium/Junction.
  Fewer fixtures: hall 5/half (was 7), atrium 3 (was 4), corridor 4 (was 5), office 3/row (was 4).
- Re-run the nav graph and shift-hinge checks for the new layout.

## V5. UI

Loadout menu (V1), slot bar (1–4 with counts, current highlighted), knife/sniper crosshairs
(sniper: no crosshair unscoped beyond a dot; scope overlay is Combat's), frag count, KillFeed
weapon icons (drawn, not emoji) + wallbang marker, carrier line (V2), updated help ([B], slots,
G/T/Q), mobile: slot buttons, frag, knife, LOADOUT button; remove holster UI.
