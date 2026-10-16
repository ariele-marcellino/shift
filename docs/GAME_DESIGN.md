# SHIFT — Game Design (v0.1)

> **"You can learn the map. But the map learns the match."**
> A team shooter in a dim, liminal facility that is permanently changed by every match.

Status: concept, developed in parallel with *Airport Security Simulator*. Nothing built yet.
Owner: ArivoLabs. Last updated: 2026-10-09.

---

## 1. Pitch

Two teams fight over a facility that feels familiar but wrong: endless yellow office corridors,
humming fluorescent tubes, rooms that are pitch black except for the light spilling from their
doorways. Every capture **shifts** the facility (a corridor seals, a tunnel opens), and anything a
team breaks **stays broken for the rest of the match**. No two matches end on the same map.

**One-line pitch for thumbnails and the store page:** *Capture the flag in a facility that changes
every time you score.*

**Audience:** teens and young adults (13–25), which matches who new Roblox experiences reach first
(16+ until passing review). Content target: **Moderate** violence (realistic firearm, no gore),
eerie but not horror.

---

## 2. Game mode: Capture the Flag first, Search & Destroy later

The original concept was 5v5 Search & Destroy. Recommendation: **launch with Capture the Flag
("Core Run")** and keep Search & Destroy as a later ranked mode.

| | Capture the Flag (launch mode) | Search & Destroy (later, ranked) |
|---|---|---|
| Lives | Respawn (short timer) | One life per round |
| Waiting | Almost none | Dead players spectate for up to 3 min |
| Players needed | Works 3v3 to 6v6, drop-in/drop-out | Needs full, stable 5v5 teams |
| New / younger players | Forgiving, always in the action | Punishing, high skill floor |
| Bots | Easy to fill empty slots | Bots feel bad in high-stakes rounds |
| Tension | Moment-to-moment chases | Very high per round |

The deciding factor is **lobby liquidity**: a new game has few players online at once. CTF still
works with 6 players and people joining or leaving mid-match; one-life 5v5 does not.

### Core Run rules (CTF variant)

- Each team has a **Core** (the "flag": a glowing canister) in its base room.
- Steal the enemy Core and carry it back to your own base while your Core is home → **capture**.
- **Carrier rule (decided):** the carrier can shoot, but **with the AK drawn they move extremely
  slowly** (about 35% speed). **Holstered, they move at normal speed** but can't fight back. Every
  carry becomes a choice: run, or turn and fight. The Core glows, so the carrier is the brightest
  thing in a dark room, which ties the flag directly into the lighting system.
- A dropped Core returns home after 20 s or when a defender touches it.
- **Every capture triggers a Facility Shift** (see §4). Scoring changes the map for both teams.
- Match: first to 3 captures or 12 minutes. Respawn 5 s (+1 s per death streak, capped at 8 s).
- Team size: **3v3 at launch (decided)**; 4v4+ later; **bots fill empty slots** (see §8).
- Camera: **first-person (decided)**.

---

## 3. Lighting: the signature look

The game's identity is **dim light and darkness**: most of the facility is barely lit, and light
is information.

### Light zones

| Zone | Look | Gameplay role |
|---|---|---|
| **Lit corridors** | Weak, flickering fluorescent tubes; sickly yellow; long shadows | Main routes; you see and are seen |
| **Dim rooms** | Only every third tube works; deep corners | Ambush spots; flashlights matter |
| **Dark rooms** | No ceiling light at all. The only light is a small lamp **above each doorway** (exit-sign green or caged bulb) | The signature space. Doorways become silhouettes; anyone entering is backlit for a moment |
| **Base rooms** | Each team's Core room in its team color (cold blue / warm red) | Orientation; you always know where home is |

**Doorway lights are the key rule:** in dark rooms players stand in darkness but are clearly
silhouetted when they cross a lit doorway. Holding an angle on a doorway is strong; crossing one is
a risk. Simple to understand, and it creates tactics without any extra system.

### Player light

- **Flashlight** (toggle, [F]): lets you see in dark rooms, but the beam is visible to everyone
  and gives away your position. Classic risk/reward.
- **Muzzle flash** briefly lights the shooter and nearby walls. Firing in the dark reveals you.
- **The Core** glows: carriers are visible in the dark, so escorting the carrier matters.

### Breakable lights

- Doorway lamps and selected fluorescent tubes can be shot out. **They stay out for the rest of
  the match** (persistent damage, §4).
- Over a match the facility gets darker in the places where fights happened. Defenders darken
  approaches to their Core; attackers knock out the lamps that silhouette them.
- Balance guard: base rooms and spawn corridors have **unbreakable emergency lights**, so the map
  never becomes fully black.

### Art direction

