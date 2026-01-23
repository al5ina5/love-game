
const { GameServer } = require('./server/dist/game_server');
const { ChunkManager } = require('./server/dist/world/ChunkManager');
const { WorldGenerator } = require('./server/dist/world/WorldGenerator');

console.log('Testing GameServer World Generation...');

try {
    const gs = new GameServer();
    console.log('GameServer initialized.');

    const chunk = gs.getChunkData(4, 4);
    if (chunk) {
        console.log('SUCCESS: Generated chunk 4,4');
        console.log(`  Roads: ${Object.keys(chunk.roads || {}).length}`);
        console.log(`  Water: ${Object.keys(chunk.water || {}).length}`);
        console.log(`  Rocks: ${(chunk.rocks || []).length}`);
        console.log(`  Trees: ${(chunk.trees || []).length}`);

        // Check if data is actually there
        if (Object.keys(chunk.roads).length > 0) {
            console.log('  Road data sample:', Object.entries(chunk.roads).slice(0, 3));
        } else {
            console.log('  WARNING: Roads are empty in this chunk.');
        }
    } else {
        console.log('FAILURE: Chunk 4,4 is null');
    }
} catch (e) {
    console.log(`ERROR: ${e.message}`);
    console.log(e.stack);
}
