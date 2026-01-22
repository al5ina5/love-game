#!/usr/bin/env node
// Test WebSocket connection for love-game

const WebSocket = require('ws');

const API_URL = process.env.API_URL || 'https://love-game-production.up.railway.app';
const ROOM_CODE = process.argv[2];
const PLAYER_ID = process.argv[3] || `test_player_${Date.now()}`;
const IS_HOST = process.argv[4] === 'true' || process.argv[4] === 'host';

if (!ROOM_CODE) {
  console.error('Usage: node test-websocket.js <ROOM_CODE> [playerId] [host|client]');
  console.error('Example: node test-websocket.js 123456 test_player_1 host');
  process.exit(1);
}

// Convert HTTPS to WSS
const wsUrl = API_URL.replace('https://', 'wss://').replace('http://', 'ws://');
const fullUrl = `${wsUrl}/ws?room=${ROOM_CODE}&playerId=${PLAYER_ID}&isHost=${IS_HOST}`;

console.log(`Connecting to: ${fullUrl}`);
console.log(`Room Code: ${ROOM_CODE}`);
console.log(`Player ID: ${PLAYER_ID}`);
console.log(`Is Host: ${IS_HOST}`);
console.log('');

const ws = new WebSocket(fullUrl);

ws.on('open', () => {
  console.log('✅ WebSocket connected!');
  console.log('');
  
  // Send a test game message after 1 second
  setTimeout(() => {
    const testMessage = {
      type: 'game_message',
      roomCode: ROOM_CODE,
      playerId: PLAYER_ID,
      data: {
        type: 'player_move',
        x: 100,
        y: 200,
        dir: 'down'
      }
    };
    console.log('Sending test message:', JSON.stringify(testMessage));
    ws.send(JSON.stringify(testMessage));
  }, 1000);
});

ws.on('message', (data) => {
  try {
    const message = JSON.parse(data.toString());
    console.log('📨 Received message:', JSON.stringify(message, null, 2));
    
    if (message.type === 'connected') {
      console.log('✅ Server confirmed connection');
    } else if (message.type === 'player_joined') {
      console.log(`✅ Player joined: ${message.playerId}`);
    } else if (message.type === 'game_message') {
      console.log(`✅ Game message from ${message.playerId}:`, message.data);
    }
  } catch (e) {
    console.log('📨 Received (raw):', data.toString());
  }
});

ws.on('error', (error) => {
  console.error('❌ WebSocket error:', error.message);
});

ws.on('close', (code, reason) => {
  console.log(`🔌 WebSocket closed: ${code} - ${reason.toString()}`);
  process.exit(0);
});

// Keep alive
setInterval(() => {
  if (ws.readyState === WebSocket.OPEN) {
    ws.ping();
  }
}, 30000);

// Close after 10 seconds
setTimeout(() => {
  console.log('\nClosing connection...');
  ws.close();
}, 10000);
