// server/src/game_server.ts
// Server-authoritative game server for Boon Snatch
// Always running, manages extraction cycles, authoritative for all game state

interface Player {
  id: string;
  x: number;
  y: number;
  direction: string;
  hp: number;
  maxHp: number;
  boons: any[];
  kills: number;
  deaths: number;
  invulnerable: boolean;
  invulnerableTimer: number;
  extracted: boolean;
  skin?: string;
  sprinting?: boolean;
  lastProcessedSeq?: number;
}

interface Projectile {
  id: string;
  x: number;
  y: number;
  vx: number;
  vy: number;
  ownerId: string;
  damage: number;
  lifetime: number;
}

interface Chest {
  id: string;
  x: number;
  y: number;
  opened: boolean;
  respawnTimer: number;
  rarity: string;
}

interface NPC {
  id: string;
  x: number;
  y: number;
  spritePath: string;
  name: string;
  dialogue: string[];
}

interface Animal {
  id: string;
  x: number;
  y: number;
  spritePath: string;
  name: string;
  speed: number;
  state: string;
  direction: string;
  groupCenterX: number;
  groupCenterY: number;
  groupRadius: number;
}

interface Pet {
  x: number;
  y: number;
  monster?: string;
}

interface GameState {
  players: { [playerId: string]: Player };
  pets: { [playerId: string]: Pet }; // One pet per player
  projectiles: { [projId: string]: Projectile };
  chests: { [chestId: string]: Chest };
  npcs: { [npcId: string]: NPC };
  animals: { [animalId: string]: Animal };
  cycleStartTime: number;
  cycleDuration: number; // 20 minutes in milliseconds
  cycleTimeRemaining: number; // milliseconds
  extractionZones: Array<{ x: number; y: number; radius: number }>;
  deadlyEventActive: boolean;
}

import { ChunkManager, ChunkData } from './world/ChunkManager';
import { WorldGenerator } from './world/WorldGenerator';
import { AnimalManager } from './world/AnimalManager';
import { SpatialGrid } from './world/SpatialGrid';

export class GameServer {
  private state: GameState;
  // Match client world size: 2,500x2,500 pixels (smaller for MIYO optimization)
  private worldWidth: number = 2500;
  private worldHeight: number = 2500;
  private nextProjectileId: number = 1;
  private nextChestId: number = 1;
  private lastUpdate: number = Date.now();
  private updateInterval: NodeJS.Timeout | null = null;
  private readonly CYCLE_DURATION = 20 * 60 * 1000; // 20 minutes in milliseconds
  private readonly UPDATE_RATE = 1 / 60; // 60 updates per second
  private readonly PROJECTILE_SPEED = 400; // pixels per second
  private readonly PROJECTILE_DAMAGE = 10;
  private readonly PROJECTILE_LIFETIME = 3.0; // seconds
  private readonly MONSTER_SPRITES = [
    "Blinded Grimlock",
    "Bloodshot Eye",
    "Brawny Ogre",
    "Crimson Slaad",
    "Crushing Cyclops",
    "Death Slime",
    "Fungal Myconid",
    "Humongous Ettin",
    "Murky Slaad",
    "Ochre Jelly",
    "Ocular Watcher",
    "Red Cap",
    "Shrieker Mushroom",
    "Stone Troll",
    "Swamp Troll",
  ];

  private chunkManager: ChunkManager;
  private animalManager: AnimalManager | null = null;
  private spatialGrid: SpatialGrid;

  constructor() {
    this.spatialGrid = new SpatialGrid(512); // Grid cell size 512px
    this.state = {
      players: {},
      pets: {}, // Initialize empty pets object
      projectiles: {},
      chests: {},
      npcs: {},
      animals: {},
      cycleStartTime: Date.now(),
      cycleDuration: this.CYCLE_DURATION,
      cycleTimeRemaining: this.CYCLE_DURATION,
      extractionZones: [
        { x: 250, y: 250, radius: 50 }, // Top-left
        { x: 2250, y: 250, radius: 50 }, // Top-right
        { x: 250, y: 2250, radius: 50 }, // Bottom-left
        { x: 2250, y: 2250, radius: 50 }, // Bottom-right
      ],
      deadlyEventActive: false,
    };

    // Initialize World Generation
    this.chunkManager = new ChunkManager(this.worldWidth, this.worldHeight);
    const worldGen = new WorldGenerator(this.chunkManager, 12345); // Fixed seed for now
    worldGen.generate();

    // Create Animals
    this.animalManager = worldGen.getAnimalManager();
    if (this.animalManager) {
      const animals = this.animalManager.getAnimals();
      for (const animalId in animals) {
        const animal = animals[animalId];
        this.state.animals[animalId] = { ...animal };
        this.spatialGrid.updateEntity(animalId, animal.x, animal.y);
      }
    }

    // Spawn initial chests
    this.spawnInitialChests(10);

    // Create NPCs
    this.createNPCs();

    // Start game loop
    this.startGameLoop();
  }

