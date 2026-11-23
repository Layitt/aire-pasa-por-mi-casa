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

// Si otro proceso ocupa el puerto 57120, sclang arranca en el siguiente libre
// (57121) y el /aire se pierde sin ningún error visible: el mapa manda datos y
// no suena nada. Avisar de que nadie escucha ahí ahorra esa caza.
function portListening(port) {
    const fs = require('fs');
    try {
        for (const file of ['/proc/net/udp', '/proc/net/udp6']) {
            const rows = fs.readFileSync(file, 'utf8').trim().split('\n').slice(1);
            for (const row of rows) {
                const local = row.trim().split(/\s+/)[1];   // "00000000:DF20"
                if (parseInt(local.split(':').pop(), 16) === port) return true;
            }
        }
        return false;
    } catch (e) {
        return null;  // sin /proc (otro SO): no se puede verificar
    }
}

if (portListening(OSC_PORT) === false) {
    console.warn(`Aviso: nadie escucha en udp:${OSC_PORT}. Abre SuperCollider y ejecuta osc_receiver.scd.`);
}

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

// Arrancar dos puentes es un error fácil de cometer (y sin este mensaje Node
// escupe una traza larga): el segundo no puede escuchar el mismo puerto.
wss.on('error', (error) => {
    if (error.code === 'EADDRINUSE') {
        console.error(`Ya hay un puente escuchando en el puerto ${WS_PORT}.`);
        console.error('Cierra el otro proceso o usa otro puerto: node osc_bridge.js 8081');
    } else {
        console.error('Error del servidor WebSocket:', error);
    }
    process.exit(1);
});

wss.on('connection', (ws) => {
    console.log('Browser connected');
    if (portListening(OSC_PORT) === false) {
        console.warn(`Aviso: nadie escucha en udp:${OSC_PORT}; SuperCollider no está recibiendo.`);
    }

    ws.on('message', (data) => {
        try {
            const message = JSON.parse(data);

            if (message.address && message.args) {
                // Forward to SuperCollider via OSC
                udpPort.send({
                    address: message.address,
                    args: message.args
                });

                const values = message.args.map(a => a.value).join(' ');
                console.log(`OSC -> ${message.address} ${values}`);
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
