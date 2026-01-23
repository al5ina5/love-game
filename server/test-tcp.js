const net = require('net');

const HOST = process.env.TCP_HOST || 'localhost';
const PORT = process.env.TCP_PORT || 12346;
const ROOM_CODE = process.argv[2];

if (!ROOM_CODE) {
    console.error('Usage: node test-tcp.js <ROOM_CODE>');
    process.exit(1);
}

console.log(`Connecting to ${HOST}:${PORT} for room ${ROOM_CODE}...`);

const client = new net.Socket();

client.connect(PORT, HOST, () => {
    console.log('Connected to server!');
    const joinMsg = `JOIN:${ROOM_CODE}\n`;
    console.log(`Sending: ${joinMsg.trim()}`);
    client.write(joinMsg);
});

client.on('data', (data) => {
    console.log('Received: ' + data.toString().trim());
    // Keep alive or just exit after receiving data?
    // Let's keep alive for 5 seconds then exit
    if (data.toString().includes("join|")) {
        console.log("✅ Join verified!");
    }
});

client.on('close', () => {
    console.log('Connection closed');
});

client.on('error', (err) => {
    console.error('Connection error: ' + err.message);
});

// Close after 5 seconds
setTimeout(() => {
    console.log('Test finished, closing...');
    client.destroy();
    process.exit(0);
}, 5000);
