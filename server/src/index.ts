import express, { Request, Response } from 'express';
import cors from 'cors';
import { createServer } from 'http';
import net from 'net';
import { KVStore } from './kv';
import { WebSocketManager } from './websocket';

const app = express();
const server = createServer(app);

// Middleware
app.use(cors());
app.use(express.json());

// Initialize services
const kv = new KVStore();
const wsManager = new WebSocketManager(server, kv);

// Generate 6-digit room code
function generateRoomCode(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

// REST API Routes

// Create a new room
app.post('/api/create-room', async (req: Request, res: Response) => {
  try {
    const { isPublic = false, hostId } = req.body;

    // Generate unique room code
    let code: string;
    let attempts = 0;
    do {
      code = generateRoomCode();
      attempts++;
      if (attempts > 10) {
        return res.status(500).json({ error: 'Failed to generate unique room code' });
      }
    } while (await kv.getRoom(code) !== null);

    const room = {
      code,
      isPublic,
      hostId: hostId || `host_${Date.now()}`,
      players: [hostId || `host_${Date.now()}`],
      createdAt: Date.now(),
      lastHeartbeat: Date.now(),
    };

    const success = await kv.setRoom(room);
    if (!success) {
      return res.status(500).json({ error: 'Failed to create room' });
    }

    // Get WebSocket URL
    const wsUrl = process.env.RAILWAY_PUBLIC_DOMAIN 
      ? `wss://${process.env.RAILWAY_PUBLIC_DOMAIN}/ws`
      : `ws://localhost:${process.env.PORT || 3000}/ws`;

    res.json({
      success: true,
      roomCode: code,
      wsUrl: `${wsUrl}?room=${code}&playerId=${room.hostId}&isHost=true`,
    });
  } catch (error) {
    console.error('Error creating room:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Join a room by code
app.post('/api/join-room', async (req: Request, res: Response) => {
  try {
    const { code, playerId } = req.body;

    if (!code) {
      return res.status(400).json({ error: 'Room code required' });
    }

    const room = await kv.getRoom(code);
    if (!room) {
      return res.status(404).json({ error: 'Room not found' });
    }

    const newPlayerId = playerId || `player_${Date.now()}`;

    // Add player to room if not already present
    if (!room.players.includes(newPlayerId)) {
      room.players.push(newPlayerId);
      room.lastHeartbeat = Date.now();
      await kv.setRoom(room);
    }

    // Get WebSocket URL
    const wsUrl = process.env.RAILWAY_PUBLIC_DOMAIN 
      ? `wss://${process.env.RAILWAY_PUBLIC_DOMAIN}/ws`
      : `ws://localhost:${process.env.PORT || 3000}/ws`;

    res.json({
      success: true,
      roomCode: code,
      wsUrl: `${wsUrl}?room=${code}&playerId=${newPlayerId}&isHost=false`,
      playerId: newPlayerId,
    });
  } catch (error) {
    console.error('Error joining room:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// List public rooms
app.get('/api/list-rooms', async (req: Request, res: Response) => {
  try {
    const rooms = await kv.listPublicRooms();
    
    // Enhance with WebSocket player counts
    const roomsWithCounts = rooms.map(room => ({
      code: room.code,
      playerCount: wsManager.getRoomPlayerCount(room.code) || room.playerCount || 0,
      maxPlayers: room.maxPlayers || 4,
      createdAt: room.createdAt,
    }));
    
    res.json({
      success: true,
      rooms: roomsWithCounts,
    });
  } catch (error) {
    console.error('Error listing rooms:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Keep room alive (heartbeat)
app.post('/api/keep-alive', async (req: Request, res: Response) => {
  try {
    const { code } = req.body;

    if (!code) {
      return res.status(400).json({ error: 'Room code required' });
    }

    const room = await kv.getRoom(code);
    if (!room) {
      return res.status(404).json({ error: 'Room not found' });
    }

    room.lastHeartbeat = Date.now();
    await kv.setRoom(room);

    res.json({ success: true });
  } catch (error) {
    console.error('Error keeping room alive:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get room status
app.get('/api/room/:code', async (req: Request, res: Response) => {
  try {
    const { code } = req.params;
    const room = await kv.getRoom(code);

    if (!room) {
      return res.status(404).json({ error: 'Room not found' });
    }

    const playerCount = wsManager.getRoomPlayerCount(code);

    res.json({
      success: true,
      room: {
        code: room.code,
        isPublic: room.isPublic,
        playerCount,
        maxPlayers: 4, // Can be configurable
        createdAt: room.createdAt,
      },
    });
  } catch (error) {
    console.error('Error getting room status:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Health check
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok' });
});

// --- TCP Relay Server (for real-time game messages) ---
// Railway TCP Proxy: Configure in Railway dashboard -> Service -> Networking -> TCP Proxy
// Set the internal port (e.g., 12346) and Railway will provide a proxy like turntable.proxy.rlwy.net:32378
const TCP_PORT = parseInt(process.env.TCP_PORT || '12346', 10);
const roomSockets = new Map<string, net.Socket[]>();

const tcpServer = net.createServer((socket: net.Socket) => {
  let currentRoomCode: string | null = null;
  let buffer = '';
  let cleanedUp = false;

  // Set keep-alive to prevent connection timeouts
  socket.setKeepAlive(true, 60000);
  socket.setNoDelay(true);
  
  console.log(`[TCP] New connection from ${socket.remoteAddress}:${socket.remotePort}`);

  socket.on('data', (data: Buffer) => {
    const dataStr = data.toString();
    console.log(`[TCP] Received data from ${socket.remoteAddress}: "${dataStr.trim()}"`);
    buffer += dataStr;
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';

    for (const line of lines) {
      const trimmedLine = line.trim();
      if (!trimmedLine) continue; // Skip empty lines
      
      console.log(`[TCP] Processing line: "${trimmedLine}"`);
      
      if (trimmedLine.startsWith('JOIN:')) {
        const code = trimmedLine.split(':')[1].trim().toUpperCase();
        if (!code) {
          console.log(`[TCP] Invalid JOIN message: "${trimmedLine}"`);
          socket.write('ERROR:Invalid room code\n');
          continue;
        }
        
        currentRoomCode = code;
        console.log(`[TCP] Player joining room: ${code}`);
        
        let sockets = roomSockets.get(code);
        if (!sockets) {
          sockets = [socket];
          roomSockets.set(code, sockets);
          console.log(`[TCP] Player joined room ${code} (1st player)`);
        } else {
          if (sockets.length < 2) {
            sockets.push(socket);
            console.log(`[TCP] Player joined room ${code} (2nd player)`);
            
            // Notify both players they are paired
            sockets.forEach(s => {
              console.log(`[TCP] Sending PAIRED to player`);
              s.write('PAIRED\n');
            });
          } else {
            console.log(`[TCP] Room ${code} is full`);
            socket.write('ERROR:Room full\n');
            socket.end();
          }
        }
        continue;
      }

      // Forward data to others in the same room
      if (currentRoomCode) {
        const sockets = roomSockets.get(currentRoomCode);
        if (sockets) {
          console.log(`[TCP] Forwarding message to ${sockets.length - 1} other player(s) in room ${currentRoomCode}`);
          sockets.forEach(s => {
            if (s !== socket) {
              s.write(trimmedLine + '\n');
            }
          });
        } else {
          console.log(`[TCP] Warning: No sockets found for room ${currentRoomCode}`);
        }
      } else {
        console.log(`[TCP] Warning: Received message but no room code set: "${trimmedLine}"`);
      }
    }
  });

  const cleanup = () => {
    if (cleanedUp) return;
    cleanedUp = true;
    
    if (currentRoomCode) {
      const sockets = roomSockets.get(currentRoomCode);
      if (sockets) {
        const filtered = sockets.filter(s => s !== socket);
        if (filtered.length === 0) {
          roomSockets.delete(currentRoomCode);
          console.log(`[TCP] Room ${currentRoomCode} deleted (empty)`);
        } else {
          roomSockets.set(currentRoomCode, filtered);
          // Notify remaining player(s) that opponent left
          filtered.forEach(s => s.write('OPPONENT_LEFT\n'));
          console.log(`[TCP] Player left room ${currentRoomCode}, notified remaining players`);
        }
      }
    }
  };

  socket.on('close', () => {
    console.log(`[TCP] Socket closed for room ${currentRoomCode || 'unknown'}`);
    cleanup();
  });
  
  socket.on('error', (err) => {
    console.log(`[TCP] Socket error for room ${currentRoomCode || 'unknown'}: ${err.message}`);
    cleanup();
  });
  
  socket.on('timeout', () => {
    console.log(`[TCP] Socket timeout for room ${currentRoomCode || 'unknown'}`);
    socket.end();
  });
  
  // Set a longer timeout
  socket.setTimeout(300000); // 5 minutes
});

tcpServer.on('error', (err: Error) => {
  console.error(`[TCP] Server error: ${err.message}`);
  console.error(`[TCP] This might mean port ${TCP_PORT} is not available or Railway doesn't expose it`);
});

tcpServer.listen(TCP_PORT, '0.0.0.0', () => {
  console.log(`📡 TCP Relay listening on port ${TCP_PORT}`);
  console.log(`📡 TCP Relay will accept connections on ${process.env.RAILWAY_PUBLIC_DOMAIN || 'localhost'}:${TCP_PORT}`);
}).on('error', (err: NodeJS.ErrnoException) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`[TCP] Port ${TCP_PORT} is already in use`);
  } else {
    console.error(`[TCP] Failed to start relay server: ${err.message}`);
  }
});

// Start HTTP/WebSocket server
const PORT = parseInt(process.env.PORT || '3000', 10);
server.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Boon Snatch Server running on port ${PORT}`);
  console.log(`📡 WebSocket available at ws://localhost:${PORT}/ws`);
  
  if (!process.env.KV_REST_API_TOKEN) {
    console.warn('⚠️  Warning: KV_REST_API_TOKEN not set');
  }
  if (!process.env.KV_REST_API_URL) {
    console.warn('⚠️  Warning: KV_REST_API_URL not set');
  }
});
