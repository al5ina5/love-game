// server/src/world/AnimalManager.ts
// Server-authoritative animal management with LARGE wander radii for constant discovery

export interface Animal {
    id: string;
    x: number;
    y: number;
    spritePath: string;
    name: string;
    speed: number;
    state: string; // "idle", "grazing", "wandering"
    direction: string;
    groupCenterX: number;
    groupCenterY: number;
    groupRadius: number;
    stateTimer: number;
    nextStateTime: number;
    wanderDirection: number;
    wanderStepsRemaining: number;
    moving: boolean;
}

interface AnimalType {
    spritePath: string;
    name: string;
    speed: number;
}

interface FlockConfig {
    centerX: number;
    centerY: number;
    radius: number;
    distance: number; // 0.2-0.8, multiplier for radius
    count: number;
    animalType: AnimalType;
}

// Simple PRNG for deterministic generation
class Alea {
    private seed: number;
    constructor(seed: number) {
        this.seed = seed;
    }

    next(): number {
        this.seed = (this.seed * 1664525 + 1013904223) % 4294967296;
        return this.seed / 4294967296;
    }

    range(min: number, max: number): number {
        return Math.floor(this.next() * (max - min + 1)) + min;
    }
}

export class AnimalManager {
    private animals: { [animalId: string]: Animal } = {};
    private nextAnimalId: number = 1;
    private rng: Alea;
    private waterMap: { [key: string]: boolean };
    private worldWidth: number = 5000;
    private worldHeight: number = 5000;

    // Animal type definitions
    private animalTypes: { [key: string]: AnimalType } = {
        chicken: {
            spritePath: 'assets/img/sprites/animals/Clucking Chicken/CluckingChicken.png',
            name: 'Chicken',
            speed: 25,
        },
        pig: {
            spritePath: 'assets/img/sprites/animals/Dainty Pig/DaintyPig.png',
            name: 'Pig',
            speed: 20,
        },
        sheep: {
            spritePath: 'assets/img/sprites/animals/Pasturing Sheep/PasturingSheep.png',
            name: 'Sheep',
            speed: 22,
        },
        chick: {
            spritePath: 'assets/img/sprites/animals/Tiny Chick/TinyChick.png',
            name: 'Chick',
            speed: 18,
        },
        fox: {
            spritePath: 'assets/img/sprites/animals/Snow Fox/SnowFox.png',
            name: 'Fox',
            speed: 35,
        },
        wolf: {
            spritePath: 'assets/img/sprites/animals/Timber Wolf/TimberWolf.png',
            name: 'Wolf',
            speed: 40,
        },
        porcupine: {
            spritePath: 'assets/img/sprites/animals/Spikey Porcupine/SpikeyPorcupine.png',
            name: 'Porcupine',
            speed: 18,
        },
        cat: {
            spritePath: 'assets/img/sprites/animals/Meowing Cat/MeowingCat.png',
            name: 'Cat',
            speed: 35,
        },
        toad: {
            spritePath: 'assets/img/sprites/animals/Croaking Toad/CroakingToad.png',
            name: 'Toad',
            speed: 15,
        },
        frog: {
            spritePath: 'assets/img/sprites/animals/Leaping Frog/LeapingFrog.png',
            name: 'Frog',
            speed: 30,
        },
        turtle: {
            spritePath: 'assets/img/sprites/animals/Slow Turtle/SlowTurtle.png',
            name: 'Turtle',
            speed: 12,
        },
        boar: {
            spritePath: 'assets/img/sprites/animals/Mad Boar/MadBoar.png',
            name: 'Boar',
            speed: 32,
        },
        skunk: {
            spritePath: 'assets/img/sprites/animals/Stinky Skunk/StinkySkunk.png',
            name: 'Skunk',
            speed: 28,
        },
        goose: {
            spritePath: 'assets/img/sprites/animals/Honking Goose/HonkingGoose.png',
            name: 'Goose',
            speed: 33,
        },
        crab: {
            spritePath: 'assets/img/sprites/animals/Coral Crab/CoralCrab.png',
            name: 'Crab',
            speed: 20,
        },
    };

    constructor(seed: number, waterMap: { [key: string]: boolean }) {
        this.rng = new Alea(seed);
        this.waterMap = waterMap;
    }

