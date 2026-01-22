#!/bin/bash
# Test script for love-game multiplayer API

API_URL="${API_URL:-https://love-game-production.up.railway.app}"

echo "=== Testing Love Game Multiplayer API ==="
echo "API URL: $API_URL"
echo ""

# Test 1: Create Room
echo "1. Testing CREATE ROOM..."
CREATE_RESPONSE=$(curl -s -X POST "$API_URL/api/create-room" \
  -H "Content-Type: application/json" \
  -d '{"isPublic": true}')

echo "Response: $CREATE_RESPONSE"
ROOM_CODE=$(echo "$CREATE_RESPONSE" | grep -o '"roomCode":"[^"]*"' | cut -d'"' -f4)

if [ -z "$ROOM_CODE" ]; then
  echo "❌ Failed to create room or extract room code"
  echo "Full response: $CREATE_RESPONSE"
  exit 1
fi

echo "✅ Room created successfully!"
echo "   Room Code: $ROOM_CODE"
echo ""

# Test 2: Join Room
echo "2. Testing JOIN ROOM..."
JOIN_RESPONSE=$(curl -s -X POST "$API_URL/api/join-room" \
  -H "Content-Type: application/json" \
  -d "{\"code\": \"$ROOM_CODE\"}")

echo "Response: $JOIN_RESPONSE"

if echo "$JOIN_RESPONSE" | grep -q "success\|roomCode"; then
  echo "✅ Successfully joined room!"
else
  echo "❌ Failed to join room"
  echo "Full response: $JOIN_RESPONSE"
  exit 1
fi
echo ""

# Test 3: List Rooms
echo "3. Testing LIST ROOMS..."
LIST_RESPONSE=$(curl -s -X GET "$API_URL/api/list-rooms")
echo "Response: $LIST_RESPONSE"
echo ""

# Test 4: Health Check
echo "4. Testing HEALTH CHECK..."
HEALTH_RESPONSE=$(curl -s -X GET "$API_URL/health")
echo "Response: $HEALTH_RESPONSE"
echo ""

# Test 5: Keep-Alive (Heartbeat)
echo "5. Testing KEEP-ALIVE (Heartbeat)..."
HEARTBEAT_RESPONSE=$(curl -s -X POST "$API_URL/api/keep-alive" \
  -H "Content-Type: application/json" \
  -d "{\"code\": \"$ROOM_CODE\"}")
echo "Response: $HEARTBEAT_RESPONSE"
echo ""

echo "=== HTTP API Tests Complete ==="
echo ""
echo "Room Code: $ROOM_CODE"
echo ""
echo "To test WebSocket connection, you can use:"
echo "  wscat -c \"wss://love-game-production.up.railway.app/ws?room=$ROOM_CODE&playerId=test_player&isHost=true\""
echo ""
echo "Or use a WebSocket client tool like:"
echo "  - websocat (install: cargo install websocat)"
echo "  - wscat (install: npm install -g wscat)"
echo "  - Browser DevTools WebSocket client"