  public getChunkData(cx: number, cy: number): ChunkData | null {
    return this.chunkManager.getChunk(cx, cy);
  }

  // Get complete world data for client pre-loading (MIYO optimization)
  public getCompleteWorldData(): any {
    console.log('[GameServer] Preparing complete world data for client...');

    const worldData = {
      worldWidth: this.worldWidth,
      worldHeight: this.worldHeight,
      chunks: {} as { [key: string]: ChunkData },
      npcs: this.getNPCs(),
      animals: this.getAnimals(),
      timestamp: Date.now()
    };

    // Get all chunks from chunk manager
    const allChunks = this.chunkManager.getAllChunks();
    for (const [chunkKey, chunkData] of Object.entries(allChunks)) {
      worldData.chunks[chunkKey] = chunkData;
    }

    console.log(`[GameServer] World data prepared: ${Object.keys(worldData.chunks).length} chunks, ${worldData.npcs.length} NPCs, ${worldData.animals.length} animals`);
    return worldData;
  }

  private startGameLoop(): void {
    const update = () => {
      const now = Date.now();
      const dt = (now - this.lastUpdate) / 1000; // Convert to seconds
      this.lastUpdate = now;

      this.update(dt);
    };

    // Run at 60 FPS
    this.updateInterval = setInterval(update, 1000 / 60);
  }

  private update(dt: number): void {
    // Update cycle timer
    const elapsed = Date.now() - this.state.cycleStartTime;
    this.state.cycleTimeRemaining = Math.max(0, this.state.cycleDuration - elapsed);

    // Check if cycle ended (deadly event)
    if (this.state.cycleTimeRemaining <= 0 && !this.state.deadlyEventActive) {
      this.triggerDeadlyEvent();
    }

    // Update animals
    if (this.animalManager) {
      this.animalManager.update(dt);
      // Sync animal state from manager to game state
      const animals = this.animalManager.getAnimals();
      for (const animalId in animals) {
        const animal = animals[animalId];
        if (this.state.animals[animalId]) {
          this.state.animals[animalId].x = animal.x;
          this.state.animals[animalId].y = animal.y;
          this.state.animals[animalId].state = animal.state;
          this.state.animals[animalId].direction = animal.direction;

          this.spatialGrid.updateEntity(animalId, animal.x, animal.y);
        }
      }
    }

    // Update game state
    this.updateProjectiles(dt);
    this.updateChests(dt);
    this.updatePlayerInvulnerability(dt);
    this.updatePets(dt); // Update pets to follow owners
  }

  private triggerDeadlyEvent(): void {
    console.log('[GameServer] Deadly event triggered - killing all players');
    this.state.deadlyEventActive = true;

    // Kill all non-extracted players
    for (const playerId in this.state.players) {
      const player = this.state.players[playerId];
      if (!player.extracted) {
        player.hp = 0;
        player.deaths++;
      }
    }

    // Reset cycle after a short delay (5 seconds)
    setTimeout(() => {
      this.resetCycle();
    }, 5000);
  }

  private resetCycle(): void {
    console.log('[GameServer] Resetting extraction cycle');
    this.state.cycleStartTime = Date.now();
    this.state.cycleTimeRemaining = this.state.cycleDuration;
    this.state.deadlyEventActive = false;

    // Respawn all players
    for (const playerId in this.state.players) {
      const player = this.state.players[playerId];
      this.respawnPlayer(playerId);
    }

    // Respawn chests
    this.spawnInitialChests(10);
  }

