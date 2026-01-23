"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ChunkManager = void 0;
class ChunkManager {
    constructor(worldWidth, worldHeight) {
        this.chunks = {};
        this.CHUNK_SIZE = 512; // 32x32 tiles (16px)
        this.worldWidth = worldWidth;
        this.worldHeight = worldHeight;
    }
    // Get chunk key from chunk coordinates
    getChunkKey(cx, cy) {
        return `${cx},${cy}`;
    }
    // Get chunk coordinates from world position
    worldToChunk(x, y) {
        return {
            cx: Math.floor(x / this.CHUNK_SIZE),
            cy: Math.floor(y / this.CHUNK_SIZE),
        };
    }
    getChunk(cx, cy) {
        const key = this.getChunkKey(cx, cy);
        return this.chunks[key] || null;
    }
    setChunk(cx, cy, data) {
        const key = this.getChunkKey(cx, cy);
        this.chunks[key] = data;
    }
    getAllChunks() {
        return this.chunks;
    }
    // Helper to add a road tile to the appropriate chunk
    addRoadTile(x, y, tileId) {
        const pixelX = x * 16;
        const pixelY = y * 16;
        const { cx, cy } = this.worldToChunk(pixelX, pixelY);
        let chunk = this.getChunk(cx, cy);
        if (!chunk) {
            chunk = this.createEmptyChunk();
            this.setChunk(cx, cy, chunk);
        }
        // Store relative to chunk? Or absolute? 
        // The previous implementation used sparse maps. 
        // Let's store RELATIVE coordinates (0-31) in the key to stick to the chunk concept properly,
        // OR we can keep absolute coordinates if we want to just act as a bucket.
        // Client expects: roads data as list of standard tiles.
        // Let's store locally within the chunk using world coordinates key for simplicity in lookups,
        // or relative for data size? 
        // "x,y" string keys are fine.
        // Actually, to make it easy for client to reconstruct, keeping "localTileX,localTileY" is best.
        const localTileX = x % 32;
        const localTileY = y % 32;
        chunk.roads[`${localTileX},${localTileY}`] = tileId;
    }
    addWaterTile(x, y, tileId) {
        const pixelX = x * 16;
        const pixelY = y * 16;
        const { cx, cy } = this.worldToChunk(pixelX, pixelY);
        let chunk = this.getChunk(cx, cy);
        if (!chunk) {
            chunk = this.createEmptyChunk();
            this.setChunk(cx, cy, chunk);
        }
        const localTileX = x % 32;
        const localTileY = y % 32;
        chunk.water[`${localTileX},${localTileY}`] = tileId;
    }
    addRock(rock) {
        const { cx, cy } = this.worldToChunk(rock.x, rock.y);
        let chunk = this.getChunk(cx, cy);
        if (!chunk) {
            chunk = this.createEmptyChunk();
            this.setChunk(cx, cy, chunk);
        }
        chunk.rocks.push(rock);
    }
    addTree(tree) {
        const { cx, cy } = this.worldToChunk(tree.x, tree.y);
        let chunk = this.getChunk(cx, cy);
        if (!chunk) {
            chunk = this.createEmptyChunk();
            this.setChunk(cx, cy, chunk);
        }
        chunk.trees.push(tree);
    }
    createEmptyChunk() {
        return {
            roads: {},
            water: {},
            rocks: [],
            trees: [],
        };
    }
}
exports.ChunkManager = ChunkManager;
