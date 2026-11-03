#!/usr/bin/env node
/**
 * WebSocket to OSC bridge for Aire CDMX
 * Receives WebSocket messages from the browser and forwards them as OSC to SuperCollider.
 *
 * Usage:
 *   node osc_bridge.js [ws_port] [osc_host] [osc_port]
 *
 * Defaults:
 *   ws_port: 8080
 *   osc_host: 127.0.0.1
 *   osc_port: 57120 (SuperCollider default)
 */

const WebSocket = require('ws');
const osc = require('osc');

// Configuration
const WS_PORT = process.argv[2] || 8080;
const OSC_HOST = process.argv[3] || '127.0.0.1';
const OSC_PORT = process.argv[4] || 57120;

console.log(`WebSocket server: ws://localhost:${WS_PORT}`);
console.log(`OSC target: udp://${OSC_HOST}:${OSC_PORT}`);

// Create UDP OSC port for sending to SuperCollider
const udpPort = new osc.UDPPort({
    localAddress: '127.0.0.1',
    localPort: 0,  // Let OS assign port
    remoteAddress: OSC_HOST,
    remotePort: OSC_PORT,
    metadata: true
});

udpPort.on('error', (error) => {
    console.error('OSC error:', error);
});

udpPort.on('ready', () => {
    console.log('OSC UDP port ready');
});

// Create WebSocket server
const wss = new WebSocket.Server({ port: WS_PORT });

wss.on('connection', (ws) => {
    console.log('Browser connected');

    ws.on('message', (data) => {
        try {
            const message = JSON.parse(data);

            if (message.address && message.args) {
                // Forward to SuperCollider via OSC
                udpPort.send({
                    address: message.address,
                    args: message.args
                });

                console.log(`OSC -> ${message.address}`);
            }
        } catch (e) {
            console.error('Error processing message:', e);
        }
    });

    ws.on('close', () => {
        console.log('Browser disconnected');
    });
});

// Open the UDP port
udpPort.open();

console.log(`\nBridge ready! Open map/index.html in your browser.`);
console.log(`SuperCollider should listen on OSC port ${OSC_PORT}`);
