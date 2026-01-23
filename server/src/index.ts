import express, { Request, Response } from 'express';
import cors from 'cors';
import net from 'net';
import { GameServer } from './game_server';

// --- Configuration ---
// Railway: HTTP on PORT (should be 8080), TCP on 12346 (Railway TCP proxy forwards to this)
// If Railway incorrectly sets PORT=12346, use 12346 for TCP and 8080 for HTTP
const RAILWAY_PORT = parseInt(process.env.PORT || '3000', 10);
const RAILWAY_TCP_PORT = parseInt(process.env.TCP_PORT || '12346', 10);

let HTTP_PORT = RAILWAY_PORT;
let TCP_PORT = RAILWAY_TCP_PORT;

// Handle Railway quirk: if PORT is set to TCP proxy port (12346), use it for TCP and default HTTP port for HTTP
if (RAILWAY_PORT === 12346 && !process.env.TCP_PORT) {
  HTTP_PORT = 8080;  // Railway HTTP should be on 8080
  TCP_PORT = 12346;  // Railway TCP proxy forwards to 12346
  console.log(`[CONFIG] Detected PORT=12346, using HTTP_PORT=${HTTP_PORT}, TCP_PORT=${TCP_PORT}`);
} else {
  HTTP_PORT = RAILWAY_PORT;
  TCP_PORT = RAILWAY_TCP_PORT;
}

// --- Types ---
interface Room {
  code: string;
  hostName: string;
  isPublic: boolean;
  players: number;
  maxPlayers: number;
  createdAt: number;
  lastHeartbeat: number;
  gameStarted: boolean;  // Track if game has begun
}

interface RoomData {
  sockets: Map<net.Socket, string>; // socket -> playerId mapping
  gameStarted: boolean;
  gameServer: GameServer;
  lastStateBroadcast: number;
  stateBroadcastInterval: number; // milliseconds
}

// --- In-Memory State ---
const rooms = new Map<string, Room>();
const roomSockets = new Map<string, RoomData>();

// --- Helper: Generate Room Code ---
function generateRoomCode(): string {
  // Generate 6-digit numeric code (100000-999999) for easier gamepad input
  const code = Math.floor(100000 + Math.random() * 900000).toString();
  return code;
}

// --- HTTP Server (Matchmaker) ---
const app = express();
app.use(cors());
app.use(express.json());

app.post('/api/create-room', (req: Request, res: Response) => {
  const { isPublic, hostName = 'Host' } = req.body;
  const code = generateRoomCode();

  const room: Room = {
    code,
    hostName,
    isPublic: !!isPublic,
    players: 1,
    maxPlayers: 10,
    createdAt: Date.now(),
    lastHeartbeat: Date.now(),
    gameStarted: false,
  };

  rooms.set(code, room);
  res.json({ roomCode: code });
  console.log(`[HTTP] Room ${code} created`);
});

app.get('/api/list-rooms', (_req: Request, res: Response) => {
  const now = Date.now();
  const publicRooms = Array.from(rooms.values()).filter(r =>
    r.isPublic &&
    r.players < r.maxPlayers &&
    (now - r.lastHeartbeat) < 60000 // Only show active rooms
    // Game is always running, so we don't filter by gameStarted
  );
  res.json({ rooms: publicRooms });
});

app.post('/api/join-room', (req: Request, res: Response) => {
  const { roomCode } = req.body;
  const room = rooms.get(roomCode?.toUpperCase());

  if (!room) return res.status(404).json({ error: 'Room not found' });
  if (room.players >= room.maxPlayers) return res.status(400).json({ error: 'Room full' });
  // Game is always running, so we don't check gameStarted

  res.json({ success: true });
});

app.post('/api/heartbeat', (req: Request, res: Response) => {
  const { roomCode } = req.body;
  const room = rooms.get(roomCode?.toUpperCase());
  if (room) {
    room.lastHeartbeat = Date.now();
    res.json({ success: true });
  } else {
    res.status(404).json({ error: 'Room not found' });
  }
});

// Health check
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok' });
});

// Ping endpoint for latency testing
app.get('/ping', (req: Request, res: Response) => {
  res.json({ timestamp: Date.now() });
});

