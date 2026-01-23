# Local API Testing

To test the game with a local API server:

## 1. Start Local Server

```bash
cd server
npm install
npm run build
PORT=3000 TCP_PORT=12346 npm start
```

The server will run on:
- HTTP: http://localhost:3000
- TCP: localhost:12346

## 2. Configure Game to Use Local API

Set the environment variable before running the game:

```bash
export USE_LOCAL_API=true
love .
```

Or on Windows:
```cmd
set USE_LOCAL_API=true
love .
```

The game will automatically use:
- API: http://localhost:3000
- TCP Relay: localhost:12346

## 3. Test Flow

1. Start local server (see step 1)
2. Run game with `USE_LOCAL_API=true`
3. Create room on host
4. Join room on client
5. Both should connect and see each other

## 4. Verify It's Working

Check server logs - you should see:
- `[HTTP] Room X created`
- `[TCP] Player joined room X (1st player)`
- `[TCP] Player joined room X (2nd player)`
- `[TCP] Sending PAIRED to player`