- Palette: desaturated yellows and beiges, grey carpet, off-white ceiling tiles, green exit lamps,
  team colors only at the bases.
- Fluorescent flicker (subtle, not seizure-inducing; flicker rate capped and a **reduce flicker**
  setting in options).
- Fog and dust particles in light beams; light shafts from doorways into dark rooms.
- Sound sells the atmosphere as much as light: buzzing tubes, distant ventilation, a faint PA chime
  before every shift.

---

## 4. The changing facility

Two separate systems. Keep them distinct; players need to understand both.

### A. Persistent damage (player-caused, stays all match): the main feature

Only selected, clearly marked objects are destructible:

| Object | How | Result |
|---|---|---|
| Doorway lamps, ceiling tubes | Shoot them | Area goes dark for the rest of the match |
| Weak drywall panels (marked with cracks / taped seams) | Breaching charge (added in v0.3) | New opening, new angle |
| Vent covers | Melee | Crawlspace route opens |
| Glass partitions | Shoot | See-through and shoot-through |
| Office barricades (desks, shelves) | Push / break | Route opens or closes |

At match end, a **"facility report"** shows the before/after map: which walls fell, which rooms
went dark. It's a shareable screenshot moment.

### B. Facility Shifts (system-caused, on every capture)

- A PA chime and a 5 s warning: *"Facility shift in 5… Sector C sealed."* Shifts are **announced**,
  never mid-fight surprises.
- Each shift applies 1–2 changes from a **balanced, mirrored list**, so both teams are affected
  equally:
  - a security door seals or unseals
  - a maintenance tunnel opens
  - a corridor section's power fails (goes dark) or is restored
  - a stairwell or elevator becomes usable
- Shifts must never trap a player, block the last route to a Core, or spawn walls inside players.
  Shift-able spots are designed in advance as "hinges" in the layout.

---

## 5. Weapons and equipment

Deliberately tiny arsenal for launch: **everyone has the same loadout**, so skill decides fights
and balancing stays simple.

### AK-47 (the only primary at launch)

- Full auto, high damage, real recoil: a vertical climb, then a horizontal wander. Learnable,
  rewards burst fire and tap-firing at range.
- Values to tune: ~4 body shots / 1 headshot to kill, 30-round magazine, ~2.4 s reload,
  ADS (aim down sights) slows movement.
- Bright muzzle flash (it matters in the dark, §3) and a loud, distinctive report.
- Mastery levels unlock cosmetic skins, charms and kill effects only, never stats.

### Smoke grenade (2 per life)

- Thrown arc with a bounce; a dense cloud for ~12 s.
- **Interacts with light:** smoke catches the doorway lamps and flashlight beams and glows. A
  smoked doorway stops being a silhouette spot, so smoke is the tool for crossing lit doorways
  safely and for covering a Core carrier.
- In dark rooms, a flashlight shone into smoke turns it into a glowing wall that blinds both sides.

### Utility (all players)

- Flashlight (see §3).
- Melee (knife bash or rifle butt) for vent covers and finishing.

### Later (post-test)

Pistol sidearm, breaching charge, motion sensor, portable light, a shotgun for close-quarters dark
rooms. Each needs a clear role in the light/dark system before it's added.

---

## 6. Sound

Sound is gameplay, not decoration:

- Footsteps by surface (carpet is quiet, tile and metal are loud, water splashes); crouch-walk is
  near silent.
- Doors, vent covers and breaking lights make distinct sounds that travel.
- Reload and grenade-pin sounds can be heard nearby.
- Ambient bed: fluorescent hum, HVAC, distant machinery, a faint PA. Ambient sound must **never**
  imitate player footsteps or gunshots in competitive modes; fake player sounds are frustrating.
- Directional audio (Roblox 3D sound with emitter positions) must be trustworthy. Test with
  headphones early.

---

## 7. Map: "Level 0 — Office Annex" (launch map)

- Mirrored layout (fair for both teams), ~3 lanes between bases:
  - **Left: Cubicle Maze.** Dim; short sightlines; lots of cover.
  - **Middle: The Long Hall.** Lit; long sightlines; the AK duel lane; doorway rooms branch off it.
  - **Right: Maintenance.** Dark rooms with doorway lamps, vents, a flooded basement section
    (slow, loud splashing).
- 2–3 **shift hinges** per side (sealable doors, openable tunnels), mirrored.
- 4–6 breakable doorway lamps per side; 2 weak walls per side (once breaching exists).
- Built from modular greybox pieces (wall, door frame, ceiling tile, tube light) so new rooms are
  quick to assemble and Roblox **streaming** keeps it light on phones.

---

## 8. Bots and lobbies

Filling matches is the #1 risk for any team shooter on a new Roblox game.

