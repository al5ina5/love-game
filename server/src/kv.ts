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

  async listPublicRooms(): Promise<Room[]> {
    // Note: Cloudflare KV doesn't have native list/query
    // We'll need to maintain a separate index or use a different approach
    // For now, we'll return empty array and implement proper indexing later if needed
    // Alternative: Use Redis or maintain an in-memory cache of public rooms
    return [];
  }
}
