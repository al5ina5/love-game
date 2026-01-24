export class SpatialGrid {
    private cellSize: number;
    private grid: Map<string, Set<string>>; // "cx,cy" -> Set<entityId>
    private entityPositions: Map<string, { x: number; y: number }>;

    constructor(cellSize: number = 512) {
        this.cellSize = cellSize;
        this.grid = new Map();
        this.entityPositions = new Map();
    }

    private getKey(x: number, y: number): string {
        const cx = Math.floor(x / this.cellSize);
        const cy = Math.floor(y / this.cellSize);
        return `${cx},${cy}`;
    }

    public updateEntity(id: string, x: number, y: number): void {
        const newKey = this.getKey(x, y);
        const split = newKey.split(',');
        const newCx = parseInt(split[0]);
        const newCy = parseInt(split[1]);

        const oldPos = this.entityPositions.get(id);
        if (oldPos) {
            const oldKey = this.getKey(oldPos.x, oldPos.y);
            if (oldKey !== newKey) {
                // Moved to new cell
                this.removeFromCell(oldKey, id);
                this.addToCell(newKey, id);
            }
        } else {
            // New entity
            this.addToCell(newKey, id);
        }

        // Always update position
        this.entityPositions.set(id, { x, y });
    }

    public removeEntity(id: string): void {
        const pos = this.entityPositions.get(id);
        if (pos) {
            const key = this.getKey(pos.x, pos.y);
            this.removeFromCell(key, id);
            this.entityPositions.delete(id);
        }
    }

    private addToCell(key: string, id: string): void {
        if (!this.grid.has(key)) {
            this.grid.set(key, new Set());
        }
        this.grid.get(key)!.add(id);
    }

    private removeFromCell(key: string, id: string): void {
        const cell = this.grid.get(key);
        if (cell) {
            cell.delete(id);
            if (cell.size === 0) {
                this.grid.delete(key);
            }
        }
    }

    public getNearbyEntityIds(x: number, y: number, viewDistanceOfCells: number = 1): Set<string> {
        const centerCx = Math.floor(x / this.cellSize);
        const centerCy = Math.floor(y / this.cellSize);
        const nearbyIds = new Set<string>();

        for (let dy = -viewDistanceOfCells; dy <= viewDistanceOfCells; dy++) {
            for (let dx = -viewDistanceOfCells; dx <= viewDistanceOfCells; dx++) {
                const key = `${centerCx + dx},${centerCy + dy}`;
                const cell = this.grid.get(key);
                if (cell) {
                    for (const id of cell) {
                        nearbyIds.add(id);
                    }
                }
            }
        }

        return nearbyIds;
    }
}
