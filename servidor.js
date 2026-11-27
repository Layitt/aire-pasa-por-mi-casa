#!/usr/bin/env node
/**
 * Servidor estático mínimo para el mapa, sin dependencias (sólo Node).
 *
 * El mapa pide los JSON con rutas relativas (`../data/...`), así que hay que
 * servirlo desde la raíz del proyecto. `python3 -m http.server 3000` hace lo
 * mismo; este archivo existe para Windows, donde no siempre hay Python.
 *
 * Uso:
 *   node servidor.js [puerto]   →   http://localhost:3000/map/
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = __dirname;
const PORT = Number(process.argv[2]) || 3000;

const TIPOS = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.png': 'image/png',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon',
};

http.createServer((req, res) => {
    const rel = decodeURIComponent(req.url.split('?')[0]);
    let file = path.join(ROOT, rel);
    if (!file.startsWith(ROOT)) {          // no servir fuera del proyecto
        res.writeHead(403).end('fuera del proyecto');
        return;
    }
    if (fs.existsSync(file) && fs.statSync(file).isDirectory()) {
        file = path.join(file, 'index.html');
    }
    fs.readFile(file, (err, data) => {
        if (err) {
            res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('no está: ' + rel);
            return;
        }
        res.writeHead(200, { 'Content-Type': TIPOS[path.extname(file).toLowerCase()] || 'application/octet-stream' });
        res.end(data);
    });
}).listen(PORT, () => {
    console.log(`Mapa en http://localhost:${PORT}/map/`);
});
