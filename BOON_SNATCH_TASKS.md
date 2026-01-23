# Boon Snatch Implementation - Task List

## Project Vision & Pitch

**Why Pixel Art + AI?**
- **Fast Iteration**: Pixel art is quick to create/modify, perfect for prototyping
- **AI Acceleration**: AI helps with code generation, game logic, and rapid feature development
- **Your Skills**: You're a JS dev - you understand systems, architecture, and can debug. AI handles the game dev learning curve.
- **His Vision**: He has the game design ideas - MOBA mechanics, boon systems, PvPvE flow
- **Perfect Combo**: You build the infrastructure, AI helps with game-specific code, he designs the fun

**Why This Approach Works:**
1. **LOVE2D is Simple**: Lua is easy, LOVE2D API is straightforward, perfect for rapid prototyping
2. **AI is Your Game Dev Co-Pilot**: AI writes the boilerplate, you architect the systems
3. **Pixel Art is Fast**: No 3D modeling, no complex animations - just sprites and fun gameplay
4. **Iterate Quickly**: Change boon effects, spawn rates, map layout in minutes, not days
5. **Prove the Concept**: Build the core loop (find chest → get boon → kill player → steal boons) fast, then polish

**The Pitch to Your Brother:**
> "We're building a pixel version because it's fast to iterate. Every time you have an idea for a boon or mechanic, we can implement it in hours, not weeks. AI helps me write the game code I don't know, and you focus on what makes it fun. Once we prove the core loop works, we can always upgrade the graphics later. But first, let's make it FUN."

---

## Game Concept

**Boon Snatch** is a PvPvE MOBA-style extraction game inspired by:
- **Hades**: Random, diverse power-ups (boons) that dramatically change gameplay each run
- **League of Legends**: Item system that diversifies how characters play
- **Arc Raiders**: Extraction-style PvPvE with chests, enemies, and extraction mechanics

### Core Mechanics
- **PvPvE**: Players compete against each other AND AI enemies
- **Boon System**: Random power-ups from chests/enemies that stack and combine
- **Steal-on-Kill**: When you kill a player, you steal ALL their boons (core mechanic!)
- **Chests**: Scattered across open world, contain random boons
- **Enemies**: PvE enemies drop boons when killed
- **Big Boss**: End-game boss with mega loot (optional extraction point)
- **Extraction**: Can extract early to keep progress, or stay to fight boss
- **Open World**: Large explorable world (1600x1200), not arena-based

---

## Progress Status

### ✅ Phase 1: Networking Infrastructure - COMPLETE

0. **✅ Task 0: TypeScript Server (Railway)** - DONE
   - ✅ `server/` directory created with TypeScript
   - ✅ Express REST API: create-room, join-room, list-rooms, heartbeat
   - ✅ TCP Relay server for real-time game messages (not WebSocket, but works!)
   - ✅ All-in-one: REST + TCP on same Railway service
   - ✅ Deployed on Railway
   - ⚠️ Using in-memory storage (not Cloudflare KV yet, but works for now)

1. **✅ Task 1: NetworkAdapter Abstraction** - DONE
   - ✅ `src/net/network_adapter.lua` created
   - ✅ Abstract interface for LAN (ENet) and Online (Relay)
   - ✅ Allows game logic to work with both networking backends

2. **✅ Task 2: OnlineClient (REST API Matchmaker)** - DONE
   - ✅ `src/net/online_client.lua` created
   - ✅ Implemented: createRoom, joinRoom, listRooms, heartbeat
   - ✅ Uses HTTPS for matchmaking (with lua-sec fallback)

3. **⚠️ Task 3: Real-Time Messaging** - PARTIAL
   - ✅ `src/net/relay_client.lua` created (TCP-based, not WebSocket)
   - ✅ Connects to Railway TCP relay server
   - ✅ Implements NetworkAdapter interface
   - ⚠️ Uses TCP sockets instead of WebSocket (works fine, but different from original plan)

4. **✅ Task 4: Update Menu UX** - DONE
   - ✅ `src/ui/menu.lua` updated
   - ✅ ESC/START to open (not open by default)
   - ✅ MULTIPLAYER → ONLINE → CREATE/JOIN/FIND flow
   - ✅ 6-digit room codes, digit picker, public room list

---

### 🚧 Phase 2: Server-Authoritative Protocol - IN PROGRESS

5. **Task 5: Extend Protocol** - TODO
   - Update `src/net/protocol.lua`
   - Add INPUT, STATE, EVENT message types for game actions
   - Add SHOOT, INTERACT, BOON_GRANTED, PLAYER_DIED, BOON_STOLEN message types
   - Keep pipe-delimited format

