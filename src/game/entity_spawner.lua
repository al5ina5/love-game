-- src/game/entity_spawner.lua
-- Creates NPCs and animals in the world

local EntitySpawner = {}

local WORLD_W = 5000
local WORLD_H = 5000

function EntitySpawner.createNPCs()
    local NPC = require('src.entities.npc')
    local npcs = {}
    
    local beardGuy = NPC:new(
        WORLD_W * 0.15, WORLD_H * 0.15,
        "assets/img/sprites/humans/Overworked Villager/OverworkedVillager.png",
        "Old Wanderer",
        {
            "They say love is the key. But to what door? I've forgotten.",
            "The one who walks the ancient paths might remember. Find the keeper of old truths.",
        }
    )
    table.insert(npcs, beardGuy)
    
    local elfLord = NPC:new(
        WORLD_W * 0.85, WORLD_H * 0.2,
        "assets/img/sprites/humans/Elf Lord/ElfLord.png",
        "Keeper of Truths",
        {
            "Love binds what time cannot. It's the thread that holds worlds together.",
            "But threads can fray. The mystic knows how they connect. Seek the one who reads the currents.",
        }
    )
    table.insert(npcs, elfLord)
    
    local merfolkMystic = NPC:new(
        WORLD_W * 0.8, WORLD_H * 0.75,
        "assets/img/sprites/humans/Merfolk Mystic/MerfolkMystic.png",
        "Current Reader",
        {
            "Every bond is a current. Love flows between souls like water between stones.",
            "But currents can be redirected. The enchanter understands this power. Find the one who shapes what cannot be seen.",
        }
    )
    table.insert(npcs, merfolkMystic)
    
    local elfEnchanter = NPC:new(
        WORLD_W * 0.2, WORLD_H * 0.8,
        "assets/img/sprites/humans/Elf Enchanter/ElfEnchanter.png",
        "Shape Shifter",
        {
            "Love shapes reality itself. It's not just feeling—it's a force that remakes the world.",
            "But forces can be dangerous. The young wanderer has seen what happens when it breaks. Look for the one who carries scars.",
        }
    )
    table.insert(npcs, elfEnchanter)
    
    local adventurousAdolescent = NPC:new(
        WORLD_W * 0.5, WORLD_H * 0.1,
        "assets/img/sprites/humans/Adventurous Adolescent/AdventurousAdolescent.png",
        "Scarred Wanderer",
        {
            "I've seen what happens when love is lost. The world grows cold. Colors fade.",
            "But I've also seen it return. The loud one knows how. Find the voice that never quiets.",
        }
    )
    table.insert(npcs, adventurousAdolescent)
    
    local boisterousYouth = NPC:new(
        WORLD_W * 0.5, WORLD_H * 0.9,
        "assets/img/sprites/humans/Boisterous Youth/BoisterousYouth.png",
        "The Voice",
        {
            "Love isn't found—it's chosen. Every moment you choose connection over isolation.",
            "The wayfarer has walked this path longer than any. They know where it leads. Find the one who never stops moving.",
        }
    )
    table.insert(npcs, boisterousYouth)
    
    -- Move Elf Wayfarer away from spawn point (2500, 2500) to avoid collision
    -- Place it slightly northeast of center to maintain story significance
    local elfWayfarer = NPC:new(
        WORLD_W * 0.52, WORLD_H * 0.48,
        "assets/img/sprites/humans/Elf Wayfarer/ElfWayfarer.png",
        "The Eternal Walker",
        {
            "I've walked every path. Love is the only thing that makes any of them matter.",
            "Without it, we're just shadows moving through an empty world. With it... we become real.",
            "The old wanderer was right. It is the key. But the door? That's for you to find.",
        }
    )
    table.insert(npcs, elfWayfarer)
    
    local joyfulKid = NPC:new(
        WORLD_W * 0.25, WORLD_H * 0.3,
        "assets/img/sprites/humans/Joyful Kid/JoyfulKid.png",
        "Little One",
        {
            "Everyone talks about love but nobody explains it!",
            "Maybe the grown-ups don't know either?",
        }
    )
    table.insert(npcs, joyfulKid)
    
    local playfulChild = NPC:new(
        WORLD_W * 0.75, WORLD_H * 0.3,
        "assets/img/sprites/humans/Playful Child/PlayfulChild.png",
        "Curious Child",
        {
            "I heard the old wanderer talking about keys and doors!",
            "Do you think there's a secret door somewhere?",
        }
    )
    table.insert(npcs, playfulChild)
    
    local elfBladedancer = NPC:new(
        WORLD_W * 0.3, WORLD_H * 0.7,
        "assets/img/sprites/humans/Elf Bladedancer/ElfBladedancer.png",
        "Silent Guardian",
        {
            "I guard the paths. Many seek answers. Few find them.",
            "The truth is scattered. You must gather all the pieces.",
        }
    )
    table.insert(npcs, elfBladedancer)
    
    return npcs
