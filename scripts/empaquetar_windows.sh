#!/usr/bin/env bash
# Arma una copia del proyecto lista para correr en Windows: mapa, datos, puente
# OSC con sus dependencias y los SynthDefs, más dos .bat para arrancar. No
# compila nada: para el mapa y el puente lo único que hace falta es Node; el
# audio necesita SuperCollider instalado en Windows aparte.
#
# Uso:
#   scripts/empaquetar_windows.sh [/ruta/de/destino]
#
# Por defecto escribe en la partición compartida, que Windows ve como unidad.
set -euo pipefail

ORIGEN="$(cd "$(dirname "$0")/.." && pwd)"
DESTINO="${1:-/mnt/compartido/AireCDMX}"

if [ ! -d "$ORIGEN/data" ] || [ ! -d "$ORIGEN/map" ]; then
    echo "No encuentro data/ y map/ en $ORIGEN" >&2
    exit 1
fi

echo "Origen:  $ORIGEN"
echo "Destino: $DESTINO"

mkdir -p "$DESTINO/data" "$DESTINO/map" "$DESTINO/supercollider"

# Datos, mapa, audio y el servidor estático.
cp "$ORIGEN"/data/*.json "$DESTINO/data/"
cp "$ORIGEN"/map/index.html "$ORIGEN"/map/osc_bridge.js "$ORIGEN"/map/package.json "$DESTINO/map/"
cp "$ORIGEN"/supercollider/*.scd "$DESTINO/supercollider/"
cp "$ORIGEN"/servidor.js "$ORIGEN"/README.md "$DESTINO/"

# Dependencias del puente. `ws` y `osc` son JavaScript puro, así que las mismas
# copian y corren en Windows sin recompilar nada. Se copian con -L porque FAT y
# exFAT (la partición compartida) no admiten enlaces simbólicos y node_modules
# trae unos cuantos en .bin.
if [ ! -d "$DESTINO/map/node_modules/ws" ]; then
    if [ ! -d "$ORIGEN/map/node_modules" ]; then
        ( cd "$ORIGEN/map" && npm install --omit=dev --silent )
    fi
    cp -rL "$ORIGEN/map/node_modules" "$DESTINO/map/"
fi

# Los .bat van con fin de línea de Windows (\r\n); con LF cmd.exe se atraganta.
printf '%s\r\n' \
    '@echo off' \
    'rem Mapa de AIRE CDMX: sirve el proyecto en http://localhost:3000/map/' \
    'cd /d "%~dp0"' \
    'start "AIRE - servidor del mapa" cmd /c node servidor.js' \
    'timeout /t 2 >nul' \
    'start "" http://localhost:3000/map/' \
    > "$DESTINO/INICIAR-MAPA.bat"

printf '%s\r\n' \
    '@echo off' \
    'rem Puente WebSocket -> OSC hacia SuperCollider (puerto 57120)' \
    'cd /d "%~dp0map"' \
    'node osc_bridge.js' \
    'pause' \
    > "$DESTINO/INICIAR-PUENTE.bat"

cat > "$DESTINO/LEEME.txt" <<'LEEME'
AIRE CDMX - sonificación 2004-2024
==================================

Qué es esto
-----------
El mapa interactivo de calidad del aire y su puente de audio. El mapa corre en
el navegador; el puente manda los datos a SuperCollider, que hace sonar una
bocina por punto cardinal (Norte, Este, Sur, Oeste).

Lo único que hace falta en Windows
---------------------------------
Node.js ( https://nodejs.org ) para el mapa y el puente.
SuperCollider ( https://supercollider.github.io ) sólo si quieres oír el audio.

Arrancar
--------
1. Doble clic en INICIAR-MAPA.bat
   Abre http://localhost:3000/map/ en el navegador. El mapa ya funciona: los
   botones, la línea de tiempo y los contaminantes, sin audio.

2. Para oírlo, además:
   a. Doble clic en INICIAR-PUENTE.bat (deja esa ventana abierta).
   b. Abrir SuperCollider y arrancar el servidor con cuatro salidas:
         s.options.numOutputBusChannels = 4;
         s.reboot;
   c. Ejecutar supercollider\osc_receiver.scd (Ctrl+Enter).
      Carga los SynthDefs solo; no hay que ejecutar synthdefs.scd aparte.

Con dos canales de salida también suena: las cuatro zonas se mezclan en estéreo,
pero entonces no es cuadrafonía.

Los canales de la salida cuadrafónica, en sentido horario desde el norte:
   1 = Norte    2 = Este    3 = Sur    4 = Oeste

Dentro de SuperCollider:
   ~aire.stopAll     apagar todo
   ~aire.volumen(0.6)   volumen general
   ~aire.resetState  después de reiniciar el servidor de audio

Si no suena
-----------
- El indicador "OSC" del mapa habla del puente: si está apagado, falta
  INICIAR-PUENTE.bat.
- Si el puente avisa que nadie escucha en udp:57120, SuperCollider no está
  recibiendo (revisa que osc_receiver.scd siga ejecutado).
LEEME

echo
echo "Listo. En Windows abre la carpeta y ejecuta INICIAR-MAPA.bat"
du -sh "$DESTINO"
