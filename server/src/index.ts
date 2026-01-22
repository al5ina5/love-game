import express, { Request, Response } from 'express';
import cors from 'cors';
import net from 'net';

// --- Configuration ---
const HTTP_PORT = parseInt(process.env.PORT || '3000', 10);
const TCP_PORT = parseInt(process.env.TCP_PORT || '12346', 10);

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
  sockets: net.Socket[];
  gameStarted: boolean;
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
    maxPlayers: 2,
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
    !r.gameStarted &&  // Don't show rooms where game already started
    (now - r.lastHeartbeat) < 60000 // Only show active rooms
  );
  res.json({ rooms: publicRooms });
});

app.post('/api/join-room', (req: Request, res: Response) => {
  const { roomCode } = req.body;
  const room = rooms.get(roomCode?.toUpperCase());
  
  if (!room) return res.status(404).json({ error: 'Room not found' });
  if (room.players >= room.maxPlayers) return res.status(400).json({ error: 'Room full' });
  if (room.gameStarted) return res.status(400).json({ error: 'Game already in progress' });
  
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
        
        // Reject if game already started
        if (room && room.gameStarted) {
          socket.write('ERROR:Game already in progress\n');
          socket.end();
          continue;
        }
        
        let roomData = roomSockets.get(code);
        if (!roomData) {
          roomData = { sockets: [socket], gameStarted: false };
          roomSockets.set(code, roomData);
          console.log(`[TCP] Player joined room ${code} (1st player)`);
        } else {
          if (roomData.sockets.length < 2) {
            roomData.sockets.push(socket);
            if (room) room.players = roomData.sockets.length;
            console.log(`[TCP] Player joined room ${code} (2nd player)`);
            
            // Notify both players they are paired
            roomData.sockets.forEach(s => s.write('PAIRED\n'));
          } else {
            socket.write('ERROR:Room full\n');
            socket.end();
          }
        }
        continue;
      }

      // Track game start (countdown message)
      if (line.includes('|scd|') || line.startsWith('scd|')) {
        const roomData = roomSockets.get(currentRoomCode || '');
        const room = rooms.get(currentRoomCode || '');
        if (roomData) roomData.gameStarted = true;
        if (room) room.gameStarted = true;
        console.log(`[TCP] Game started in room ${currentRoomCode}`);
      }

      // Forward data to others in the same room
      if (currentRoomCode) {
        const roomData = roomSockets.get(currentRoomCode);
        if (roomData) {
          roomData.sockets.forEach(s => {
            if (s !== socket) s.write(line + '\n');
          });
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
        roomData.sockets = roomData.sockets.filter(s => s !== socket);
        const room = rooms.get(currentRoomCode);
        if (room) room.players = roomData.sockets.length;

        if (roomData.sockets.length === 0) {
          // No players left - delete the room entirely
          roomSockets.delete(currentRoomCode);
          rooms.delete(currentRoomCode);
          console.log(`[TCP] Room ${currentRoomCode} deleted (empty)`);
        } else {
          // Notify remaining player(s) that opponent left
          roomData.sockets.forEach(s => s.write('OPPONENT_LEFT\n'));
          console.log(`[TCP] Player left room ${currentRoomCode}, notified remaining players`);
          
          // If game was in progress, reset game state so host can rematch or continue solo
          if (roomData.gameStarted) {
            roomData.gameStarted = false;
            if (room) room.gameStarted = false;
          }
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