// World data endpoint - returns complete world data for client pre-loading
app.get('/api/world-data', (req: Request, res: Response) => {
  // For now, return a sample room's world data
  // In a real implementation, this might be based on room code or cached globally
  const sampleRoomCode = Array.from(rooms.keys())[0]; // Get first room
  if (!sampleRoomCode) {
    return res.status(404).json({ error: 'No active rooms' });
  }

  const roomData = roomSockets.get(sampleRoomCode);
  if (!roomData) {
    return res.status(404).json({ error: 'Room data not found' });
  }

  try {
    // Get complete world data from the game server's chunk manager
    const worldData = roomData.gameServer.getCompleteWorldData();
    res.json(worldData);
  } catch (error) {
    console.error('[HTTP] Error getting world data:', error);
    res.status(500).json({ error: 'Failed to get world data' });
  }
});

app.listen(HTTP_PORT, '0.0.0.0', () => {
  console.log(`[HTTP] Matchmaker listening on port ${HTTP_PORT}`);
});

// --- TCP Server (Real-time Relay) ---
const tcpServer = net.createServer((socket: net.Socket) => {
  let currentRoomCode: string | null = null;
  let buffer = '';
  let cleanedUp = false;

  socket.on('data', (data: Buffer) => {
    buffer += data.toString();
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';

    for (const line of lines) {
      if (line.startsWith('JOIN:')) {
        const code = line.split(':')[1].toUpperCase();
        currentRoomCode = code;

        const room = rooms.get(code);

        // Game is always running, so we don't reject based on gameStarted
        // Players can join at any time during the cycle

        let roomData = roomSockets.get(code);
        if (!roomData) {
          // Create new room with game server (always running)
          const gameServer = new GameServer();
          roomData = {
            sockets: new Map(),
            gameStarted: true, // Game always running
            gameServer,
            lastStateBroadcast: Date.now(),
            stateBroadcastInterval: 50, // 20 times per second (50ms)
          };
          roomSockets.set(code, roomData);
          console.log(`[TCP] Room ${code} created with game server (always running)`);
        }

        // Generate player ID
        const playerId = `p${roomData.sockets.size + 1}`;
        roomData.sockets.set(socket, playerId);

        // Add player to game server (will scatter spawn automatically)
        roomData.gameServer.addPlayer(playerId);

        // Get the actual spawn position from the game server
        const player = roomData.gameServer['state'].players[playerId];
        const spawnX = player ? Math.floor(player.x) : 2500;
        const spawnY = player ? Math.floor(player.y) : 2500;

        // Send player their ID and initial state
        socket.write(`join|${playerId}|${spawnX}|${spawnY}\n`);

        // Send NPC data (server-authoritative)
        const npcs = roomData.gameServer.getNPCs();
        if (npcs.length > 0) {
          const npcParts = ['npcs', npcs.length.toString()];
          for (const npc of npcs) {
            npcParts.push(Math.floor(npc.x).toString());
            npcParts.push(Math.floor(npc.y).toString());
            npcParts.push(npc.spritePath || '');
            npcParts.push(npc.name || 'NPC');
            // Encode dialogue as JSON
            const dialogueJson = JSON.stringify(npc.dialogue || []);
            npcParts.push(dialogueJson);
          }
          socket.write(npcParts.join('|') + '\n');
        }

        // Send Animal data (server-authoritative)
        const animals = roomData.gameServer.getAnimals();
        if (animals.length > 0) {
          const animalParts = ['animals', animals.length.toString()];
          for (const animal of animals) {
            animalParts.push(Math.floor(animal.x).toString());
            animalParts.push(Math.floor(animal.y).toString());
            animalParts.push(animal.spritePath || '');
            animalParts.push(animal.name || 'Animal');
            animalParts.push(animal.speed.toString());
            animalParts.push(Math.floor(animal.groupCenterX).toString());
            animalParts.push(Math.floor(animal.groupCenterY).toString());
            animalParts.push(Math.floor(animal.groupRadius).toString());
          }
          socket.write(animalParts.join('|') + '\n');
        }

        const stateJson = roomData.gameServer.getStateSnapshot();
        socket.write(`state|${stateJson}\n`);

        // Update room player count
        if (room) {
          room.players = roomData.sockets.size;
        }

        console.log(`[TCP] Player ${playerId} joined room ${code} (${roomData.sockets.size} players)`);

        // Notify all players they are paired when 2+ players are present
        if (roomData.sockets.size >= 2) {
          roomData.sockets.forEach((_, s) => s.write('PAIRED\n'));
        }
        continue;
      }

      // Handle game messages server-authoritatively
      if (currentRoomCode) {
        const roomData = roomSockets.get(currentRoomCode);
        if (roomData) {
          const playerId = roomData.sockets.get(socket);

          // Parse message
          const parts = line.split('|');
          const msgType = parts[0];

          if (msgType === 'move' && playerId) {
            // Player position update - server validates and updates
            const x = parseFloat(parts[2]) || 0;
            const y = parseFloat(parts[3]) || 0;
            const direction = parts[4] || 'down';
            const sprinting = parts[6] === '1' || parts[6] === 'true';

            // Server updates authoritative position
            roomData.gameServer.updatePlayerPosition(playerId, x, y, direction, sprinting);

            // Broadcast to other players
            roomData.sockets.forEach((pid, s) => {
              if (s !== socket) {
                s.write(line + '\n');
              }
            });
          } else if (msgType === 'shoot' && playerId) {
            // Shoot input - server handles it
            const angle = parseFloat(parts[2]) || 0;
            roomData.gameServer.handleShoot(playerId, angle);
            // Don't echo back to sender, state will be broadcast
          } else if (msgType === 'interact' && playerId) {
            // Interact input - server handles it
            roomData.gameServer.handleInteract(playerId);
            // Don't echo back to sender, state will be broadcast
            roomData.sockets.forEach((_, s) => {
              if (s !== socket) {
                s.write(line + '\n');
              }
            });
          } else if (msgType === 'chunk') {
            // Chunk request: chunk|cx|cy
            const cx = parseInt(parts[1]);
            const cy = parseInt(parts[2]);

            if (!isNaN(cx) && !isNaN(cy)) {
              const chunkData = roomData.gameServer.getChunkData(cx, cy);
              if (chunkData) {
                // Send chunk data back
                const json = JSON.stringify(chunkData);
                socket.write(`chunk|${cx}|${cy}|${json}\n`);
              }
            }
          } else {
            // Unknown message type - just relay
            roomData.sockets.forEach((_, s) => {
              if (s !== socket) {
                s.write(line + '\n');
              }
            });
          }
        }
      }
    }
  });

  const cleanup = () => {
    if (cleanedUp) return;  // Prevent double cleanup
    cleanedUp = true;

    if (currentRoomCode) {
      const roomData = roomSockets.get(currentRoomCode);
      if (roomData) {
        // Remove player from game server
        const playerId = roomData.sockets.get(socket);
        roomData.sockets.delete(socket);  // Remove socket from map

        if (playerId) {
          roomData.gameServer.removePlayer(playerId);
        }

        // Update room player count
        const room = rooms.get(currentRoomCode);
        if (room) room.players = roomData.sockets.size;

        if (roomData.sockets.size === 0) {
          // No players left - but keep room and game server running!
          // Game cycle continues even with no players
          console.log(`[TCP] Room ${currentRoomCode} empty but game server continues running`);
        } else {
          // Notify remaining player(s) that opponent left
          roomData.sockets.forEach((_, s) => s.write('OPPONENT_LEFT\n'));
          console.log(`[TCP] Player ${playerId} left room ${currentRoomCode}, ${roomData.sockets.size} players remaining`);

          // Update room player count
          if (room) room.players = roomData.sockets.size;
        }
      }
    }
  };

  socket.on('close', cleanup);
  socket.on('error', (err) => {
    console.log(`[TCP] Socket error: ${err.message}`);
    cleanup();
  });
});

