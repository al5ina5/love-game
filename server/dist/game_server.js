"use strict";
// server/src/game_server.ts
// Server-authoritative game server for Boon Snatch
// Always running, manages extraction cycles, authoritative for all game state
Object.defineProperty(exports, "__esModule", { value: true });
exports.GameServer = void 0;
const ChunkManager_1 = require("./world/ChunkManager");
const WorldGenerator_1 = require("./world/WorldGenerator");
class GameServer {
    constructor() {
        // Match client world size: 5,000x5,000 pixels (takes ~1 minute to walk across at sprint)
        this.worldWidth = 5000;
        this.worldHeight = 5000;
        this.nextProjectileId = 1;
        this.nextChestId = 1;
        this.lastUpdate = Date.now();
        this.updateInterval = null;
        this.CYCLE_DURATION = 20 * 60 * 1000; // 20 minutes in milliseconds
        this.UPDATE_RATE = 1 / 60; // 60 updates per second
        this.PROJECTILE_SPEED = 400; // pixels per second
        this.PROJECTILE_DAMAGE = 10;
        this.PROJECTILE_LIFETIME = 3.0; // seconds
        this.state = {
            players: {},
            projectiles: {},
            chests: {},
            npcs: {},
            cycleStartTime: Date.now(),
            cycleDuration: this.CYCLE_DURATION,
            cycleTimeRemaining: this.CYCLE_DURATION,
            extractionZones: [
                { x: 500, y: 500, radius: 50 }, // Top-left
                { x: 4500, y: 500, radius: 50 }, // Top-right
                { x: 500, y: 4500, radius: 50 }, // Bottom-left
                { x: 4500, y: 4500, radius: 50 }, // Bottom-right
            ],
            deadlyEventActive: false,
        };
        // Initialize World Generation
        this.chunkManager = new ChunkManager_1.ChunkManager(this.worldWidth, this.worldHeight);
        const worldGen = new WorldGenerator_1.WorldGenerator(this.chunkManager, 12345); // Fixed seed for now
        worldGen.generate();
        // Spawn initial chests
        this.spawnInitialChests(10);
        // Create NPCs (server-authoritative)
        this.createNPCs();
        // Start game loop
        this.startGameLoop();
    }
    getChunkData(cx, cy) {
        return this.chunkManager.getChunk(cx, cy);
    }
    startGameLoop() {
        const update = () => {
            const now = Date.now();
            const dt = (now - this.lastUpdate) / 1000; // Convert to seconds
            this.lastUpdate = now;
            this.update(dt);
        };
        // Run at 60 FPS
        this.updateInterval = setInterval(update, 1000 / 60);
    }
    update(dt) {
        // Update cycle timer
        const elapsed = Date.now() - this.state.cycleStartTime;
        this.state.cycleTimeRemaining = Math.max(0, this.state.cycleDuration - elapsed);
        // Check if cycle ended (deadly event)
        if (this.state.cycleTimeRemaining <= 0 && !this.state.deadlyEventActive) {
            this.triggerDeadlyEvent();
        }
        // Update projectiles
        this.updateProjectiles(dt);
        // Update chest respawn timers
        this.updateChests(dt);
        // Update player invulnerability
        this.updatePlayerInvulnerability(dt);
    }
    triggerDeadlyEvent() {
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
    resetCycle() {
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
    addPlayer(playerId, x, y) {
        let spawnX;
        let spawnY;
        if (x !== undefined && y !== undefined) {
            // Use provided coordinates
            spawnX = x;
            spawnY = y;
        }
        else {
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
                if (!tooClose)
                    break;
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
        console.log(`[GameServer] Player ${playerId} added at (${spawnX}, ${spawnY})`);
    }
    removePlayer(playerId) {
        delete this.state.players[playerId];
        console.log(`[GameServer] Player ${playerId} removed`);
    }
    updatePlayerPosition(playerId, x, y, direction, sprinting) {
        const player = this.state.players[playerId];
        if (!player)
            return;
        // Server validates and updates position
        // Could add collision checking here
        player.x = Math.max(0, Math.min(this.worldWidth, x));
        player.y = Math.max(0, Math.min(this.worldHeight, y));
        player.direction = direction;
        if (sprinting !== undefined) {
            player.sprinting = sprinting;
        }
    }
    handleShoot(playerId, angle) {
        const player = this.state.players[playerId];
        if (!player)
            return;
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
    handleInteract(playerId) {
        const player = this.state.players[playerId];
        if (!player)
            return;
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
    updateProjectiles(dt) {
        const projectilesToRemove = [];
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
    updateChests(dt) {
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
    updatePlayerInvulnerability(dt) {
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
    respawnPlayer(playerId) {
        const player = this.state.players[playerId];
        if (!player)
            return;
        // Random spawn location (avoid center where players start)
        const margin = 100;
        player.x = margin + Math.random() * (this.worldWidth - margin * 2);
        player.y = margin + Math.random() * (this.worldHeight - margin * 2);
        player.hp = player.maxHp;
        player.invulnerable = true;
        player.invulnerableTimer = 3.0; // 3 seconds of invulnerability
        player.extracted = false;
    }
    spawnInitialChests(count) {
        // Clear existing chests
        this.state.chests = {};
        this.nextChestId = 1;
        for (let i = 0; i < count; i++) {
            const x = 100 + Math.random() * (this.worldWidth - 200);
            const y = 100 + Math.random() * (this.worldHeight - 200);
            let rarity = 'common';
            if (Math.random() < 0.1)
                rarity = 'rare';
            if (Math.random() < 0.02)
                rarity = 'epic';
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
    generateRandomBoon(rarity) {
        const boons = {
            common: ['damage_boost', 'speed_boost', 'hp_boost'],
            rare: ['triple_shot', 'piercing', 'lifesteal'],
            epic: ['dash', 'shield', 'slow_enemies'],
            legendary: ['teleport', 'steal_on_hit', 'boss_damage'],
        };
        const availableBoons = boons[rarity] || boons.common;
        return availableBoons[Math.floor(Math.random() * availableBoons.length)];
    }
    createNPCs() {
        // Create NPCs matching the client's NPC positions (server-authoritative)
        const npcs = [
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
        }
        console.log(`[GameServer] Created ${npcs.length} NPCs`);
    }
    getNPCs() {
        return Object.values(this.state.npcs);
    }
    getStateSnapshot() {
        return JSON.stringify({
            players: this.state.players,
            projectiles: this.state.projectiles,
            chests: this.state.chests,
            npcs: this.state.npcs,
            cycleTimeRemaining: this.state.cycleTimeRemaining,
            cycleDuration: this.state.cycleDuration,
            deadlyEventActive: this.state.deadlyEventActive,
            extractionZones: this.state.extractionZones,
        });
    }
    getCycleTimeRemaining() {
        return this.state.cycleTimeRemaining;
    }
    getCycleDuration() {
        return this.state.cycleDuration;
    }
    destroy() {
        if (this.updateInterval) {
            clearInterval(this.updateInterval);
            this.updateInterval = null;
        }
    }
}
exports.GameServer = GameServer;
