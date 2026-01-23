"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.WorldGenerator = void 0;
// --- Constants ---
const TILE_SIZE = 16;
const CHUNK_SIZE = 512;
// Tile IDs (Matching Lua constants)
const ROAD_TILES = {
    CORNER_NW: 1, CORNER_NE: 3, CORNER_SW: 7, CORNER_SE: 9,
    EDGE_N: 2, EDGE_S: 8, EDGE_W: 4, EDGE_E: 6,
    CENTER: 5,
    INNER_NW: 14, INNER_NE: 13, INNER_SW: 11, INNER_SE: 10
};
const WATER_TILES = {
    CORNER_NW: 1, CORNER_NE: 3, CORNER_SW: 7, CORNER_SE: 9,
    EDGE_N: 2, EDGE_S: 8, EDGE_W: 4, EDGE_E: 6,
    CENTER: 5,
    INNER_NW: 14, INNER_NE: 13, INNER_SW: 11, INNER_SE: 10
};
// Simple pseudo-random number generator
class Alea {
    constructor(seed) {
        this.seed = seed;
    }
    // Returns [0, 1)
    next() {
        this.seed = (this.seed * 1664525 + 1013904223) % 4294967296;
        return this.seed / 4294967296;
    }
    // Returns [min, max] integer
    range(min, max) {
        return Math.floor(this.next() * (max - min + 1)) + min;
    }
}
class WorldGenerator {
    constructor(chunkManager, seed) {
        // Sparse maps for generation logic checks
        this.roadMap = {};
        this.waterMap = {};
        this.chunkManager = chunkManager;
        // We access world dimensions from chunkManager (we added public accessors ideally, assume standard size)
        this.worldWidth = 5000; // Passed in or hardcoded in server
        this.worldHeight = 5000;
        this.rng = new Alea(seed);
    }
    generate() {
        console.log('[WorldGenerator] Starting generation...');
        // 1. Roads
        this.generateRoads();
        // 2. Water
        this.generateWater();
        // 3. Objects (Trees, Rocks)
        this.generateObjects();
        console.log('[WorldGenerator] Generation complete.');
    }
    // --- Roads ---
    generateRoads() {
        const pointsOfInterest = [
            { x: 500, y: 500 }, // Top-left
            { x: 2500, y: 500 }, // Top-mid
            { x: 4500, y: 500 }, // Top-right
            { x: 500, y: 2500 }, // Mid-left
            { x: 2500, y: 2500 }, // Spawn center
            { x: 4500, y: 2500 }, // Mid-right
            { x: 500, y: 4500 }, // Bot-left
            { x: 2500, y: 4500 }, // Bot-mid
            { x: 4500, y: 4500 } // Bot-right
        ];
        // Connect points simply (1->2->3...)
        for (let i = 0; i < pointsOfInterest.length - 1; i++) {
            const p1 = pointsOfInterest[i];
            const p2 = pointsOfInterest[i + 1];
            // Convert to tile coordinates
            const start = { x: Math.floor(p1.x / TILE_SIZE), y: Math.floor(p1.y / TILE_SIZE) };
            const end = { x: Math.floor(p2.x / TILE_SIZE), y: Math.floor(p2.y / TILE_SIZE) };
            const path = this.findPath(start, end);
            if (path) {
                this.drawThickLine(path);
            }
        }
        // Add some random loops/connections? (Optional, skipping for parity with current Lua)
        // Bitmasking & Writing to ChunkManager
        this.finalizeRoads();
    }
    findPath(start, end) {
        // A* implementation
        // For simplicity heavily simplified since it's an open field mostly
        // But let's do a proper basic grid A*
        const heuristic = (a, b) => Math.abs(a.x - b.x) + Math.abs(a.y - b.y);
        const openSet = [{ pos: start, f: 0, g: 0 }];
        const cameFrom = {};
        const gScore = {};
        const fScore = {};
        const key = (p) => `${p.x},${p.y}`;
        gScore[key(start)] = 0;
        fScore[key(start)] = heuristic(start, end);
        let iterations = 0;
        while (openSet.length > 0 && iterations < 5000) {
            iterations++;
            // Sort by f
            openSet.sort((a, b) => a.f - b.f);
            const current = openSet.shift().pos;
            if (current.x === end.x && current.y === end.y) {
                // Reconstruct
                const path = [current];
                let curr = current;
                while (cameFrom[key(curr)]) {
                    curr = cameFrom[key(curr)];
                    path.unshift(curr);
                }
                return path;
            }
            const neighbors = [
                { x: current.x + 1, y: current.y }, { x: current.x - 1, y: current.y },
                { x: current.x, y: current.y + 1 }, { x: current.x, y: current.y - 1 }
            ];
            for (const neighbor of neighbors) {
                if (neighbor.x < 0 || neighbor.y < 0 || neighbor.x >= this.worldWidth / TILE_SIZE || neighbor.y >= this.worldHeight / TILE_SIZE)
                    continue;
                const tentativeG = gScore[key(current)] + 1;
                const nKey = key(neighbor);
                if (tentativeG < (gScore[nKey] ?? Infinity)) {
                    cameFrom[nKey] = current;
                    gScore[nKey] = tentativeG;
                    fScore[nKey] = tentativeG + heuristic(neighbor, end);
                    if (!openSet.some((node) => node.pos.x === neighbor.x && node.pos.y === neighbor.y)) {
                        openSet.push({ pos: neighbor, f: fScore[nKey], g: tentativeG });
                    }
                }
            }
        }
        return null;
    }
    drawThickLine(path) {
        const THICKNESS = 4; // radius
        for (const node of path) {
            for (let dy = -THICKNESS; dy <= THICKNESS; dy++) {
                for (let dx = -THICKNESS; dx <= THICKNESS; dx++) {
                    this.markRoad(node.x + dx, node.y + dy);
                }
            }
        }
    }
    markRoad(x, y) {
        this.roadMap[`${x},${y}`] = true;
    }
    isRoad(x, y) {
        return !!this.roadMap[`${x},${y}`];
    }
    finalizeRoads() {
        for (const key in this.roadMap) {
            const parts = key.split(',');
            const x = parseInt(parts[0]);
            const y = parseInt(parts[1]);
            const n = this.isRoad(x, y - 1) ? 1 : 0;
            const w = this.isRoad(x - 1, y) ? 1 : 0;
            const e = this.isRoad(x + 1, y) ? 1 : 0;
            const s = this.isRoad(x, y + 1) ? 1 : 0;
            const mask = (n * 1) + (w * 2) + (e * 4) + (s * 8);
            let tileID = ROAD_TILES.CENTER;
            if (mask === 12)
                tileID = ROAD_TILES.CORNER_NW;
            else if (mask === 10)
                tileID = ROAD_TILES.CORNER_NE;
            else if (mask === 5)
                tileID = ROAD_TILES.CORNER_SW;
            else if (mask === 3)
                tileID = ROAD_TILES.CORNER_SE;
            else if (mask === 14)
                tileID = ROAD_TILES.EDGE_N;
            else if (mask === 7)
                tileID = ROAD_TILES.EDGE_S;
            else if (mask === 11)
                tileID = ROAD_TILES.EDGE_E;
            else if (mask === 13)
                tileID = ROAD_TILES.EDGE_W;
            else if (mask === 15) {
                // Inner corners
                if (!this.isRoad(x + 1, y - 1))
                    tileID = ROAD_TILES.INNER_NE;
                else if (!this.isRoad(x - 1, y - 1))
                    tileID = ROAD_TILES.INNER_NW;
                else if (!this.isRoad(x + 1, y + 1))
                    tileID = ROAD_TILES.INNER_SE;
                else if (!this.isRoad(x - 1, y + 1))
                    tileID = ROAD_TILES.INNER_SW;
            }
            this.chunkManager.addRoadTile(x, y, tileID);
        }
    }
    // --- Water ---
    generateWater() {
        const potentialSeeds = [];
        // Find potential seeds near roads (ported from Lua)
        // We iterate roadMap
        for (const key in this.roadMap) {
            const [tx, ty] = key.split(',').map(Number);
            // Try 2 random spots per tile
            for (let i = 0; i < 2; i++) {
                const dx = this.rng.range(-4, 4);
                const dy = this.rng.range(-4, 4);
                if (Math.abs(dx) >= 2 || Math.abs(dy) >= 2) {
                    const targetX = tx + dx;
                    const targetY = ty + dy;
                    if (!this.isRoad(targetX, targetY) && !this.waterMap[`${targetX},${targetY}`]) {
                        const spawnDist = Math.sqrt(Math.pow(targetX * 16 - 2500, 2) + Math.pow(targetY * 16 - 2500, 2));
                        if (spawnDist > 150) {
                            // Check buffer
                            let tooClose = false;
                            for (let cx = -1; cx <= 1; cx++) {
                                for (let cy = -1; cy <= 1; cy++) {
                                    if (this.isRoad(targetX + cx, targetY + cy))
                                        tooClose = true;
                                }
                            }
                            if (!tooClose)
                                potentialSeeds.push({ x: targetX, y: targetY });
                        }
                    }
                }
            }
        }
        // Grow ponds
        for (const seed of potentialSeeds) {
            if (this.rng.next() < 0.05) { // 5% chance
                this.growPond(seed);
            }
        }
        // Smoothing
        this.smoothWater();
        // Finalize
        this.finalizeWater();
    }
    growPond(seed) {
        const targetSize = this.rng.range(15, 60);
        let currentSize = 0;
        const frontier = [seed];
        this.waterMap[`${seed.x},${seed.y}`] = true;
        currentSize++;
        while (currentSize < targetSize && frontier.length > 0) {
            const idx = this.rng.range(0, frontier.length - 1);
            const current = frontier[idx];
            let expanded = false;
            const dirs = [{ x: 0, y: 1 }, { x: 0, y: -1 }, { x: 1, y: 0 }, { x: -1, y: 0 }];
            for (const dir of dirs) {
                const nx = current.x + dir.x;
                const ny = current.y + dir.y;
                if (!this.waterMap[`${nx},${ny}`]) {
                    // Check road buffer
                    let safe = true;
                    for (let rx = -1; rx <= 1; rx++) {
                        for (let ry = -1; ry <= 1; ry++) {
                            if (this.isRoad(nx + rx, ny + ry))
                                safe = false;
                        }
                    }
                    if (safe) {
                        this.waterMap[`${nx},${ny}`] = true;
                        frontier.push({ x: nx, y: ny });
                        currentSize++;
                        expanded = true;
                        if (currentSize >= targetSize)
                            break;
                    }
                }
            }
            if (!expanded) {
                frontier.splice(idx, 1);
            }
            if (currentSize >= targetSize)
                break;
        }
    }
    smoothWater() {
        // Cellular automata smoothing
        // We implement specific bounds to avoid iterating full 5000x5000 tilemap (300*300)
        // Actually 5000px / 16 = 312 tiles.
        // Iterating 312x312 is trivial (approx 100k iters).
        const widthInTiles = Math.ceil(this.worldWidth / TILE_SIZE);
        const heightInTiles = Math.ceil(this.worldHeight / TILE_SIZE);
        for (let i = 0; i < 4; i++) {
            const newMap = {};
            for (let x = 0; x < widthInTiles; x++) {
                for (let y = 0; y < heightInTiles; y++) {
                    let neighbors = 0;
                    for (let dx = -1; dx <= 1; dx++) {
                        for (let dy = -1; dy <= 1; dy++) {
                            if (dx === 0 && dy === 0)
                                continue;
                            if (this.waterMap[`${x + dx},${y + dy}`])
                                neighbors++;
                        }
                    }
                    const isWater = this.waterMap[`${x},${y}`];
                    if (isWater) {
                        if (neighbors < 4) { /* die */ }
                        else
                            newMap[`${x},${y}`] = true;
                    }
                    else {
                        if (neighbors >= 5) {
                            // Check road safety
                            let safe = true;
                            if (this.isRoad(x, y))
                                safe = false;
                            else {
                                for (let rx = -1; rx <= 1; rx++) {
                                    for (let ry = -1; ry <= 1; ry++) {
                                        if (this.isRoad(x + rx, y + ry))
                                            safe = false;
                                    }
                                }
                            }
                            if (safe)
                                newMap[`${x},${y}`] = true;
                        }
                    }
                }
            }
            this.waterMap = newMap;
        }
    }
    finalizeWater() {
        for (const key in this.waterMap) {
            const [x, y] = key.split(',').map(Number);
            const n = this.waterMap[`${x},${y - 1}`] ? 1 : 0;
            const w = this.waterMap[`${x - 1},${y}`] ? 1 : 0;
            const e = this.waterMap[`${x + 1},${y}`] ? 1 : 0;
            const s = this.waterMap[`${x},${y + 1}`] ? 1 : 0;
            const mask = (n * 1) + (w * 2) + (e * 4) + (s * 8);
            let tileID = null;
            if (mask === 12)
                tileID = WATER_TILES.CORNER_NW;
            else if (mask === 10)
                tileID = WATER_TILES.CORNER_NE;
            else if (mask === 5)
                tileID = WATER_TILES.CORNER_SW;
            else if (mask === 3)
                tileID = WATER_TILES.CORNER_SE;
            else if (mask === 14)
                tileID = WATER_TILES.EDGE_N;
            else if (mask === 7)
                tileID = WATER_TILES.EDGE_S;
            else if (mask === 11)
                tileID = WATER_TILES.EDGE_E;
            else if (mask === 13)
                tileID = WATER_TILES.EDGE_W;
            else if (mask === 15) {
                if (!this.waterMap[`${x + 1},${y - 1}`])
                    tileID = WATER_TILES.INNER_NE;
                else if (!this.waterMap[`${x - 1},${y - 1}`])
                    tileID = WATER_TILES.INNER_NW;
                else if (!this.waterMap[`${x + 1},${y + 1}`])
                    tileID = WATER_TILES.INNER_SE;
                else if (!this.waterMap[`${x - 1},${y + 1}`])
                    tileID = WATER_TILES.INNER_SW;
                else
                    tileID = WATER_TILES.CENTER;
            }
            if (tileID) {
                this.chunkManager.addWaterTile(x, y, tileID);
            }
        }
    }
    // --- Objects ---
    generateObjects() {
        // Trees
        const numTrees = Math.floor((this.worldWidth * this.worldHeight) / 40000);
        const treeWidth = 48; // Estimate
        const treeHeight = 64;
        for (let i = 0; i < numTrees; i++) {
            const x = this.rng.range(0, this.worldWidth - treeWidth);
            const y = this.rng.range(0, this.worldHeight - treeHeight);
            // Validation
            const tx = Math.floor(x / TILE_SIZE);
            const ty = Math.floor((y + treeHeight) / TILE_SIZE);
            if (!this.isRoad(tx, ty)
                && !this.waterMap[`${tx},${ty}`]
                && !this.isRoad(Math.floor((x + treeWidth) / TILE_SIZE), ty)) {
                // Spawn distance check
                const distSq = Math.pow(x - 2500, 2) + Math.pow(y - 2500, 2);
                if (distSq > 40000) { // 200px
                    this.chunkManager.addTree({ x, y, width: treeWidth, height: treeHeight });
                }
            }
        }
        // Rocks
        const numRocks = Math.floor((this.worldWidth * this.worldHeight) / 100000);
        for (let i = 0; i < numRocks; i++) {
            const x = this.rng.range(0, this.worldWidth - 16);
            const y = this.rng.range(0, this.worldHeight - 16);
            const tx = Math.floor(x / TILE_SIZE);
            const ty = Math.floor(y / TILE_SIZE);
            if (!this.isRoad(tx, ty) && !this.waterMap[`${tx},${ty}`]) {
                const rockType = this.rng.range(0, 1) === 0 ? 3 : 4; // Types 3, 4
                // We need mapping from rock type to actual tile ID logic if it's complex, 
                // but client takes "tileId" and "actualTileNum".
                // Let's assume 3 and 4 are the ones we want.
                this.chunkManager.addRock({
                    x, y,
                    tileId: rockType,
                    actualTileNum: rockType // Fallback 
                });
            }
        }
    }
}
exports.WorldGenerator = WorldGenerator;
