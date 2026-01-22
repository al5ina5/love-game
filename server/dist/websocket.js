"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.WebSocketManager = void 0;
const ws_1 = require("ws");
class WebSocketManager {
    constructor(server, kv) {
        this.clients = new Map();
        this.rooms = new Map(); // roomCode -> Set of client IDs
        this.kv = kv;
        this.wss = new ws_1.WebSocketServer({ server, path: '/ws' });
        this.setupWebSocket();
    }
    setupWebSocket() {
        this.wss.on('connection', (ws, req) => {
            const url = new URL(req.url || '', 'http://localhost');
            const roomCode = url.searchParams.get('room');
            const playerId = url.searchParams.get('playerId') || this.generatePlayerId();
            if (!roomCode) {
                ws.close(1008, 'Missing room code');
                return;
            }
            const clientId = `${roomCode}:${playerId}`;
            const isHost = url.searchParams.get('isHost') === 'true';
            console.log(`WebSocket connection: ${clientId} (host: ${isHost})`);
            const connection = {
                ws,
                roomCode,
                playerId,
                isHost,
            };
            this.clients.set(clientId, connection);
            // Add to room
            if (!this.rooms.has(roomCode)) {
                this.rooms.set(roomCode, new Set());
            }
            this.rooms.get(roomCode).add(clientId);
            // Update room heartbeat when connection is established
            this.updateRoomHeartbeat(roomCode);
            // Send welcome message
            ws.send(JSON.stringify({
                type: 'connected',
                playerId,
                roomCode,
            }));
            // Send existing players to the new joiner
            const roomClients = this.rooms.get(roomCode);
            if (roomClients) {
                roomClients.forEach((existingClientId) => {
                    if (existingClientId !== clientId) {
                        const existingConnection = this.clients.get(existingClientId);
                        if (existingConnection) {
                            // Tell new player about existing player
                            ws.send(JSON.stringify({
                                type: 'player_joined',
                                playerId: existingConnection.playerId,
                                isHost: existingConnection.isHost,
                            }));
                        }
                    }
                });
            }
            // Broadcast player joined to others in room
            this.broadcastToRoom(roomCode, {
                type: 'player_joined',
                playerId,
                isHost,
            }, clientId);
            ws.on('message', (data) => {
                try {
                    const message = JSON.parse(data.toString());
                    this.handleMessage(clientId, message);
                }
                catch (error) {
                    console.error('Error parsing WebSocket message:', error);
                }
            });
            ws.on('close', () => {
                console.log(`WebSocket disconnected: ${clientId}`);
                this.handleDisconnect(clientId);
            });
            ws.on('error', (error) => {
                console.error(`WebSocket error for ${clientId}:`, error);
            });
        });
    }
    handleMessage(clientId, message) {
        const connection = this.clients.get(clientId);
        if (!connection)
            return;
        // Forward game messages to other players in the room
        if (message.type === 'game_message') {
            this.broadcastToRoom(connection.roomCode, message, clientId);
        }
    }
    handleDisconnect(clientId) {
        const connection = this.clients.get(clientId);
        if (!connection)
            return;
        // Broadcast player left
        this.broadcastToRoom(connection.roomCode, {
            type: 'player_left',
            playerId: connection.playerId,
        }, clientId);
        // Remove from room
        const roomClients = this.rooms.get(connection.roomCode);
        if (roomClients) {
            roomClients.delete(clientId);
            if (roomClients.size === 0) {
                this.rooms.delete(connection.roomCode);
                // Clean up empty room from KV store
                this.cleanupEmptyRoom(connection.roomCode);
            }
        }
        this.clients.delete(clientId);
    }
    async cleanupEmptyRoom(roomCode) {
        try {
            const room = await this.kv.getRoom(roomCode);
            if (room) {
                // Delete room from KV store if it has no players
                await this.kv.deleteRoom(roomCode);
                console.log(`Cleaned up empty room: ${roomCode}`);
            }
        }
        catch (error) {
            console.error(`Error cleaning up room ${roomCode}:`, error);
        }
    }
    broadcastToRoom(roomCode, message, excludeClientId) {
        const roomClients = this.rooms.get(roomCode);
        if (!roomClients)
            return;
        const messageStr = JSON.stringify(message);
        roomClients.forEach((clientId) => {
            if (clientId === excludeClientId)
                return;
            const connection = this.clients.get(clientId);
            if (connection && connection.ws.readyState === ws_1.WebSocket.OPEN) {
                connection.ws.send(messageStr);
            }
        });
    }
    sendToPlayer(roomCode, playerId, message) {
        const clientId = `${roomCode}:${playerId}`;
        const connection = this.clients.get(clientId);
        if (connection && connection.ws.readyState === ws_1.WebSocket.OPEN) {
            connection.ws.send(JSON.stringify(message));
        }
    }
    getRoomPlayerCount(roomCode) {
        return this.rooms.get(roomCode)?.size || 0;
    }
    generatePlayerId() {
        return `p${Date.now()}${Math.random().toString(36).substr(2, 5)}`;
    }
    async updateRoomHeartbeat(roomCode) {
        try {
            const room = await this.kv.getRoom(roomCode);
            if (room) {
                room.lastHeartbeat = Date.now();
                await this.kv.setRoom(room);
            }
        }
        catch (error) {
            console.error(`Error updating heartbeat for room ${roomCode}:`, error);
        }
    }
}
exports.WebSocketManager = WebSocketManager;