  addPlayer(playerId: string, x?: number, y?: number): void {
    let spawnX: number;
    let spawnY: number;

    if (x !== undefined && y !== undefined) {
      // Use provided coordinates
      spawnX = x;
      spawnY = y;
    } else {
      // Scatter players in a small spawn area (1-2 tiles = 16-32 pixels apart)
      const centerX = this.worldWidth / 2;
      const centerY = this.worldHeight / 2;
      const spawnRadius = 40; // Maximum distance from center (2.5 tiles)
      const minDistance = 24; // Minimum distance between players (1.5 tiles)

      // Try to find a valid spawn position that doesn't collide with existing players
      let attempts = 0;
      const maxAttempts = 50;
      do {
        const angle = Math.random() * Math.PI * 2;
        const distance = Math.random() * spawnRadius;
        spawnX = centerX + Math.cos(angle) * distance;
        spawnY = centerY + Math.sin(angle) * distance;

        // Check collision with existing players
        let tooClose = false;
        for (const pid in this.state.players) {
          if (pid !== playerId) {
            const player = this.state.players[pid];
            const dx = spawnX - player.x;
            const dy = spawnY - player.y;
            const dist = Math.sqrt(dx * dx + dy * dy);
            if (dist < minDistance) {
              tooClose = true;
              break;
            }
          }
        }

        attempts++;
        if (!tooClose) break;
      } while (attempts < maxAttempts);

      // If we couldn't find a good spot after many attempts, just use a random offset
      if (attempts >= maxAttempts) {
        spawnX = centerX + (Math.random() - 0.5) * spawnRadius * 2;
        spawnY = centerY + (Math.random() - 0.5) * spawnRadius * 2;
      }
    }

    this.state.players[playerId] = {
      id: playerId,
      x: spawnX,
      y: spawnY,
      direction: 'down',
      hp: 100,
      maxHp: 100,
      boons: [],
      kills: 0,
      deaths: 0,
      invulnerable: false,
      invulnerableTimer: 0,
      extracted: false,
    };

    // Create pet for this player
    const monster = this.MONSTER_SPRITES[Math.floor(Math.random() * this.MONSTER_SPRITES.length)];
    this.state.pets[playerId] = {
      x: spawnX,
      y: spawnY,
      monster,
    };

    this.spatialGrid.updateEntity(playerId, spawnX, spawnY);

    console.log(`[GameServer] Player ${playerId} added at (${spawnX}, ${spawnY}) with pet`);
  }

  removePlayer(playerId: string): void {
    delete this.state.players[playerId];
    delete this.state.pets[playerId]; // Remove pet too
    this.spatialGrid.removeEntity(playerId);
    console.log(`[GameServer] Player ${playerId} removed`);
  }

  updatePlayerPosition(playerId: string, direction: string, batch: { dx: number, dy: number, sprinting: boolean, dt: number, seq: number }[]): void {
    const player = this.state.players[playerId];
    if (!player || batch.length === 0) return;

    for (const input of batch) {
      // Skip already processed inputs
      if (player.lastProcessedSeq !== undefined && input.seq <= player.lastProcessedSeq) {
        continue;
      }

      const speed = 60 * (input.sprinting ? 1.5 : 1.0);
      const dt = Math.min(input.dt, 0.1); // Clamp dt for safety

      const newX = player.x + input.dx * speed * dt;
      const newY = player.y + input.dy * speed * dt;

      // Validate move
      if (this.canMoveTo(newX, newY)) {
        player.x = newX;
        player.y = newY;
      } else {
        // Sliding
        if (this.canMoveTo(newX, player.y)) {
          player.x = newX;
        } else if (this.canMoveTo(player.x, newY)) {
          player.y = newY;
        }
      }

      player.lastProcessedSeq = input.seq;
      player.sprinting = input.sprinting;
    }

    player.direction = direction;
    this.spatialGrid.updateEntity(playerId, player.x, player.y);
  }