    public generate(): void {
        console.log('[AnimalManager] Generating animals with LARGE wander radii for constant discovery...');

        const WORLD_W = this.worldWidth;
        const WORLD_H = this.worldHeight;

        // LARGE RADII (400-800px) with HIGH DISTANCE multipliers (0.7-0.9)
        // This creates sparse groups where animals wander FAR from center
        // You'll encounter animals everywhere as you stroll!
        // Occasional tight groups (20-30 animals) for "OMG look a family" moments

        const flocks: FlockConfig[] = [
            // Scattered across entire world - LARGE wander areas
            // Northwest region
            { centerX: WORLD_W * 0.15, centerY: WORLD_H * 0.15, radius: 600, distance: 0.85, count: 50, animalType: this.animalTypes.chicken },
            { centerX: WORLD_W * 0.2, centerY: WORLD_H * 0.1, radius: 550, distance: 0.8, count: 40, animalType: this.animalTypes.pig },
            { centerX: WORLD_W * 0.1, centerY: WORLD_H * 0.2, radius: 650, distance: 0.9, count: 45, animalType: this.animalTypes.sheep },
            { centerX: WORLD_W * 0.25, centerY: WORLD_H * 0.25, radius: 500, distance: 0.75, count: 35, animalType: this.animalTypes.chick },

            // Northeast region
            { centerX: WORLD_W * 0.85, centerY: WORLD_H * 0.15, radius: 700, distance: 0.85, count: 50, animalType: this.animalTypes.fox },
            { centerX: WORLD_W * 0.8, centerY: WORLD_H * 0.2, radius: 650, distance: 0.8, count: 45, animalType: this.animalTypes.wolf },
            { centerX: WORLD_W * 0.9, centerY: WORLD_H * 0.25, radius: 600, distance: 0.75, count: 40, animalType: this.animalTypes.cat },
            { centerX: WORLD_W * 0.75, centerY: WORLD_H * 0.1, radius: 550, distance: 0.7, count: 35, animalType: this.animalTypes.porcupine },

            // Southeast region
            { centerX: WORLD_W * 0.85, centerY: WORLD_H * 0.85, radius: 700, distance: 0.85, count: 50, animalType: this.animalTypes.toad },
            { centerX: WORLD_W * 0.8, centerY: WORLD_H * 0.8, radius: 650, distance: 0.8, count: 45, animalType: this.animalTypes.frog },
            { centerX: WORLD_W * 0.9, centerY: WORLD_H * 0.75, radius: 600, distance: 0.75, count: 40, animalType: this.animalTypes.turtle },
            { centerX: WORLD_W * 0.75, centerY: WORLD_H * 0.9, radius: 550, distance: 0.7, count: 35, animalType: this.animalTypes.goose },

            // Southwest region
            { centerX: WORLD_W * 0.15, centerY: WORLD_H * 0.85, radius: 700, distance: 0.85, count: 50, animalType: this.animalTypes.boar },
            { centerX: WORLD_W * 0.2, centerY: WORLD_H * 0.8, radius: 650, distance: 0.8, count: 45, animalType: this.animalTypes.skunk },
            { centerX: WORLD_W * 0.1, centerY: WORLD_H * 0.75, radius: 600, distance: 0.75, count: 40, animalType: this.animalTypes.goose },
            { centerX: WORLD_W * 0.25, centerY: WORLD_H * 0.9, radius: 550, distance: 0.7, count: 35, animalType: this.animalTypes.crab },

            // Center regions - animals everywhere!
            { centerX: WORLD_W * 0.5, centerY: WORLD_H * 0.5, radius: 800, distance: 0.9, count: 60, animalType: this.animalTypes.chicken },
            { centerX: WORLD_W * 0.45, centerY: WORLD_H * 0.45, radius: 750, distance: 0.85, count: 55, animalType: this.animalTypes.sheep },
            { centerX: WORLD_W * 0.55, centerY: WORLD_H * 0.55, radius: 700, distance: 0.8, count: 50, animalType: this.animalTypes.pig },
            { centerX: WORLD_W * 0.5, centerY: WORLD_H * 0.4, radius: 650, distance: 0.75, count: 45, animalType: this.animalTypes.chick },
            { centerX: WORLD_W * 0.5, centerY: WORLD_H * 0.6, radius: 600, distance: 0.7, count: 40, animalType: this.animalTypes.frog },

            // North edge
            { centerX: WORLD_W * 0.3, centerY: WORLD_H * 0.1, radius: 650, distance: 0.8, count: 45, animalType: this.animalTypes.wolf },
            { centerX: WORLD_W * 0.5, centerY: WORLD_H * 0.15, radius: 700, distance: 0.85, count: 50, animalType: this.animalTypes.fox },
            { centerX: WORLD_W * 0.7, centerY: WORLD_H * 0.1, radius: 600, distance: 0.75, count: 40, animalType: this.animalTypes.cat },

            // South edge
            { centerX: WORLD_W * 0.3, centerY: WORLD_H * 0.9, radius: 650, distance: 0.8, count: 45, animalType: this.animalTypes.toad },
            { centerX: WORLD_W * 0.5, centerY: WORLD_H * 0.85, radius: 700, distance: 0.85, count: 50, animalType: this.animalTypes.frog },
            { centerX: WORLD_W * 0.7, centerY: WORLD_H * 0.9, radius: 600, distance: 0.75, count: 40, animalType: this.animalTypes.crab },

            // East edge
            { centerX: WORLD_W * 0.9, centerY: WORLD_H * 0.3, radius: 650, distance: 0.8, count: 45, animalType: this.animalTypes.chicken },
            { centerX: WORLD_W * 0.85, centerY: WORLD_H * 0.5, radius: 700, distance: 0.85, count: 50, animalType: this.animalTypes.sheep },
            { centerX: WORLD_W * 0.9, centerY: WORLD_H * 0.7, radius: 600, distance: 0.75, count: 40, animalType: this.animalTypes.goose },

            // West edge
            { centerX: WORLD_W * 0.1, centerY: WORLD_H * 0.3, radius: 650, distance: 0.8, count: 45, animalType: this.animalTypes.pig },
            { centerX: WORLD_W * 0.15, centerY: WORLD_H * 0.5, radius: 700, distance: 0.85, count: 50, animalType: this.animalTypes.boar },
            { centerX: WORLD_W * 0.1, centerY: WORLD_H * 0.7, radius: 600, distance: 0.75, count: 40, animalType: this.animalTypes.skunk },

            // Mid regions - more coverage
            { centerX: WORLD_W * 0.35, centerY: WORLD_H * 0.35, radius: 650, distance: 0.8, count: 45, animalType: this.animalTypes.chicken },
            { centerX: WORLD_W * 0.65, centerY: WORLD_H * 0.35, radius: 700, distance: 0.85, count: 50, animalType: this.animalTypes.fox },
            { centerX: WORLD_W * 0.35, centerY: WORLD_H * 0.65, radius: 600, distance: 0.75, count: 40, animalType: this.animalTypes.frog },
            { centerX: WORLD_W * 0.65, centerY: WORLD_H * 0.65, radius: 650, distance: 0.8, count: 45, animalType: this.animalTypes.goose },

            // RARE tight family groups (20-30 animals close together)
            { centerX: WORLD_W * 0.2, centerY: WORLD_H * 0.3, radius: 80, distance: 0.3, count: 25, animalType: this.animalTypes.chick },
            { centerX: WORLD_W * 0.8, centerY: WORLD_H * 0.3, radius: 90, distance: 0.35, count: 28, animalType: this.animalTypes.chicken },
            { centerX: WORLD_W * 0.3, centerY: WORLD_H * 0.7, radius: 85, distance: 0.32, count: 26, animalType: this.animalTypes.sheep },
            { centerX: WORLD_W * 0.7, centerY: WORLD_H * 0.7, radius: 95, distance: 0.38, count: 30, animalType: this.animalTypes.pig },
        ];

        // Generate animals from flock configs
        for (const flock of flocks) {
            this.createFlock(flock);
        }

        console.log(`[AnimalManager] Generated ${Object.keys(this.animals).length} animals in ${flocks.length} groups (mostly spread out, few tight families)`);
    }

