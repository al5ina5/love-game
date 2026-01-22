#!/bin/bash
# Full game flow test with Railway URLs

API_URL="https://love-game-production.up.railway.app"
TCP_PROXY="ballast.proxy.rlwy.net:16563"

echo "=== Full Game Flow Test ==="
echo "HTTP API: $API_URL"
echo "TCP Proxy: $TCP_PROXY"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test 1: Health Check
echo "1. Health Check..."
HEALTH=$(curl -s -w "\n%{http_code}" "$API_URL/health")
HTTP_CODE=$(echo "$HEALTH" | tail -n1)
BODY=$(echo "$HEALTH" | head -n-1)

if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✅ Health OK${NC} - $BODY"
else
  echo -e "${RED}❌ Health failed (HTTP $HTTP_CODE)${NC}"
  echo "$BODY"
  exit 1
fi
echo ""

# Test 2: Create Room
echo "2. Create Room..."
CREATE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/create-room" \
  -H "Content-Type: application/json" \
  -d '{"isPublic": true}')

HTTP_CODE=$(echo "$CREATE" | tail -n1)
BODY=$(echo "$CREATE" | head -n-1)

if [ "$HTTP_CODE" = "200" ]; then
  ROOM_CODE=$(echo "$BODY" | grep -o '"roomCode":"[^"]*"' | cut -d'"' -f4 || echo "$BODY" | grep -o '"roomCode":[0-9]*' | cut -d: -f2 | tr -d ' ')
  if [ -n "$ROOM_CODE" ]; then
    echo -e "${GREEN}✅ Room created${NC} - Code: $ROOM_CODE"
    echo "   Response: $BODY"
  else
    echo -e "${RED}❌ No room code in response${NC}"
    echo "$BODY"
    exit 1
  fi
else
  echo -e "${RED}❌ Create failed (HTTP $HTTP_CODE)${NC}"
  echo "$BODY"
  exit 1
fi
echo ""

# Test 3: Join Room
echo "3. Join Room..."
JOIN=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/join-room" \
  -H "Content-Type: application/json" \
  -d "{\"code\": \"$ROOM_CODE\"}")

HTTP_CODE=$(echo "$JOIN" | tail -n1)
BODY=$(echo "$JOIN" | head -n-1)

if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✅ Joined room${NC}"
  echo "   Response: $BODY"
else
  echo -e "${RED}❌ Join failed (HTTP $HTTP_CODE)${NC}"
  echo "$BODY"
  exit 1
fi
echo ""

# Test 4: Heartbeat
echo "4. Heartbeat..."
HEARTBEAT=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/keep-alive" \
  -H "Content-Type: application/json" \
  -d "{\"code\": \"$ROOM_CODE\"}")

HTTP_CODE=$(echo "$HEARTBEAT" | tail -n1)
BODY=$(echo "$HEARTBEAT" | head -n-1)

if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✅ Heartbeat OK${NC}"
else
  echo -e "${YELLOW}⚠️  Heartbeat failed (HTTP $HTTP_CODE)${NC}"
fi
echo ""

# Test 5: List Rooms
echo "5. List Rooms..."
LIST=$(curl -s -w "\n%{http_code}" "$API_URL/api/list-rooms")
HTTP_CODE=$(echo "$LIST" | tail -n1)
BODY=$(echo "$LIST" | head -n-1)

if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✅ List rooms OK${NC}"
  echo "   Found $(echo "$BODY" | grep -o '"code"' | wc -l | tr -d ' ') room(s)"
else
  echo -e "${YELLOW}⚠️  List failed (HTTP $HTTP_CODE)${NC}"
fi
echo ""

echo "=== HTTP Tests Complete ==="
echo ""
echo -e "${GREEN}Room Code: $ROOM_CODE${NC}"
echo ""
echo "WebSocket Test:"
echo "  wscat -c \"wss://love-game-production.up.railway.app/ws?room=$ROOM_CODE&playerId=test_host&isHost=true\""
echo ""
echo "TCP Relay Test (using netcat or telnet):"
echo "  echo \"JOIN:$ROOM_CODE\" | nc $TCP_PROXY"
echo "  (Then send: move|host|100|200|down)"