  handleShoot(playerId: string, angle: number): void {
    const player = this.state.players[playerId];
    if (!player) return;

    // Calculate damage with boon modifiers
    let damage = this.PROJECTILE_DAMAGE;
    for (const boon of player.boons) {
      if (boon.type === 'damage_boost') {
        damage = damage * (1 + (boon.data?.multiplier || 0.5));
      }
    }

    // Create projectile
    const projId = `proj_${this.nextProjectileId++}`;
    const vx = Math.cos(angle) * this.PROJECTILE_SPEED;
    const vy = Math.sin(angle) * this.PROJECTILE_SPEED;

    this.state.projectiles[projId] = {
      id: projId,
      x: player.x,
      y: player.y,
      vx,
      vy,
      ownerId: playerId,
      damage,
      lifetime: this.PROJECTILE_LIFETIME,
    };

    console.log(`[GameServer] Player ${playerId} shot projectile ${projId}`);
  }

  handleInteract(playerId: string): void {
    const player = this.state.players[playerId];
    if (!player) return;

    // Check for nearby chests (within 32 pixels)
    const interactRange = 32;
    for (const chestId in this.state.chests) {
      const chest = this.state.chests[chestId];
      if (!chest.opened) {
        const dx = player.x - chest.x;
        const dy = player.y - chest.y;
        const dist = Math.sqrt(dx * dx + dy * dy);

        if (dist <= interactRange) {
          // Open chest and grant boon
          chest.opened = true;
          chest.respawnTimer = 30.0;

          const boonType = this.generateRandomBoon(chest.rarity);
          player.boons.push({
            type: boonType,
            data: { rarity: chest.rarity },
            rarity: chest.rarity,
          });

          console.log(`[GameServer] Player ${playerId} opened chest ${chestId}, got boon ${boonType}`);
          return; // Only open one chest at a time
        }
      }
    }

    // Check for extraction zones
    for (const zone of this.state.extractionZones) {
      const dx = player.x - zone.x;
      const dy = player.y - zone.y;
      const dist = Math.sqrt(dx * dx + dy * dy);

      if (dist <= zone.radius && !player.extracted) {
        player.extracted = true;
        console.log(`[GameServer] Player ${playerId} extracted at zone (${zone.x}, ${zone.y})`);
        // Could add extraction timer/sequence here
      }
    }
  }

  private canMoveTo(x: number, y: number): boolean {
    // 1. World Bounds
    if (x < 0 || x >= this.worldWidth || y < 0 || y >= this.worldHeight) return false;

    // 2. Tile-based collision (Rocks/Water)
    const { cx, cy } = this.chunkManager.worldToChunk(x, y);
    const chunk = this.chunkManager.getChunk(cx, cy);
    if (!chunk) return true; // If chunk not loaded yet on server, allow (should technically not happen)

    const lx = Math.floor((x % this.chunkManager.CHUNK_SIZE) / 16);
    const ly = Math.floor((y % this.chunkManager.CHUNK_SIZE) / 16);
    const tileKey = `${lx},${ly}`;

    // Block water
    if (chunk.water[tileKey]) return false;

    // 3. Object-based collision (Rocks/Trees)
    // For simplicity, we'll check against trees/rocks in this chunk and neighbors
    // Note: This is an approximation for now to avoid high CPU spikes
    for (const tree of chunk.trees) {
      const trunkX = tree.x + 24;
      const trunkY = tree.y + 57;
      if (x >= trunkX && x <= trunkX + 16 && y >= trunkY && y <= trunkY + 8) return false;
    }

    return true;
  }

  private updateProjectiles(dt: number): void {
    const projectilesToRemove: string[] = [];

    for (const projId in this.state.projectiles) {
      const proj = this.state.projectiles[projId];

      // Move projectile
      proj.x += proj.vx * dt;
      proj.y += proj.vy * dt;
      proj.lifetime -= dt;

      // Check bounds
      if (proj.x < 0 || proj.x > this.worldWidth || proj.y < 0 || proj.y > this.worldHeight) {
        projectilesToRemove.push(projId);
        continue;
      }

      // Check collision with players
      for (const playerId in this.state.players) {
        const player = this.state.players[playerId];
        if (playerId !== proj.ownerId && !player.invulnerable) {
          const dx = player.x - proj.x;
          const dy = player.y - proj.y;
          const dist = Math.sqrt(dx * dx + dy * dy);

          if (dist < 16) {
            // Hit!
            player.hp = Math.max(0, player.hp - proj.damage);
            projectilesToRemove.push(projId);

            if (player.hp <= 0) {
              // Player died - steal boons!
              const killer = this.state.players[proj.ownerId];
              if (killer) {
                const stolenCount = player.boons.length;
                killer.boons.push(...player.boons);
                player.boons = [];
                killer.kills++;
                player.deaths++;
              }

              // Respawn player
              this.respawnPlayer(playerId);
            }

            break; // Projectile hit someone, remove it
          }
        }
      }

      // Remove expired projectiles
      if (proj.lifetime <= 0) {
        projectilesToRemove.push(projId);
      }
    }

    // Remove projectiles
    for (const projId of projectilesToRemove) {
      delete this.state.projectiles[projId];
    }
  }