    private createFlock(config: FlockConfig): void {
        for (let i = 0; i < config.count; i++) {
            const angle = (i / config.count) * Math.PI * 2 + this.rng.next() * Math.PI / 4;
            const distance = config.radius * config.distance * (0.5 + this.rng.next() * 0.5);
            const offsetX = Math.cos(angle) * distance;
            const offsetY = Math.sin(angle) * distance;

            const x = config.centerX + offsetX;
            const y = config.centerY + offsetY;

            // Validate position (not in water, not too close to spawn)
            if (this.isValidPosition(x, y)) {
                this.createAnimal(x, y, config.animalType, config.centerX, config.centerY, config.radius);
            }
        }
    }

    private isValidPosition(x: number, y: number): boolean {
        // Check spawn distance (200px minimum)
        const spawnDist = Math.sqrt(Math.pow(x - 2500, 2) + Math.pow(y - 2500, 2));
        if (spawnDist < 200) return false;

        // Check water collision (convert to tile coords)
        const tileX = Math.floor(x / 16);
        const tileY = Math.floor(y / 16);
        if (this.waterMap[`${tileX},${tileY}`]) return false;

        // Check bounds
        if (x < 0 || x >= this.worldWidth || y < 0 || y >= this.worldHeight) return false;

        return true;
    }

