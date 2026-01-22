#!/bin/bash
# Full flow test for love-game multiplayer

API_URL="${API_URL:-https://love-game-production.up.railway.app}"

echo "=== Full Game Flow Test ==="
echo "API URL: $API_URL"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test 1: Health Check
echo "1. Testing Health Check..."
HEALTH=$(curl -s -w "\nHTTP_CODE:%{http_code}" "$API_URL/health")
HTTP_CODE=$(echo "$HEALTH" | grep "HTTP_CODE" | cut -d: -f2)
BODY=$(echo "$HEALTH" | sed '/HTTP_CODE/d')

if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✅ Health check passed${NC}"
  echo "   Response: $BODY"
else
  echo -e "${RED}❌ Health check failed (HTTP $HTTP_CODE)${NC}"
  echo "   Response: $BODY"
  echo ""
  echo -e "${YELLOW}⚠️  Server might not be running or accessible${NC}"
  exit 1
fi
echo ""

# Test 2: Create Room
echo "2. Testing CREATE ROOM..."
CREATE_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$API_URL/api/create-room" \
  -H "Content-Type: application/json" \
  -d '{"isPublic": true}')

HTTP_CODE=$(echo "$CREATE_RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)
BODY=$(echo "$CREATE_RESPONSE" | sed '/HTTP_CODE/d')

if [ "$HTTP_CODE" = "200" ]; then
  ROOM_CODE=$(echo "$BODY" | grep -o '"roomCode":"[^"]*"' | cut -d'"' -f4)
  if [ -z "$ROOM_CODE" ]; then
    ROOM_CODE=$(echo "$BODY" | grep -o '"roomCode":[^,}]*' | cut -d: -f2 | tr -d ' "')
  fi
  
  if [ -n "$ROOM_CODE" ]; then
    echo -e "${GREEN}✅ Room created successfully!${NC}"
    echo "   Room Code: $ROOM_CODE"
    echo "   Full Response: $BODY"
  else
    echo -e "${RED}❌ Room created but couldn't extract room code${NC}"
    echo "   Response: $BODY"
    exit 1
  fi
else
  echo -e "${RED}❌ Failed to create room (HTTP $HTTP_CODE)${NC}"
  echo "   Response: $BODY"
  exit 1
fi
echo ""

# Test 3: Join Room
echo "3. Testing JOIN ROOM..."
JOIN_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$API_URL/api/join-room" \
  -H "Content-Type: application/json" \
  -d "{\"code\": \"$ROOM_CODE\"}")

HTTP_CODE=$(echo "$JOIN_RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)
BODY=$(echo "$JOIN_RESPONSE" | sed '/HTTP_CODE/d')

if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✅ Successfully joined room!${NC}"
  echo "   Response: $BODY"
else
  echo -e "${RED}❌ Failed to join room (HTTP $HTTP_CODE)${NC}"
  echo "   Response: $BODY"
  exit 1
fi
echo ""

# Test 4: Keep-Alive (Heartbeat)
echo "4. Testing KEEP-ALIVE (Heartbeat)..."
HEARTBEAT_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$API_URL/api/keep-alive" \
  -H "Content-Type: application/json" \
  -d "{\"code\": \"$ROOM_CODE\"}")

HTTP_CODE=$(echo "$HEARTBEAT_RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)
BODY=$(echo "$HEARTBEAT_RESPONSE" | sed '/HTTP_CODE/d')

if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✅ Heartbeat successful!${NC}"
  echo "   Response: $BODY"
else
  echo -e "${YELLOW}⚠️  Heartbeat failed (HTTP $HTTP_CODE)${NC}"
  echo "   Response: $BODY"
fi
echo ""

# Test 5: List Rooms
echo "5. Testing LIST ROOMS..."
LIST_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET "$API_URL/api/list-rooms")
HTTP_CODE=$(echo "$LIST_RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)
BODY=$(echo "$LIST_RESPONSE" | sed '/HTTP_CODE/d')

if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✅ List rooms successful!${NC}"
  echo "   Response: $BODY"
else
  echo -e "${YELLOW}⚠️  List rooms failed (HTTP $HTTP_CODE)${NC}"
  echo "   Response: $BODY"
fi
echo ""

echo "=== HTTP API Tests Complete ==="
echo ""
echo -e "${GREEN}Room Code: $ROOM_CODE${NC}"
echo ""
echo "To test WebSocket connection:"
echo "  node test-websocket.js $ROOM_CODE test_player_1 host"
echo ""
echo "Or use wscat:"
echo "  wscat -c \"wss://love-game-production.up.railway.app/ws?room=$ROOM_CODE&playerId=test_player&isHost=true\""
