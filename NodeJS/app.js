const WebSocket = require('ws');
const os = require('os');

function getLocalIPv4Addresses() {
    const interfaces = os.networkInterfaces();
    const addresses = [];

    Object.values(interfaces).forEach((networkInterface) => {
        if (!networkInterface) return;
        networkInterface.forEach((details) => {
            if (details.family === 'IPv4' && !details.internal) {
                addresses.push(details.address);
            }
        });
    });

    return [...new Set(addresses)];
}

const wss = new WebSocket.Server({ port: 8080 }, () => {
    console.log("Signaling server is now listening on port 8080");
    const ipAddresses = getLocalIPv4Addresses();
    if (ipAddresses.length > 0) {
        console.log("Use one of these URLs in Config.swift:");
        ipAddresses.forEach((ip) => {
            console.log(`- ws://${ip}:8080`);
        });
    } else {
        console.log("Could not detect a LAN IP address automatically.");
    }
});

// Broadcast to all.
wss.broadcast = (ws, data) => {
    wss.clients.forEach((client) => {
        if (client !== ws && client.readyState === WebSocket.OPEN) {
            client.send(data);
        }
    });
};

wss.on('connection', (ws) => {
    console.log(`Client connected. Total connected clients: ${wss.clients.size}`)
    
    ws.onmessage = (message) => {
        console.log(message.data + "\n");
        wss.broadcast(ws, message.data);
    }

    ws.onclose = () => {
        console.log(`Client disconnected. Total connected clients: ${wss.clients.size}`)
    }
});