6. **Task 6: Game State Module** - TODO
   - Create `src/gamemodes/boonsnatch/state.lua`
   - Server-owned state structure:
     - Players (position, HP, boons, kills, deaths)
     - Projectiles (position, velocity, owner, damage)
     - Chests (position, opened state, respawn timer)
     - Enemies (position, HP, type, boon drop chance)
     - Boss (position, HP, phase, mega loot)

7. **Task 7: Server Logic Skeleton** - TODO
   - Create `src/gamemodes/boonsnatch/server_logic.lua`
   - Basic server simulation structure
   - Game loop: update players, projectiles, enemies, chests
   - Collision detection (projectiles vs players, players vs enemies)
   - State snapshot generation for clients

---

### ⏳ Phase 3: Core Game Mechanics - NOT STARTED

8. **Task 8: Combat System**
   - Implement in `server_logic.lua`
   - Shooting: fire rate, projectile physics, damage calculation
   - Melee attacks (for close-range boons)
   - Self-hit prevention
   - Damage calculation with boon modifiers

9. **Task 9: Boon System** - CORE MECHANIC
   - Boon types (like Hades):
     - Offensive: +damage, +fire rate, triple shot, piercing, elemental effects
     - Defensive: +HP, +armor, block every N hits, regen
     - Mobility: +speed, dash, teleport, slow enemies
     - Utility: +range, reveal chests, steal on hit, lifesteal
   - Boon stacking: multiple boons combine effects
   - Boon rarity: common, rare, epic, legendary

10. **Task 10: Chest System**
    - Chests spawn randomly across open world
    - Chest types: common, rare, epic, legendary (better boons)
    - Interaction: press SPACE near chest to open
    - Cooldown: chests respawn after X seconds
    - Visual feedback: chest glow, opening animation

11. **Task 11: Enemy System (PvE)**
    - Spawn enemies across world
    - Enemy types: weak (common boons), medium (rare), strong (epic), mini-boss (legendary)
    - Enemy AI: patrol, chase players, attack
    - Drop boons on death (based on enemy type)
    - Respawn system

12. **Task 12: Death/Respawn + Steal-on-Kill** - CORE MECHANIC
    - When player dies:
      - Killer gets ALL boons from dead player
      - Dead player respawns at random location
      - Dead player loses all boons (back to base state)
      - Kill counter increments for killer
    - Respawn invincibility (3 seconds)
    - Death animation/effects

13. **Task 13: Boss System**
    - Big boss spawns after X minutes or when triggered
    - Boss has multiple phases, high HP
    - Boss drops MEGA LOOT (multiple legendary boons)
    - Boss location marked on map
    - Players can extract OR fight boss

14. **Task 14: Extraction System**
    - Extraction points at map edges
    - Players can extract to "bank" their boons (keep for next match)
    - If you die before extracting, lose everything
    - Extraction takes 5 seconds (vulnerable)
    - Can extract early OR stay to fight boss

15. **Task 15: Match End**
    - Win conditions:
      - First to X kills (default: 5)
      - OR kill the boss
      - OR last player standing
    - Match reset logic
    - Victory/defeat screen
    - Stats display (kills, deaths, boons collected)

---

### ⏳ Phase 4: Client Integration - NOT STARTED

16. **Task 16: Client Game Mode**
    - Create `src/gamemodes/boonsnatch/client.lua`
    - Input sending (movement, shooting, interaction)
    - State receiving and interpolation
    - Event handling (boon granted, player died, etc.)
    - Client-side prediction for responsiveness

17. **Task 17: Server/Relay Integration**
    - Update `src/net/server.lua` to use server_logic
    - Host runs server_logic simulation
    - Broadcast state snapshots to all clients
    - Handle input from clients

18. **Task 18: Client Network Integration**
    - Update client to send inputs via NetworkAdapter
    - Receive and apply state snapshots
    - Handle network events (boon granted, death, etc.)
    - Lag compensation

---

### ⏳ Phase 5: Rendering + UI - NOT STARTED

19. **Task 19: World Rendering**
    - Keep open world (1600x1200)
    - Add chest visuals at world positions
    - Chest glow/particles for rarity
    - Enemy rendering
    - Boss rendering (large, intimidating)
    - Extraction point markers

20. **Task 20: Player Rendering**
    - HP bar above player
    - Boon indicator (icons around player, or status bar)
    - Death effects (particles, fade out)
    - Respawn effects (fade in, invincibility glow)
    - Update `player.lua` and `remote_player.lua`