  private updateChests(dt: number): void {
    for (const chestId in this.state.chests) {
      const chest = this.state.chests[chestId];
      if (chest.opened) {
        chest.respawnTimer -= dt;
        if (chest.respawnTimer <= 0) {
          chest.opened = false;
        }
      }
    }
  }

  private updatePlayerInvulnerability(dt: number): void {
    for (const playerId in this.state.players) {
      const player = this.state.players[playerId];
      if (player.invulnerable) {
        player.invulnerableTimer -= dt;
        if (player.invulnerableTimer <= 0) {
          player.invulnerable = false;
        }
      }
    }
  }

  private updatePets(dt: number): void {
    const PET_SPEED = 45; // Base movement speed from client
    const PET_CATCH_UP_SPEED = 80; // Catch up speed from client
    const PREFERRED_DISTANCE = 25; // Sweet spot distance from owner
    const MAX_DISTANCE = 50; // Too far! Catch up

    for (const playerId in this.state.players) {
      const player = this.state.players[playerId];
      const pet = this.state.pets[playerId];

      if (pet && player) {
        const dx = player.x - pet.x;
        const dy = player.y - pet.y;
        const dist = Math.sqrt(dx * dx + dy * dy);

        // Determine speed based on distance
        let speed = 0;
        if (dist > MAX_DISTANCE) {
          speed = PET_CATCH_UP_SPEED;
        } else if (dist > PREFERRED_DISTANCE) {
          speed = PET_SPEED;
        }

        if (speed > 0) {
          const moveDist = speed * dt;
          // Move toward player until preferred distance is reached
          const ratio = Math.min(1, moveDist / dist);
          pet.x += dx * ratio;
          pet.y += dy * ratio;
        }
      }
    }
  }

  private respawnPlayer(playerId: string): void {
    const player = this.state.players[playerId];
    if (!player) return;

    // Random spawn location (avoid center where players start)
    const margin = 100;
    player.x = margin + Math.random() * (this.worldWidth - margin * 2);
    player.y = margin + Math.random() * (this.worldHeight - margin * 2);
    player.hp = player.maxHp;
    player.invulnerable = true;
    player.invulnerableTimer = 3.0; // 3 seconds of invulnerability
    player.extracted = false;

    this.spatialGrid.updateEntity(playerId, player.x, player.y);
  }

  private spawnInitialChests(count: number): void {
    // Clear existing chests
    this.state.chests = {};
    this.nextChestId = 1;

    for (let i = 0; i < count; i++) {
      const x = 100 + Math.random() * (this.worldWidth - 200);
      const y = 100 + Math.random() * (this.worldHeight - 200);
      let rarity = 'common';
      if (Math.random() < 0.1) rarity = 'rare';
      if (Math.random() < 0.02) rarity = 'epic';

      const chestId = `chest_${this.nextChestId++}`;
      this.state.chests[chestId] = {
        id: chestId,
        x,
        y,
        opened: false,
        respawnTimer: 0,
        rarity,
      };
    }
  }

  private generateRandomBoon(rarity: string): string {
    const boons: { [key: string]: string[] } = {
      common: ['damage_boost', 'speed_boost', 'hp_boost'],
      rare: ['triple_shot', 'piercing', 'lifesteal'],
      epic: ['dash', 'shield', 'slow_enemies'],
      legendary: ['teleport', 'steal_on_hit', 'boss_damage'],
    };

    const availableBoons = boons[rarity] || boons.common;
    return availableBoons[Math.floor(Math.random() * availableBoons.length)];
  }

