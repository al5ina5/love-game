# Boon Snatch Implementation - Task List

## Priority Order (Networking First!)

### Phase 1: Networking Infrastructure ⚡ DO FIRST

0. **Task 0: TypeScript Server (Railway)**
   - Create `server/` directory (separate project)
   - Express REST API: create-room, join-room, list-rooms, keep-alive
   - WebSocket server: real-time game messages (ws library)
   - Cloudflare KV storage (reuse existing keys, prefix `boonsnatch:room:`)
   - All-in-one: REST + WebSocket on same Railway service
   - One-click deploy on Railway
   - Uses existing env vars: KV_REST_API_TOKEN, KV_REST_API_URL
   - NO Ably needed!

1. **Task 1: NetworkAdapter Abstraction**
   - Create `src/net/adapter.lua`
   - Abstract interface for REST API + WebSocket
   - Allows game logic to work with WebSocket backend

2. **Task 2: OnlineClient (REST API Matchmaker)**
   - Create `src/net/online_client.lua`
   - Implement: createRoom, joinRoom, listRooms, keepAlive
   - Uses HTTPS for matchmaking

3. **Task 3: WebSocketClient (Real-Time Messaging)**
   - Create `src/net/websocket_client.lua`
   - WebSocket client for real-time game messages
   - Connects to Railway WebSocket server, implements NetworkAdapter interface

4. **Task 4: Update Menu UX**
   - Update `src/ui/menu.lua`
   - ESC/START to open (not open by default)
   - MULTIPLAYER → ONLINE → CREATE/JOIN/FIND flow
   - 6-digit room codes, digit picker, public room list

---

### Phase 2: Server-Authoritative Protocol

5. **Task 5: Extend Protocol**
   - Update `src/net/protocol.lua`
   - Add INPUT, STATE, EVENT message types
   - Keep pipe-delimited format

6. **Task 6: Game State Module**
   - Create `src/gamemodes/boonsnatch/state.lua`
   - Server-owned state structure (players, projectiles, chests)

7. **Task 7: Server Logic Skeleton**
   - Create `src/gamemodes/boonsnatch/server_logic.lua`
   - Basic server simulation structure

---

### Phase 3: Core Game Mechanics

8. **Task 8: Shooting System**
   - Implement in `server_logic.lua`
   - Fire rate, single/triple-shot, self-hit prevention

9. **Task 9: Chest + Boon System**
   - Chests spawn in open world (not just center)
   - Interaction, cooldown, boon granting

10. **Task 10: Death/Respawn + Steal-on-Kill**
    - Core mechanic: boon transfers on kill
    - Respawn at random world locations

11. **Task 11: Match End**
    - First to 5 kills wins
    - Match reset logic

---

### Phase 4: Client Integration

12. **Task 12: Client Game Mode**
    - Create `src/gamemodes/boonsnatch/client.lua`
    - Input sending, state receiving, event handling

13. **Task 13: Server/Relay Integration**
    - Update server/relay to use server_logic
    - Broadcast state snapshots

14. **Task 14: Client Network Integration**
    - Update client to send inputs via NetworkAdapter
    - Receive and apply state

---

### Phase 5: Rendering + UI

15. **Task 15: World Rendering**
    - Keep open world (800x600)
    - Add chest visuals at world positions

16. **Task 16: Player Rendering**
    - HP display, boon indicator, death effects
    - Update `player.lua` and `remote_player.lua`

17. **Task 17: HUD**
    - Create `src/gamemodes/boonsnatch/hud.lua`
    - Scoreboard, match status, winner screen

---

### Phase 6: Integration

18. **Task 18: Main Game Integration**
    - Update `src/game.lua`
    - Remove NPC/pet/dialogue
    - Integrate boonsnatch mode
    - Menu opens with ESC/START

19. **Task 19: Testing**
    - Test all networking flows
    - Test all game mechanics
    - Verify steal-on-kill works
    - Test match end and reset

---

## Key Design Decisions

- **Open World**: 800x600 explorable world, not single-screen arena
- **Networking First**: Build networking before game features
- **All-in-One Server**: REST API + WebSocket server on Railway (one service)
- **TypeScript Server**: Matchmaker + WebSocket relay on Railway, uses Cloudflare KV
- **No Ably**: Everything runs on your Railway server
- **Room Codes**: 6-digit codes for private rooms, public room browser
- **Server Authority**: Host runs server_logic, all state is authoritative
- **Menu UX**: ESC/START to open, game starts immediately
