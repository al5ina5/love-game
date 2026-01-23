"use strict";
// server/src/game_server.ts
// Server-authoritative game server for Boon Snatch
// Always running, manages extraction cycles, authoritative for all game state
Object.defineProperty(exports, "__esModule", { value: true });
exports.GameServer = void 0;
class GameServer {
    constructor() {
        this.worldWidth = 1600;
        this.worldHeight = 1200;
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
            cycleStartTime: Date.now(),
            cycleDuration: this.CYCLE_DURATION,
            cycleTimeRemaining: this.CYCLE_DURATION,
            extractionZones: [
                { x: 100, y: 100, radius: 50 }, // Top-left
                { x: 1500, y: 100, radius: 50 }, // Top-right
                { x: 100, y: 1100, radius: 50 }, // Bottom-left
                { x: 1500, y: 1100, radius: 50 }, // Bottom-right
            ],
            deadlyEventActive: false,
        };
        // Spawn initial chests
        this.spawnInitialChests(10);
        // Start game loop
        this.startGameLoop();
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
        const spawnX = x ?? this.worldWidth / 2;
        const spawnY = y ?? this.worldHeight / 2;
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
    getStateSnapshot() {
        return JSON.stringify({
            players: this.state.players,
            projectiles: this.state.projectiles,
            chests: this.state.chests,
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