  private createNPCs(): void {
    // Create NPCs matching the client's NPC positions (server-authoritative)
    const npcs: Array<{ id: string; x: number; y: number; spritePath: string; name: string; dialogue: string[] }> = [
      // Part 1: The Beard Guy (Overworked Villager) - Starts the mystery
      {
        id: 'npc_1',
        x: this.worldWidth * 0.15,
        y: this.worldHeight * 0.15,
        spritePath: 'assets/img/sprites/humans/Overworked Villager/OverworkedVillager.png',
        name: 'Old Wanderer',
        dialogue: [
          "They say love is the key. But to what door? I've forgotten.",
          "The one who walks the ancient paths might remember. Find the keeper of old truths.",
        ],
      },
      // Part 2: Elf Lord - The ancient truth
      {
        id: 'npc_2',
        x: this.worldWidth * 0.85,
        y: this.worldHeight * 0.2,
        spritePath: 'assets/img/sprites/humans/Elf Lord/ElfLord.png',
        name: 'Keeper of Truths',
        dialogue: [
          'Love binds what time cannot. It\'s the thread that holds worlds together.',
          'But threads can fray. The mystic knows how they connect. Seek the one who reads the currents.',
        ],
      },
      // Part 3: Merfolk Mystic - The connection
      {
        id: 'npc_3',
        x: this.worldWidth * 0.8,
        y: this.worldHeight * 0.75,
        spritePath: 'assets/img/sprites/humans/Merfolk Mystic/MerfolkMystic.png',
        name: 'Current Reader',
        dialogue: [
          'Every bond is a current. Love flows between souls like water between stones.',
          'But currents can be redirected. The enchanter understands this power. Find the one who shapes what cannot be seen.',
        ],
      },
      // Part 4: Elf Enchanter - The power
      {
        id: 'npc_4',
        x: this.worldWidth * 0.2,
        y: this.worldHeight * 0.8,
        spritePath: 'assets/img/sprites/humans/Elf Enchanter/ElfEnchanter.png',
        name: 'Shape Shifter',
        dialogue: [
          'Love shapes reality itself. It\'s not just feeling—it\'s a force that remakes the world.',
          'But forces can be dangerous. The young wanderer has seen what happens when it breaks. Look for the one who carries scars.',
        ],
      },
      // Part 5: Adventurous Adolescent - The warning
      {
        id: 'npc_5',
        x: this.worldWidth * 0.5,
        y: this.worldHeight * 0.1,
        spritePath: 'assets/img/sprites/humans/Adventurous Adolescent/AdventurousAdolescent.png',
        name: 'Scarred Wanderer',
        dialogue: [
          'I\'ve seen what happens when love is lost. The world grows cold. Colors fade.',
          'But I\'ve also seen it return. The loud one knows how. Find the voice that never quiets.',
        ],
      },
      // Part 6: Boisterous Youth - The revelation
      {
        id: 'npc_6',
        x: this.worldWidth * 0.5,
        y: this.worldHeight * 0.9,
        spritePath: 'assets/img/sprites/humans/Boisterous Youth/BoisterousYouth.png',
        name: 'The Voice',
        dialogue: [
          'Love isn\'t found—it\'s chosen. Every moment you choose connection over isolation.',
          'The wayfarer has walked this path longer than any. They know where it leads. Find the one who never stops moving.',
        ],
      },
      // Part 7: Elf Wayfarer - The conclusion
      // Moved away from spawn point (2500, 2500) to avoid collision with players
      {
        id: 'npc_7',
        x: this.worldWidth * 0.52,
        y: this.worldHeight * 0.48,
        spritePath: 'assets/img/sprites/humans/Elf Wayfarer/ElfWayfarer.png',
        name: 'The Eternal Walker',
        dialogue: [
          'I\'ve walked every path. Love is the only thing that makes any of them matter.',
          'Without it, we\'re just shadows moving through an empty world. With it... we become real.',
          'The old wanderer was right. It is the key. But the door? That\'s for you to find.',
        ],
      },
      // Additional NPCs for flavor
      {
        id: 'npc_8',
        x: this.worldWidth * 0.25,
        y: this.worldHeight * 0.3,
        spritePath: 'assets/img/sprites/humans/Joyful Kid/JoyfulKid.png',
        name: 'Little One',
        dialogue: [
          'Everyone talks about love but nobody explains it!',
          'Maybe the grown-ups don\'t know either?',
        ],
      },
      {
        id: 'npc_9',
        x: this.worldWidth * 0.75,
        y: this.worldHeight * 0.3,
        spritePath: 'assets/img/sprites/humans/Playful Child/PlayfulChild.png',
        name: 'Curious Child',
        dialogue: [
          'I heard the old wanderer talking about keys and doors!',
          'Do you think there\'s a secret door somewhere?',
        ],
      },
      {
        id: 'npc_10',
        x: this.worldWidth * 0.3,
        y: this.worldHeight * 0.7,
        spritePath: 'assets/img/sprites/humans/Elf Bladedancer/ElfBladedancer.png',
        name: 'Silent Guardian',
        dialogue: [
          'I guard the paths. Many seek answers. Few find them.',
          'The truth is scattered. You must gather all the pieces.',
        ],
      },
    ];

    // Add NPCs to state
    for (const npc of npcs) {
      this.state.npcs[npc.id] = npc;
      this.spatialGrid.updateEntity(npc.id, npc.x, npc.y);
    }

    console.log(`[GameServer] Created ${npcs.length} NPCs`);
  }

