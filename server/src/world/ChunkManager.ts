
export interface ChunkData {
  roads: { [key: string]: number }; // sparse map: "x,y" => tileID
  water: { [key: string]: number }; // sparse map: "x,y" => tileID
  rocks: Array<{ x: number; y: number; tileId: number; actualTileNum: number }>;
  trees: Array<{ x: number; y: number; width: number; height: number; type: string }>;
}

export class ChunkManager {
  private chunks: { [key: string]: ChunkData } = {};
  public readonly CHUNK_SIZE = 512; // 32x32 tiles (16px)
  private worldWidth: number;
  private worldHeight: number;

  constructor(worldWidth: number, worldHeight: number) {
    this.worldWidth = worldWidth;
    this.worldHeight = worldHeight;
  }

  // Get chunk key from chunk coordinates
  private getChunkKey(cx: number, cy: number): string {
    return `${cx},${cy}`;
  }

  // Get chunk coordinates from world position
  public worldToChunk(x: number, y: number): { cx: number; cy: number } {
    return {
      cx: Math.floor(x / this.CHUNK_SIZE),
      cy: Math.floor(y / this.CHUNK_SIZE),
    };
  }

  public getChunk(cx: number, cy: number): ChunkData | null {
    const key = this.getChunkKey(cx, cy);
    return this.chunks[key] || null;
  }

  public setChunk(cx: number, cy: number, data: ChunkData): void {
    const key = this.getChunkKey(cx, cy);
    this.chunks[key] = data;
  }

  public getAllChunks(): { [key: string]: ChunkData } {
    return this.chunks;
  }

  // Helper to add a road tile to the appropriate chunk
  public addRoadTile(x: number, y: number, tileId: number): void {
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

  public addWaterTile(x: number, y: number, tileId: number): void {
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

  public addRock(rock: { x: number; y: number; tileId: number; actualTileNum: number }): void {
    const { cx, cy } = this.worldToChunk(rock.x, rock.y);
    let chunk = this.getChunk(cx, cy);
    if (!chunk) {
      chunk = this.createEmptyChunk();
      this.setChunk(cx, cy, chunk);
    }
    chunk.rocks.push(rock);
  }

  public addTree(tree: { x: number; y: number; width: number; height: number; type: string }): void {
    const { cx, cy } = this.worldToChunk(tree.x, tree.y);
    let chunk = this.getChunk(cx, cy);
    if (!chunk) {
      chunk = this.createEmptyChunk();
      this.setChunk(cx, cy, chunk);
    }
    chunk.trees.push(tree);
  }

  private createEmptyChunk(): ChunkData {
    return {
      roads: {},
      water: {},
      rocks: [],
      trees: [],
    };
  }
}