    private createAnimal(
        x: number,
        y: number,
        animalType: AnimalType,
        groupCenterX: number,
        groupCenterY: number,
        groupRadius: number
    ): void {
        const animalId = `animal_${this.nextAnimalId++}`;

        this.animals[animalId] = {
            id: animalId,
            x,
            y,
            spritePath: animalType.spritePath,
            name: animalType.name,
            speed: animalType.speed,
            state: 'idle',
            direction: 'down',
            groupCenterX,
            groupCenterY,
            groupRadius,
            stateTimer: 0,
            nextStateTime: this.rng.range(3, 8),
            wanderDirection: this.rng.next() * Math.PI * 2,
            wanderStepsRemaining: 0,
            moving: false,
        };
    }

    public update(dt: number): void {
        // Update each animal's AI state
        for (const animalId in this.animals) {
            const animal = this.animals[animalId];
            this.updateAnimal(animal, dt);
        }
    }

    private updateAnimal(animal: Animal, dt: number): void {
        // Update state timer
        animal.stateTimer += dt;

        // State transitions
        if (animal.stateTimer >= animal.nextStateTime) {
            this.transitionAnimalState(animal);
        }

        // Movement for wandering state
        if (animal.state === 'wandering' && animal.wanderStepsRemaining > 0) {
            const peacefulSpeed = animal.speed * 0.6;
            const moveX = Math.cos(animal.wanderDirection) * peacefulSpeed * dt;
            const moveY = Math.sin(animal.wanderDirection) * peacefulSpeed * dt;

            const newX = animal.x + moveX;
            const newY = animal.y + moveY;

            // Validate new position
            if (this.isValidPosition(newX, newY)) {
                animal.x = newX;
                animal.y = newY;
                animal.moving = true;

                // Update direction
                this.updateAnimalDirection(animal);
            } else {
                // Hit obstacle, stop wandering
                animal.wanderStepsRemaining = 0;
                animal.moving = false;
            }
        } else {
            animal.moving = false;
        }

        // Keep within group bounds
        const dx = animal.x - animal.groupCenterX;
        const dy = animal.y - animal.groupCenterY;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist > animal.groupRadius) {
            const angle = Math.atan2(dy, dx);
            animal.x = animal.groupCenterX + Math.cos(angle) * animal.groupRadius;
            animal.y = animal.groupCenterY + Math.sin(angle) * animal.groupRadius;
            if (animal.state === 'wandering') {
                animal.state = 'idle';
                animal.stateTimer = 0;
                animal.nextStateTime = this.rng.range(2, 5);
            }
        }
    }

    private transitionAnimalState(animal: Animal): void {
        animal.stateTimer = 0;

        if (animal.state === 'idle') {
            if (this.rng.next() < 0.4) {
                animal.state = 'grazing';
                animal.nextStateTime = this.rng.range(4, 8);
                animal.direction = 'down';
            } else {
                animal.state = 'wandering';
                this.startWandering(animal);
                animal.nextStateTime = this.rng.range(2, 4);
            }
        } else if (animal.state === 'grazing') {
            if (this.rng.next() < 0.6) {
                animal.state = 'idle';
                animal.nextStateTime = this.rng.range(3, 7);
            } else {
                animal.state = 'wandering';
                this.startWandering(animal);
                animal.nextStateTime = this.rng.range(2, 4);
            }
        } else if (animal.state === 'wandering') {
            if (this.rng.next() < 0.5) {
                animal.state = 'idle';
                animal.nextStateTime = this.rng.range(4, 8);
            } else {
                animal.state = 'grazing';
                animal.nextStateTime = this.rng.range(3, 6);
            }
            animal.wanderStepsRemaining = 0;
            animal.moving = false;
        }
    }

    private startWandering(animal: Animal): void {
        const dx = animal.groupCenterX - animal.x;
        const dy = animal.groupCenterY - animal.y;
        const distToCenter = Math.sqrt(dx * dx + dy * dy);

        if (distToCenter > animal.groupRadius * 0.8) {
            animal.wanderDirection = Math.atan2(dy, dx);
        } else {
            const angleToCenter = Math.atan2(dy, dx);
            animal.wanderDirection = angleToCenter + (this.rng.next() - 0.5) * (Math.PI * 2 / 3);
        }

        animal.wanderStepsRemaining = this.rng.range(2, 4);
    }

    private updateAnimalDirection(animal: Animal): void {
        const angle = animal.wanderDirection;
        if (angle >= -Math.PI / 4 && angle < Math.PI / 4) {
            animal.direction = 'right';
        } else if (angle >= Math.PI / 4 && angle < (3 * Math.PI) / 4) {
            animal.direction = 'down';
        } else if (angle >= (3 * Math.PI) / 4 || angle < (-3 * Math.PI) / 4) {
            animal.direction = 'left';
        } else {
            animal.direction = 'up';
        }
    }

    public getAnimals(): { [animalId: string]: Animal } {
        return this.animals;
    }
}