  getNPCs(): NPC[] {
    return Object.values(this.state.npcs);
  }

  getAnimals(): Animal[] {
    return Object.values(this.state.animals);
  }

  getStateSnapshot(): string {
    return JSON.stringify({
      players: this.state.players,
      projectiles: this.state.projectiles,
      chests: this.state.chests,
      npcs: this.state.npcs,
      animals: this.state.animals,
      cycleTimeRemaining: this.state.cycleTimeRemaining,
      cycleDuration: this.state.cycleDuration,
      deadlyEventActive: this.state.deadlyEventActive,
      extractionZones: this.state.extractionZones,
    });
  }

  getPlayerStateSnapshot(playerId: string): string {
    const player = this.state.players[playerId];
    if (!player) return this.getStateSnapshot(); // Fallback if player invalid

    // Get nearby entity IDs from grid (e.g., 2 cells view distance = 1000px radius approx)
    const nearbyIds = this.spatialGrid.getNearbyEntityIds(player.x, player.y, 2);

    const relevantState: any = {
      players: {},
      pets: {}, // Include pets
      projectiles: {}, // Projectiles might be fast, maybe redundant spatial check?
      chests: {}, // Chests are static? No, they open/close. Should add to grid.
      npcs: {},
      animals: {},
      // Globals
      cycleTimeRemaining: this.state.cycleTimeRemaining,
      cycleDuration: this.state.cycleDuration,
      deadlyEventActive: this.state.deadlyEventActive,
      extractionZones: this.state.extractionZones,
    };

    // Include self always
    relevantState.players[playerId] = player;

    // Include ALL players (not just nearby) - players need to see all other players
    // Spatial filtering for players causes issues where remote players disappear/reappear
    for (const pid in this.state.players) {
      relevantState.players[pid] = this.state.players[pid];
      // Include pet for each player
      if (this.state.pets[pid]) {
        relevantState.pets[pid] = this.state.pets[pid];
      }
    }

    // Filter NPCs
    for (const nid in this.state.npcs) {
      if (nearbyIds.has(nid)) {
        relevantState.npcs[nid] = this.state.npcs[nid];
      }
    }

    // Filter Animals
    for (const aid in this.state.animals) {
      if (nearbyIds.has(aid)) {
        relevantState.animals[aid] = this.state.animals[aid];
      }
    }

    // TODO: Projectiles and chests currently NOT in spatial grid, so we send all.
    // Ideally put them in grid too. For now sending all is safer than invisible bullets.
    relevantState.projectiles = this.state.projectiles;
    relevantState.chests = this.state.chests;

    return JSON.stringify(relevantState);
  }

  getCycleTimeRemaining(): number {
    return this.state.cycleTimeRemaining;
  }

  getCycleDuration(): number {
    return this.state.cycleDuration;
  }

  destroy(): void {
    if (this.updateInterval) {
      clearInterval(this.updateInterval);
      this.updateInterval = null;
    }
  }
}