- **Bots fill every empty slot**, and leave when a real player joins. Matches start immediately.
- Bot behaviour (simple, honest): follow lane paths, fight using line of sight with a reaction
  delay and deliberate inaccuracy, go for the Core and return dropped Cores. They use flashlights
  in dark rooms, which keeps them readable.
- Drop-in/drop-out: players join running matches and auto-balance to the smaller team.
- Party support: friends joining together stay on the same team.
- Later: private servers for clans and scrims (cheap to offer, good revenue).

---

## 9. Progression and monetization

**Rule: never sell power.** Same AK for everyone; skill decides.

- Account level (XP from playing, objectives, captures, wins).
- **AK-47 mastery** (levels 1–100): skins, charms, kill effects, titles.
- **Map mastery:** challenges like "capture through the Maintenance route" or "darken all lamps on
  your side" unlock map-themed cosmetics.
- Cosmetics: weapon skins, gloves, masks, uniforms, flashlight beam colors, Core carrier trails,
  capture celebrations, player cards.
- Monetization: cosmetic shop with rotating stock, a season pass (cosmetic-only), private servers.
- Paid random items (crates) only if odds are shown, per Roblox policy; prefer a direct-purchase
  shop.

---

## 10. Technical notes (Roblox)

- **Shooting:** client-side firing for responsiveness, **server validates every hit** (line of
  sight, distance, rate of fire, ammo, plausible angle) with simple lag compensation. Never trust
  client damage.
- **Anti-cheat reality check:** darkness is **rendered on the client**. An exploiter can make their
  own screen fully bright, and aimbots exist. Design darkness as *tension and readability*, not as
  a hard information wall. Doorway silhouettes and flashlights still work against cheaters, but
  don't build anything that only works if the client can't see. Add server-side sanity checks
  (impossible headshot rates, snapping, speed) and easy reporting.
- **Lighting performance:** use Future lighting; budget shadow-casting lights carefully (they're
  expensive, especially on phones). Most fluorescent tubes should be non-shadow lights; reserve
  shadows for doorway lamps and flashlights. Test darkness on low graphics quality, since
  low-quality phones render differently and the game must stay fair and readable.
- **Destruction:** persistent damage is server state (a list of broken object IDs) replicated to
  clients, so late joiners see the same damaged map.
- **Shifts:** pre-built hinge variants swapped in and out (enable/disable models), not runtime
  geometry generation.
- **Mobile:** auto-fire assist option, large fire/aim/smoke buttons, simplified HUD.

---

## 11. MVP: the one-week test

Prove two things before building more:

1. **Does the AK feel good to shoot** (feel, recoil, hit registration) in dim corridors?
2. **Is lasting damage plus darkness actually fun** after several captures?

Build only:
- one small greybox map (half of Level 0), mirrored
- 3v3 with bots filling slots (6 players total)
- AK-47 + smoke grenade + flashlight
- Core Run rules (steal, carry, capture, drop/return)
- breakable doorway lamps that stay broken for the whole match
- **one** shift hinge that toggles on each capture
- basic round HUD and end screen with the before/after "facility report"

No progression, no shop, no saving in the test.

**Success test:** after 3 matches, testers want another one, and they mention the map changing or
the dark rooms without being asked.

---

## 12. Roadmap (if the test passes)

| Version | Adds |
|---|---|
| v0.1 | The one-week test (above) |
| v0.2 | Full Level 0 map, 4v4, better bots, saving, account level, AK mastery |
| v0.3 | Breaching charge + weak walls, vents, glass, facility report screenshot |
| v0.4 | Cosmetic shop, season pass, private servers, second map ("Parking Level P3") |
| v0.5 | Search & Destroy ranked mode (one life, 5v5), sidearm, motion sensor |
| v0.6+ | Facility events (power failure, flooding, lockdown), optional lore terminals |

---

## 13. Decisions

- Camera: first-person.
- Team size: 3v3 first.
- ~~Carrier: can shoot; gun drawn = extremely slow, holstered = normal speed.~~ (replaced in v2)
- **v2 (after first playtest, 2026-10-10):** carrier is locked to the knife (fast, can't shoot);
  knife is always the fastest way to move; weapons: AK-47, AWP-style bolt sniper, knife, frag,
  smoke; loadout menu (once at start, then [B]); flat 3 s respawn; spawns further from Cores;
  no direct face-off sightlines between bases; more tactical cover (head glitches, boosts);
  wallbangs through some thin walls; lights randomly go on/dim/off during a match.

## 14. Open questions

- How dark is too dark on a phone in daylight? (Needs a real-device test.)
- Does every capture shift the map, or only every second capture?
- Final name: **SHIFT** is the strongest; check for existing Roblox experiences with the same name
  before committing.
