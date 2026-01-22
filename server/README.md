# Boon Snatch Server

Matchmaker + WebSocket server for Boon Snatch multiplayer game.

## Setup

1. Install dependencies:
```bash
npm install
```

2. Set environment variables (Railway will set these automatically):
- `UPSTASH_REDIS_REST_URL` - Upstash Redis REST API URL (or `KV_REST_API_URL` for legacy)
- `UPSTASH_REDIS_REST_TOKEN` - Upstash Redis REST API token (or `KV_REST_API_TOKEN` for legacy)
- `PORT` - Server port (Railway sets this, default: 8080)
- `RAILWAY_PUBLIC_DOMAIN` - Railway public domain (optional, for WebSocket URL)

## Development

```bash
npm run dev
```

## Build

```bash
npm run build
npm start
```

## Deploy to Railway

1. Connect your GitHub repo to Railway
2. Select the `server/` directory as the root
3. Railway will auto-detect Node.js and run `npm install && npm run build && npm start`
4. Add environment variables in Railway dashboard:
   - `UPSTASH_REDIS_REST_URL` (e.g., `https://fresh-mongoose-45397.upstash.io`)
   - `UPSTASH_REDIS_REST_TOKEN` (your Upstash REST API token)
   - `PORT=8080` (if not auto-set)
   - `RAILWAY_PUBLIC_DOMAIN` (optional, for WebSocket URL)

## API Endpoints

- `POST /api/create-room` - Create a new room
- `POST /api/join-room` - Join a room by code
- `GET /api/list-rooms` - List public rooms
- `POST /api/keep-alive` - Keep room alive (heartbeat)
- `GET /api/room/:code` - Get room status
- `GET /health` - Health check

## WebSocket

Connect to: `ws://your-domain/ws?room={code}&playerId={id}&isHost={true|false}`
