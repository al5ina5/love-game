
const net = require('net');

const HOST = 'localhost';
const PORT = 12345; // Base game port? No, relay is 12346. 
// Actually GameServer might be listening on 12345 in LAN mode.
// In Online mode, it's handled by index.ts in the room.

console.log(`Connecting to ${HOST}:${PORT}...`);

const client = new net.Socket();
client.connect(PORT, HOST, () => {
    console.log('Connected!');
    // Request a chunk: chunk|cx|cy
    client.write('chunk|4|4\n');
});

client.on('data', (data) => {
    console.log('Received data:');
    const str = data.toString();
    console.log(str.substring(0, 200) + '...');
    if (str.length > 200) {
        console.log(`(Total length: ${str.length})`);
    }

    if (str.startsWith('chunk|')) {
        const parts = str.split('|');
        const cx = parts[1];
        const cy = parts[2];
        const json = parts.slice(3).join('|');
        try {
            const parsed = JSON.parse(json);
            console.log(`SUCCESS: Parsed chunk ${cx},${cy}`);
            console.log(`  Roads: ${Object.keys(parsed.roads || {}).length}`);
            console.log(`  Water: ${Object.keys(parsed.water || {}).length}`);
            console.log(`  Rocks: ${(parsed.rocks || []).length}`);
            console.log(`  Trees: ${(parsed.trees || []).length}`);
        } catch (e) {
            console.log(`FAILURE: Failed to parse JSON: ${e.message}`);
        }
    }
    client.destroy();
});

client.on('error', (err) => {
    console.log(`Error: ${err.message}`);
});

client.on('close', () => {
    console.log('Connection closed');
});
