# Portable Train Horn Gun (`trainhorn_gun`)

A handheld train horn for **Luanti (formerly Minetest)**. Left-click to fire a horn blast.
Mobs and players in a cone in front of you are **stunned**: they are slowed, hear a ringing
stun sound and get a small knockback. By default the horn does **no damage**. A rate-limited
`/victoryhorn` chat command plays a stadium goal-horn celebration.

By [Train Horn](https://train-horn.com/), an independent reference site about train horns.

## Features

- **Tool `trainhorn_gun:horn_gun`**. On use it plays a positional horn blast (`trainhorn_gun_blast.ogg`).
  - Targets are mobs and players inside a cone: 8 nodes long with a 30° half-angle by default.
    A target counts if its body centre or its head is inside the cone.
    By default solid nodes block the blast (line of sight).
  - **Stun**: players get `set_physics_override` speed × 0.3 for up to 3 s.
    The stun is always restored when it ends, and also when the player leaves, dies, respawns or the server shuts down.
    Mobs have their horizontal velocity damped every server step while stunned.
    `luaentity._trainhorn_stun_until` is set, so mob mods can react to it.
  - **Distance falloff**: the stun gets weaker with distance, following the inverse-square law (−6.02 dB per doubling of distance).
    This is the same free-field model that the [decibel-at-distance calculator](https://train-horn.com/tools/decibel-distance/) uses.
    The strength is linear in dB between 1 node (full stun) and the max range (15 % by default).
    So stun length, slowdown, knockback and optional damage all fall off together.
    It is a physics approximation for gameplay, not a measurement.
  - Cooldown of 2 s per player. The tool wears out after 200 blasts (no wear in creative mode).
  - Dropped items (`__builtin:*`) and entities with the `immortal` armor group are ignored.
    Players are only affected when `enable_pvp` is on.
- **`/victoryhorn`** (needs `interact`): plays `trainhorn_gun_victory.ogg` at your position.
  It is rate limited to once per 30 s per player.
  An optional setting also plays it when a player defeats another player.
- **Crafting** (only when a `default` mod is present, e.g. Minetest Game):

  |                         |                 |               |
  |-------------------------|-----------------|---------------|
  |                         | steel ingot     | steel ingot   |
  | mese crystal fragment   | copper ingot    | steel ingot   |
  | stick                   |                 |               |

  Without `default` the mod still loads. Get the tool with `/giveme trainhorn_gun:horn_gun`.

## Settings (`settingtypes.txt`, Settings → All settings → Mods → trainhorn_gun)

| Setting | Default | Meaning |
|---|---|---|
| `trainhorn_gun_range` | 8 | Blast range in nodes |
| `trainhorn_gun_cone_angle` | 30 | Cone half-angle in degrees |
| `trainhorn_gun_stun_duration` | 3 | Stun length in seconds at point blank |
| `trainhorn_gun_stun_speed` | 0.3 | Speed multiplier at point blank |
| `trainhorn_gun_damage` | 0 | HP damage at point blank (0 = stun only) |
| `trainhorn_gun_knockback` | 3 | Knockback speed at point blank (0 = off) |
| `trainhorn_gun_cooldown` | 2 | Seconds between blasts |
| `trainhorn_gun_uses` | 200 | Blasts before the tool breaks (0 = unbreakable) |
| `trainhorn_gun_min_strength` | 0.15 | Strength at the edge of the range |
| `trainhorn_gun_affect_players` | true | Allow stunning players (also needs `enable_pvp`) |
| `trainhorn_gun_require_los` | true | Solid nodes block the blast |
| `trainhorn_gun_victory_cooldown` | 30 | Seconds between `/victoryhorn` uses |
| `trainhorn_gun_victory_on_kill` | false | Victory horn when a player defeats another player |

## API for other mods

```lua
trainhorn_gun.blast(player)               -- fire as if the player used the tool
trainhorn_gun.stun(obj, strength, dir)    -- strength 0..1
trainhorn_gun.is_stunned(obj)
trainhorn_gun.restore_player(player_or_name)
trainhorn_gun.victory(player)             -- returns ok, message
trainhorn_gun.falloff.level_at(130, 16)   -- 130 dB at 1 m -> ~105.9 dB at 16 m
```

`falloff.lua` and `cone.lua` are pure Lua with no engine calls, so you can reuse them anywhere.

## Tests

`sh run_tests.sh` (from the source repository) runs:
- the unit tests for `falloff.lua` and `cone.lua`;
- an integration test that loads `init.lua` against a mocked `minetest` API, fires the tool at fake players and mobs, and checks who is stunned and that everyone is restored;
- `luacheck`;
- a headless Luanti server that loads the mod in a test world and runs in-engine checks (it spawns real entities and checks the stun and its expiry).

Tested on Luanti 5.18.0 (LuaJIT) and on Lua 5.5. Requires Luanti/Minetest 5.4 or newer.

## License

- **Code** (`*.lua`, tests): MIT. See `LICENSE`.
- **Media** (textures and sounds): CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/).
  - `textures/trainhorn_gun_horn_gun.png`: an original 16×16 pixel-art icon by Train Horn.
  - `sounds/trainhorn_gun_blast.ogg`, `sounds/trainhorn_gun_stun.ogg`, `sounds/trainhorn_gun_victory.ogg`:
    Sound effects generated with ElevenLabs for Train Horn (https://train-horn.com/).

Source: https://github.com/train-horn/luanti-trainhorn-gun
