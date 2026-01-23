# Next Steps: Making Boon Snatch a Real Game

## Current Status ✅
- ✅ Networking (LAN + Online)
- ✅ Movement & Multiplayer
- ✅ NPCs & World
- ✅ Basic Interactions
- ⚠️ Shooting (partially working - projectiles exist but may not be visible)
- ⚠️ Chests (exist, can open, grant boons server-side)
- ⚠️ Boons (server-side, but no visual feedback)

## Priority 1: Make Core Loop Playable (THE HOOK) 🎯

### 1. Fix Shooting & Make It Visible
**Why**: Players need to see their bullets to feel like they're playing a game
- ✅ Projectiles are created (server-side)
- ❌ Projectiles may not be rendering
- ❌ No visual feedback when shooting
- **Action**: Debug projectile rendering, ensure they're visible

### 2. Make Boons Actually Work (Apply Effects)
**Why**: Boons are the core mechanic - they need to DO something
- ✅ Boons are granted (server-side)
- ❌ Boons don't actually modify gameplay yet
- **Action**: Apply boon effects:
  - `damage_boost`: Increase projectile damage
  - `speed_boost`: Increase player movement speed
  - `hp_boost`: Increase max HP
  - `triple_shot`: Fire 3 projectiles instead of 1
  - `piercing`: Projectiles pass through players

### 3. Add HP Bar & Death Feedback
**Why**: Players need to see when they're hurt/dying
- ❌ No HP display
- ❌ No death animation/feedback
- ❌ No respawn feedback
- **Action**: 
  - Draw HP bar above player
  - Show death animation (fade out, particles)
  - Show respawn animation (fade in, invulnerability glow)

### 4. Implement Win Condition (First to 5 Kills)
**Why**: Game needs a goal/end state
- ✅ Kill tracking exists (server-side)
- ❌ No win detection
- ❌ No match end screen
- **Action**:
  - Check for win condition in server logic
  - Show "VICTORY" / "DEFEAT" screen
  - Display stats (kills, deaths, boons collected)

## Priority 2: Make It Feel Like a Game 🎮

### 5. Boon UI (Show Active Boons)
**Why**: Players need to see what powers they have
- **Options to discuss**:
  - **Option A**: Icons around player (like Hades)
  - **Option B**: Status bar at top/bottom of screen
  - **Option C**: List in corner with tooltips
  - **Option D**: Floating icons above player head

### 6. Scoreboard/HUD
**Why**: Players need to see progress
- Show kills/deaths for all players
- Show match timer
- Show active boon count
- Show chest count remaining

### 7. Visual Feedback for Everything
- **Chest opening**: Animation, sound, particle effect
- **Boon granted**: Notification popup ("+Triple Shot!")
- **Player hit**: Damage number, screen shake
- **Player killed**: Big notification, sound effect
- **Boon stolen**: Notification ("Stole 3 boons!")

## Priority 3: Polish & Expand 🌟

### 8. Enemies (PvE)
- Spawn AI enemies that drop boons
- Adds PvE element to complement PvP

### 9. Boss System
- Big boss spawns after timer
- Mega loot on kill
- End-game goal

### 10. Extraction System
- Extraction points at map edges
- Risk/reward: extract early or stay for boss

---

## Recommended Order (Make It Playable First!)

**Week 1: Core Loop**
1. Fix shooting visibility ✅ (in progress)
2. Apply boon effects (damage, speed, HP)
3. Add HP bars & death feedback
4. Implement win condition (first to 5 kills)

**Week 2: Feel Like a Game**
5. Boon UI (discuss design)
6. Scoreboard/HUD
7. Visual feedback (notifications, animations)

**Week 3: Expand**
8. Enemies (PvE)
9. Boss system
10. Extraction system

---

## Quick Wins (Do These First!)

1. **Apply `damage_boost` boon** - Easiest, immediate impact
2. **Apply `speed_boost` boon** - Very noticeable
3. **Show HP bar** - Simple rectangle, huge impact
4. **Win condition check** - Just a few lines of code

These 4 things will make it feel like a real game immediately!
