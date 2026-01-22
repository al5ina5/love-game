// Cloudflare KV operations
// Uses REST API since we're not in a Cloudflare Worker

interface Room {
  code: string;
  isPublic: boolean;
  hostId: string;
  players: string[];
  createdAt: number;
  lastHeartbeat: number;
}

export class KVStore {
  private apiToken: string;
  private baseUrl: string;

  constructor() {
    this.apiToken = process.env.KV_REST_API_TOKEN || '';
    // KV_REST_API_URL should be: https://api.cloudflare.com/client/v4/accounts/{account_id}/storage/kv/namespaces/{namespace_id}
    this.baseUrl = process.env.KV_REST_API_URL || '';
    
    // Ensure base URL doesn't end with /
    if (this.baseUrl.endsWith('/')) {
      this.baseUrl = this.baseUrl.slice(0, -1);
    }
  }

  private getKey(roomCode: string): string {
    return `boonsnatch:room:${roomCode}`;
  }

  async getRoom(code: string): Promise<Room | null> {
    try {
      const response = await fetch(`${this.baseUrl}/values/${this.getKey(code)}`, {
        headers: {
          'Authorization': `Bearer ${this.apiToken}`,
        },
      });

      if (!response.ok) {
        if (response.status === 404) return null;
        throw new Error(`KV GET failed: ${response.statusText}`);
      }

      const text = await response.text();
      if (!text) return null;
      
      return JSON.parse(text) as Room;
    } catch (error) {
      console.error('Error getting room from KV:', error);
      return null;
    }
  }

  async setRoom(room: Room): Promise<boolean> {
    try {
      const response = await fetch(`${this.baseUrl}/values/${this.getKey(room.code)}`, {
        method: 'PUT',
        headers: {
          'Authorization': `Bearer ${this.apiToken}`,
          'Content-Type': 'text/plain',
        },
        body: JSON.stringify(room),
      });

      if (!response.ok) {
        throw new Error(`KV PUT failed: ${response.statusText}`);
      }

      return true;
    } catch (error) {
      console.error('Error setting room in KV:', error);
      return false;
    }
  }

  async deleteRoom(code: string): Promise<boolean> {
    try {
      const response = await fetch(`${this.baseUrl}/values/${this.getKey(code)}`, {
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${this.apiToken}`,
        },
      });

      return response.ok;
    } catch (error) {
      console.error('Error deleting room from KV:', error);
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