tcpServer.listen(TCP_PORT, '0.0.0.0', () => {
  console.log(`[TCP] Relay listening on port ${TCP_PORT}`);
});

// State broadcast loop - send game state to all clients periodically
setInterval(() => {
  const now = Date.now();

  for (const [roomCode, roomData] of roomSockets.entries()) {
    // Check if it's time to broadcast state
    if (now - roomData.lastStateBroadcast >= roomData.stateBroadcastInterval) {
      const stateJson = roomData.gameServer.getStateSnapshot();
      const cycleTime = roomData.gameServer.getCycleTimeRemaining();
      const cycleDuration = roomData.gameServer.getCycleDuration();

      // Broadcast state to all players in room
      roomData.sockets.forEach((playerId, socket) => {
        // Send state snapshot
        socket.write(`state|${stateJson}\n`);
        // Send cycle time update
        socket.write(`cycle|${cycleTime}|${cycleDuration}\n`);
      });

      roomData.lastStateBroadcast = now;
    }
  }
}, 50); // Check every 50ms (20 times per second)

// Cleanup: Periodically remove rooms that have been empty for too long (optional)
// For now, we keep rooms running indefinitely as requested
setInterval(() => {
  // Could add logic here to clean up rooms after X hours of being empty
  // For now, rooms persist forever as requested
}, 60000); // Check every minute