21. **Task 21: Projectile Rendering**
    - Visual projectiles (bullets, arrows, etc.)
    - Elemental effects (fire, ice, lightning based on boons)
    - Trail effects

22. **Task 22: HUD**
    - Create `src/gamemodes/boonsnatch/hud.lua`
    - Scoreboard (kills/deaths for all players)
    - Match status (time remaining, boss spawn timer)
    - Boon list (show active boons with icons)
    - HP bar
    - Minimap (optional)
    - Winner screen

23. **Task 23: Boon UI**
    - Boon notification when granted ("+Triple Shot!")
    - Boon list display (active boons)
    - Boon tooltips (hover to see description)
    - Visual feedback when boons are stolen

---

### ⏳ Phase 6: Integration - NOT STARTED

24. **Task 24: Main Game Integration**
    - Update `src/game.lua`
    - Remove NPC/pet/dialogue (or make optional)
    - Integrate boonsnatch game mode
    - Menu opens with ESC/START
    - Game mode selection (Boon Snatch vs Walking Simulator?)

25. **Task 25: Audio**
    - Combat sounds (shooting, hits, deaths)
    - Chest opening sounds
    - Boon granted sound
    - Boss music
    - Victory/defeat sounds

26. **Task 26: Testing & Polish**
    - Test all networking flows
    - Test all game mechanics
    - Verify steal-on-kill works correctly
    - Test match end and reset
    - Balance boon power levels
    - Test extraction mechanics
    - Performance optimization

---

## Key Design Decisions

### Networking
- **Open World**: 1600x1200 explorable world, not single-screen arena
- **Networking First**: Build networking before game features ✅
- **All-in-One Server**: REST API + TCP relay server on Railway (one service) ✅
- **TypeScript Server**: Matchmaker + TCP relay on Railway ✅
- **In-Memory Storage**: Currently using in-memory room storage (works for now, can add Cloudflare KV later)
- **Room Codes**: 6-digit codes for private rooms, public room browser ✅
- **Server Authority**: Host runs server_logic, all state is authoritative
- **Menu UX**: ESC/START to open, game starts immediately ✅

### Game Design
- **MOBA-Style**: Character abilities/playstyle defined by boons (like League items)
- **Hades-Inspired Boons**: Random, diverse power-ups that dramatically change gameplay
- **Steal-on-Kill**: Core mechanic - killing players transfers ALL their boons
- **PvPvE**: Players fight each other AND AI enemies for boons
- **Extraction Mechanic**: Can extract early to keep progress, or stay for boss
- **Boss End-Game**: Optional big boss with mega loot
- **Open World Exploration**: Large map with chests and enemies scattered around

### Technical
- **LOVE2D**: Pixel art game engine
- **Lua**: Game client code
- **TypeScript**: Server code (Railway)
- **TCP Relay**: Real-time communication (not WebSocket, but works fine)
- **Server Authority**: Host simulates game, clients send inputs and receive state

---

## Next Steps (Priority Order)

### Immediate Next Steps (Phase 2)
1. **Extend Protocol** (Task 5)
   - Add game action message types (SHOOT, INTERACT, etc.)
   - This enables all future game mechanics

2. **Create Game State Module** (Task 6)
   - Define the data structures for players, projectiles, chests, enemies
   - This is the foundation for server simulation

3. **Server Logic Skeleton** (Task 7)
   - Basic game loop structure
   - Start with simple movement and state broadcasting
   - Then add combat, then boons, then everything else

### After Phase 2 (Phase 3 - Core Mechanics)
4. **Combat System** (Task 8)
   - Shooting mechanics first (simplest)
   - Then melee if needed

5. **Boon System** (Task 9) - **CORE MECHANIC**
   - Start with 3-5 simple boons (damage, speed, HP)
   - Get the system working, then expand
   - This is what makes the game unique!

6. **Chest System** (Task 10)
   - Spawn chests, open them, grant boons
   - Test the core loop: find chest → get boon → use boon

7. **Steal-on-Kill** (Task 12) - **CORE MECHANIC**
   - This is the hook! Implement early to test the fun factor
   - Death → respawn → boon transfer

### Then Polish (Phases 4-6)
- Enemies, boss, extraction
- Rendering, UI, audio
- Integration and testing

---

## Current Status Summary

✅ **Completed**: Networking infrastructure (Phase 1)
- Server deployed on Railway
- Matchmaking (create/join rooms)
- Real-time TCP relay
- Menu system

🚧 **In Progress**: None (ready to start Phase 2)

⏳ **Next**: Protocol extension → Game state → Server logic skeleton

**Estimated Progress**: ~20% complete (networking done, game mechanics not started)