end

function EntitySpawner.createAnimalGroups()
    local Animal = require('src.entities.animal')
    local animals = {}
    
    local function addAnimalGroup(centerX, centerY, radius, animalData)
        for i = 1, animalData.count do
            local angle = (i / animalData.count) * math.pi * 2 + (animalData.offset or 0)
            local offsetX = math.cos(angle) * (radius * animalData.distance)
            local offsetY = math.sin(angle) * (radius * animalData.distance)
            local animal = Animal:new(
                centerX + offsetX,
                centerY + offsetY,
                animalData.spritePath,
                animalData.name,
                animalData.speed
            )
            animal:setGroupCenter(centerX, centerY, radius)
            table.insert(animals, animal)
        end
    end
    
    -- Farm animals (northwest)
    local farmX, farmY, farmR = WORLD_W * 0.15, WORLD_H * 0.15, 400
    addAnimalGroup(farmX, farmY, farmR, {count = 4, distance = 0.3, spritePath = "assets/img/sprites/animals/Clucking Chicken/CluckingChicken.png", name = "Chicken", speed = 25})
    addAnimalGroup(farmX, farmY, farmR, {count = 3, distance = 0.5, spritePath = "assets/img/sprites/animals/Dainty Pig/DaintyPig.png", name = "Pig", speed = 20})
    addAnimalGroup(farmX, farmY, farmR, {count = 3, distance = 0.4, offset = math.pi / 6, spritePath = "assets/img/sprites/animals/Pasturing Sheep/PasturingSheep.png", name = "Sheep", speed = 22})
    
    -- Forest animals (northeast)
    local forestX, forestY, forestR = WORLD_W * 0.85, WORLD_H * 0.2, 450
    addAnimalGroup(forestX, forestY, forestR, {count = 3, distance = 0.4, spritePath = "assets/img/sprites/animals/Snow Fox/SnowFox.png", name = "Fox", speed = 35})
    addAnimalGroup(forestX, forestY, forestR, {count = 2, distance = 0.6, spritePath = "assets/img/sprites/animals/Timber Wolf/TimberWolf.png", name = "Wolf", speed = 40})
    addAnimalGroup(forestX, forestY, forestR, {count = 2, distance = 0.3, offset = math.pi / 4, spritePath = "assets/img/sprites/animals/Spikey Porcupine/SpikeyPorcupine.png", name = "Porcupine", speed = 18})
    
    -- Swamp animals (southeast)
    local swampX, swampY, swampR = WORLD_W * 0.8, WORLD_H * 0.8, 400
    addAnimalGroup(swampX, swampY, swampR, {count = 4, distance = 0.35, spritePath = "assets/img/sprites/animals/Croaking Toad/CroakingToad.png", name = "Toad", speed = 15})
    addAnimalGroup(swampX, swampY, swampR, {count = 3, distance = 0.5, offset = math.pi / 6, spritePath = "assets/img/sprites/animals/Leaping Frog/LeapingFrog.png", name = "Frog", speed = 30})
    addAnimalGroup(swampX, swampY, swampR, {count = 2, distance = 0.25, spritePath = "assets/img/sprites/animals/Slow Turtle/SlowTurtle.png", name = "Turtle", speed = 12})
    
    -- Wild animals (southwest)
    local wildX, wildY, wildR = WORLD_W * 0.2, WORLD_H * 0.85, 450
    addAnimalGroup(wildX, wildY, wildR, {count = 3, distance = 0.4, spritePath = "assets/img/sprites/animals/Mad Boar/MadBoar.png", name = "Boar", speed = 32})
    addAnimalGroup(wildX, wildY, wildR, {count = 2, distance = 0.5, offset = math.pi / 4, spritePath = "assets/img/sprites/animals/Stinky Skunk/StinkySkunk.png", name = "Skunk", speed = 28})
    addAnimalGroup(wildX, wildY, wildR, {count = 3, distance = 0.3, offset = math.pi / 6, spritePath = "assets/img/sprites/animals/Honking Goose/HonkingGoose.png", name = "Goose", speed = 33})
    
    -- Coastal animals (center-east)
    local coastalX, coastalY, coastalR = WORLD_W * 0.7, WORLD_H * 0.5, 400
    addAnimalGroup(coastalX, coastalY, coastalR, {count = 4, distance = 0.4, spritePath = "assets/img/sprites/animals/Coral Crab/CoralCrab.png", name = "Crab", speed = 20})
    addAnimalGroup(coastalX, coastalY, coastalR * 1.5, {count = 2, distance = 0.6, spritePath = "assets/img/sprites/animals/Meowing Cat/MeowingCat.png", name = "Cat", speed = 35})
    
    -- Mountain animals (north central)
    local mountainX, mountainY, mountainR = WORLD_W * 0.5, WORLD_H * 0.15, 450
    addAnimalGroup(mountainX, mountainY, mountainR, {count = 3, distance = 0.4, spritePath = "assets/img/sprites/animals/Timber Wolf/TimberWolf.png", name = "Wolf", speed = 40})
    addAnimalGroup(mountainX, mountainY, mountainR, {count = 3, distance = 0.5, offset = math.pi / 6, spritePath = "assets/img/sprites/animals/Snow Fox/SnowFox.png", name = "Fox", speed = 35})
    
    -- Desert animals (center-west)
    local desertX, desertY, desertR = WORLD_W * 0.3, WORLD_H * 0.5, 400
    addAnimalGroup(desertX, desertY, desertR, {count = 4, distance = 0.3, spritePath = "assets/img/sprites/animals/Croaking Toad/CroakingToad.png", name = "Toad", speed = 15})
    addAnimalGroup(desertX, desertY, desertR, {count = 2, distance = 0.5, spritePath = "assets/img/sprites/animals/Slow Turtle/SlowTurtle.png", name = "Turtle", speed = 12})
    
    -- Grassland animals (center-northwest)
    local grasslandX, grasslandY, grasslandR = WORLD_W * 0.35, WORLD_H * 0.35, 450
    addAnimalGroup(grasslandX, grasslandY, grasslandR, {count = 5, distance = 0.5, spritePath = "assets/img/sprites/animals/Clucking Chicken/CluckingChicken.png", name = "Chicken", speed = 25})
    addAnimalGroup(grasslandX, grasslandY, grasslandR, {count = 4, distance = 0.4, offset = math.pi / 8, spritePath = "assets/img/sprites/animals/Pasturing Sheep/PasturingSheep.png", name = "Sheep", speed = 22})
    
    -- River animals (center-south)
    local riverX, riverY, riverR = WORLD_W * 0.55, WORLD_H * 0.7, 400
    addAnimalGroup(riverX, riverY, riverR, {count = 4, distance = 0.4, spritePath = "assets/img/sprites/animals/Honking Goose/HonkingGoose.png", name = "Goose", speed = 33})
    addAnimalGroup(riverX, riverY, riverR, {count = 3, distance = 0.5, offset = math.pi / 6, spritePath = "assets/img/sprites/animals/Leaping Frog/LeapingFrog.png", name = "Frog", speed = 30})
    
    -- Tiny chicks (center)
    local chickX, chickY, chickR = WORLD_W * 0.5, WORLD_H * 0.5, 300
    addAnimalGroup(chickX, chickY, chickR, {count = 5, distance = 0.5, spritePath = "assets/img/sprites/animals/Tiny Chick/TinyChick.png", name = "Chick", speed = 18})
    
    return animals
end

return EntitySpawner
