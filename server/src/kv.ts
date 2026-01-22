// Upstash Redis operations
// Uses @upstash/redis SDK for reliable connection

import { Redis } from '@upstash/redis';

export interface Room {
  code: string;
  isPublic: boolean;
  hostId: string;
  players: string[];
  createdAt: number;
  lastHeartbeat: number;
}

export interface PublicRoomInfo {
  code: string;
  playerCount: number;
  maxPlayers: number;
  createdAt: number;
}

export class KVStore {
  private redis: Redis;

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
    this.redis = new Redis({
      url: url,
      token: token,
    });
  }

  private getKey(roomCode: string): string {
    return `boonsnatch:room:${roomCode}`;
  }

  async getRoom(code: string): Promise<Room | null> {
    try {
      const key = this.getKey(code);
      const value = await this.redis.get<Room>(key);
      return value;
    } catch (error) {
      console.error('Error getting room from Upstash:', error);
      return null;
    }
  }

  async setRoom(room: Room): Promise<boolean> {
    try {
      const key = this.getKey(room.code);
      console.log('Upstash SET request for room:', room.code);
      
      const result = await this.redis.set(key, room);
      
      if (result === "OK") {
        console.log('Upstash SET successful for room:', room.code);
        return true;
      } else {
        console.error('Upstash SET unexpected response:', result);
        return false;
      }
    } catch (error) {
      console.error('Error setting room in Upstash:', error);
      if (error instanceof Error) {
        console.error('Error details:', error.message, error.stack);
      }
      return false;
    }
  }

  async deleteRoom(code: string): Promise<boolean> {
    try {
      const key = this.getKey(code);
      const result = await this.redis.del(key);
      // Returns number of keys deleted (1 if found, 0 if not)
      return result === 1;
    } catch (error) {
      console.error('Error deleting room from Upstash:', error);
      return false;
    }
  }

  async listPublicRooms(): Promise<PublicRoomInfo[]> {
    try {
      // Get all room keys matching the pattern
      const keys = await this.redis.keys('boonsnatch:room:*');
      
      if (!keys || keys.length === 0) {
        return [];
      }
      
      // Fetch all rooms in parallel
      const roomPromises = keys.map(key => this.redis.get<Room>(key));
      const rooms = await Promise.all(roomPromises);
      
      // Filter for public rooms and active rooms (heartbeat within last 2 minutes)
      const now = Date.now();
      const publicRooms: PublicRoomInfo[] = rooms
        .filter((room): room is Room => 
          room !== null && 
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
    } catch (error) {
      console.error('Error listing public rooms from Upstash:', error);
      return [];
    }
  }
}
