"use strict";
// Upstash Redis operations
// Uses @upstash/redis SDK for reliable connection
Object.defineProperty(exports, "__esModule", { value: true });
exports.KVStore = void 0;
const redis_1 = require("@upstash/redis");
class KVStore {
    constructor() {
        // Support both standard Upstash names and legacy KV names
        const url = process.env.UPSTASH_REDIS_REST_URL || process.env.KV_REST_API_URL || '';
        const token = process.env.UPSTASH_REDIS_REST_TOKEN || process.env.KV_REST_API_TOKEN || '';
        console.log('KVStore (Upstash) initializing:', {
            hasToken: !!token,
            tokenLength: token.length,
            hasUrl: !!url,
            urlPreview: url ? url.substring(0, 50) + '...' : 'missing',
            usingStandardVars: !!(process.env.UPSTASH_REDIS_REST_URL && process.env.UPSTASH_REDIS_REST_TOKEN)
        });
        if (!url || !token) {
            console.error('Missing Upstash credentials! UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN (or KV_REST_API_URL and KV_REST_API_TOKEN) required');
        }
        // Initialize Upstash Redis client
        this.redis = new redis_1.Redis({
            url: url,
            token: token,
        });
    }
    getKey(roomCode) {
        return `boonsnatch:room:${roomCode}`;
    }
    async getRoom(code) {
        try {
            const key = this.getKey(code);
            const value = await this.redis.get(key);
            return value;
        }
        catch (error) {
            console.error('Error getting room from Upstash:', error);
            return null;
        }
    }
    async setRoom(room) {
        try {
            const key = this.getKey(room.code);
            console.log('Upstash SET request for room:', room.code);
            const result = await this.redis.set(key, room);
            if (result === "OK") {
                console.log('Upstash SET successful for room:', room.code);
                return true;
            }
            else {
                console.error('Upstash SET unexpected response:', result);
                return false;
            }
        }
        catch (error) {
            console.error('Error setting room in Upstash:', error);
            if (error instanceof Error) {
                console.error('Error details:', error.message, error.stack);
            }
            return false;
        }
    }
    async deleteRoom(code) {
        try {
            const key = this.getKey(code);
            const result = await this.redis.del(key);
            // Returns number of keys deleted (1 if found, 0 if not)
            return result === 1;
        }
        catch (error) {
            console.error('Error deleting room from Upstash:', error);
            return false;
        }
    }
    async listPublicRooms() {
        try {
            // Get all room keys matching the pattern
            const keys = await this.redis.keys('boonsnatch:room:*');
            if (!keys || keys.length === 0) {
                return [];
            }
            // Fetch all rooms in parallel
            const roomPromises = keys.map(key => this.redis.get(key));
            const rooms = await Promise.all(roomPromises);
            // Filter for public rooms and active rooms (heartbeat within last 2 minutes)
            const now = Date.now();
            const publicRooms = rooms
                .filter((room) => room !== null &&
                room.isPublic === true &&
                (now - room.lastHeartbeat) < 120000 // Active within last 2 minutes
            )
                .map(room => ({
                code: room.code,
                playerCount: room.players.length,
                maxPlayers: 4, // Default max players
                createdAt: room.createdAt,
            }));
            return publicRooms;
        }
        catch (error) {
            console.error('Error listing public rooms from Upstash:', error);
            return [];
        }
    }
}
exports.KVStore = KVStore;
