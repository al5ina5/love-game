import express, { Request, Response } from 'express';
import cors from 'cors';
import { createServer } from 'http';
import { KVStore } from './kv';
import { WebSocketManager } from './websocket';

const app = express();
const server = createServer(app);

// Middleware
app.use(cors());
app.use(express.json());

// Initialize services
const kv = new KVStore();
const wsManager = new WebSocketManager(server);

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
    // Note: KV doesn't support listing, so we return empty for now
    // In production, you'd maintain a separate index or use Redis
    // For now, return empty array - can be enhanced later
    res.json({
      success: true,
      rooms: [],
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

// Start server
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
