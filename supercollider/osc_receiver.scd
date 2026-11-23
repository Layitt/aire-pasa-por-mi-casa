// ===========================================
// AIRE CDMX - Receptor OSC (4 zonas / arreglo cuadrafónico)
// ===========================================
// Recibe del mapa un promedio de contaminación por zona cardinal (Norte, Sur,
// Este y Oeste) y hace sonar un sintetizador por zona. La asignación de
// estaciones a zonas se hace una sola vez en scripts/convert_data.py a partir
// del catálogo oficial de SEDEMA, así que aquí no hace falta conocer el padrón
// de estaciones (que cambia entre años). Cada zona es una bocina del arreglo
// cuadrafónico.
//
// Requisitos previos:
//   1. Iniciar el puente OSC: cd map && node osc_bridge.js
//   2. Abrir map/index.html en el navegador (http://localhost:3000)
//   3. Ejecutar este archivo (reenvía solo los SynthDefs: ver más abajo)
//
// Formato OSC:
//   /aire [periodo] [contaminante] [norte] [sur] [este] [oeste]
//   El periodo es un día ("2024-05-01"), una semana ("2024-S18") o un año
//   ("2024"); los valores son el promedio del contaminante en cada zona.

(
// Orden fijo de las 4 zonas (coincide con el orden de los valores OSC)
var zoneOrder = [\Norte, \Sur, \Este, \Oeste];

// Frecuencia base para cada zona (armonía espacial de 4 voces)
var zoneFreqs = Dictionary.newFrom([
    \Sur,   110,  // La2 (grave)
    \Oeste, 165,  // Mi3
    \Este,  220,  // La3
    \Norte, 330   // Mi4 (agudo)
]);

// Paneo estéreo para cada zona (-1 izquierda / Oeste, +1 derecha / Este).
// Con tarjeta cuadrafónica se cambia por `out` por zona, ver README.
var zonePans = Dictionary.newFrom([
    \Oeste, -0.8,
    \Norte, -0.25,
    \Sur,    0.25,
    \Este,   0.8
]);

// Mapeo de contaminante a SynthDef
var pollutantSynths = Dictionary.newFrom([
    \CO, \aire_co,
    \NO, \aire_no,
    \NO2, \aire_no2,
    \NOX, \aire_nox,
    \O3, \aire_o3,
    \PM25, \aire_pm25,
    \SO2, \aire_so2
]);

// Escala de amplitud basada en los rangos típicos de cada contaminante
var ampScale = Dictionary.newFrom([
    \CO, 0.15,      // 0-10 ppm
    \NO, 0.005,     // 0-200 ppb
    \NO2, 0.008,    // 0-120 ppb
    \NOX, 0.004,    // 0-250 ppb
    \O3, 0.005,     // 0-200 ppb
    \PM25, 0.006,   // 0-150 μg/m³
    \SO2, 0.02      // 0-50 ppb
]);

// Sintetizadores activos por zona:
// cada entrada guarda (synth: Synth, defName: Symbol)
var activeSynths = Dictionary.new;

// Ruta de synthdefs.scd (junto a este archivo). Se reenvía más abajo.
var synthDefsPath = thisProcess.nowExecutingPath !? { |p| p.dirname +/+ "synthdefs.scd" };

// Función de limpieza con release suave.
// Ojo: Node:isRunning no refleja el estado real de estos nodos (devuelve false
// aunque el synth esté sonando), así que la limpieza no depende de él.
var cleanup = {
    activeSynths.keysValuesDo { |key, item|
        item[\synth].set(\gate, 0);
    };
    activeSynths.clear;
    "Todos los sintetizadores han sido liberados (con release)".postln;
};

// Función para detener todo
var stopAll = {
    cleanup.value;
    "Todos los sintetizadores de AIRE detenidos".postln;
};

// Olvida los synths registrados sin apagarlos. Sirve después de reiniciar el
// servidor de audio: los nodos de antes ya no existen, pero el diccionario
// seguiría apuntándoles y los mensajes sólo actualizarían fantasmas.
// (Se expone como ~aire.resetState y no como .reset porque `reset` es un método
// de Object y taparía la entrada del diccionario.)
var resetState = {
    activeSynths.clear;
    "AIRE: estado vaciado; los synths se recrearán al siguiente mensaje".postln;
};

// Los SynthDefs son la única dependencia dura de este archivo: sin ellos
// `Synth(...)` falla y el mapa manda datos pero no suena nada. Pasa cuando se
// ejecutó sólo este archivo, o cuando synthdefs.scd se ejecutó antes de que el
// servidor de audio acabara de arrancar (`.add` se pierde y no queda rastro
// sonoro). Reenviarlos es idempotente y barato, así que se hace aquí y el orden
// de los archivos deja de importar.
if (Server.default.serverRunning) {
    if (synthDefsPath.notNil and: { File.exists(synthDefsPath) }) {
        synthDefsPath.load;
    } {
        "AIRE: ¡no encuentro synthdefs.scd junto a este archivo!".postln;
    };
} {
    "AIRE: el servidor de audio no está corriendo; arráncalo y vuelve a ejecutar este archivo.".postln;
};

// Manejador OSC
OSCdef(\aireReceiver, { |msg|
    var period = msg[1].asString;
    var pollutant = msg[2].asSymbol;
    var avgs = msg[3..6].collect(_.asFloat);  // Norte, Sur, Este, Oeste

    var synthDefName = pollutantSynths[pollutant];
    var baseAmp = ampScale[pollutant] ? 0.01;
    var status = List.new;

    // El formato es fijo: periodo, contaminante y 4 promedios de zona. Una
    // página vieja manda fecha + hora + 23 estaciones, y sin este aviso el
    // sintoma es sólo "no suena": el contaminante llega como \18.
    if (msg.size != 7) {
        "AIRE: esperaba 6 argumentos (/aire periodo contaminante N S E O) y llegaron %; recarga el mapa (http://localhost:3000/map/)".format(msg.size - 1).postln;
    } {
    if (synthDefName.isNil) {
        "AIRE: contaminante sin instrumento: %".format(pollutant).postln;
    } {
        // Actualizar o crear el sintetizador de cada zona
        zoneOrder.do { |zone, i|
            var avg = avgs[i] ? 0.0;
            var freq = zoneFreqs[zone] ? 200;
            var pan = zonePans[zone] ? 0;
            var amp = (avg * baseAmp).max(0).min(1);
            var existing = activeSynths[zone];
            var syn;

            status.add(avg.round(0.01));

            if (amp > 0.001) {  // Solo reproducir si el promedio de la zona es significativo
                if (existing.notNil and: { existing[\defName] == synthDefName }) {
                    // Mismo instrumento: actualizar en tiempo real, sin clicks ni acumulación
                    existing[\synth].set(\freq, freq, \amp, amp, \pan, pan);
                } {
                    // No había sintetizador activo o cambió el contaminante:
                    // liberar el anterior con release y crear el nuevo
                    if (existing.notNil) {
                        existing[\synth].set(\gate, 0);
                    };
                    // Sin el SynthDef el servidor ignora /s_new sin avisar y el
                    // diccionario acabaría guardando un nodo fantasma: los
                    // mensajes siguientes sólo mandarían .set a algo que no
                    // existe y no volvería a sonar nunca. Por eso sólo se
                    // registra si la definición está cargada.
                    if (SynthDescLib.global.at(synthDefName).notNil) {
                        syn = Synth(synthDefName, [
                            \freq, freq,
                            \amp, amp,
                            \pan, pan,
                            \gate, 1
                        ]);
                        activeSynths[zone] = (synth: syn, defName: synthDefName);
                    } {
                        "AIRE: falta el SynthDef %; ejecuta synthdefs.scd".format(synthDefName).postln;
                    };
                };
            } {
                // Amplitud insignificante: apagar el sintetizador de la zona
                if (existing.notNil) {
                    existing[\synth].set(\gate, 0);
                    activeSynths.removeAt(zone);
                };
            };
        };

        // Mostrar estado en consola con el promedio de cada zona
        "AIRE: % [%] | N: % | S: % | E: % | O: %".format(
            period, pollutant, *status
        ).postln;
    };
    };

}, '/aire');

"¡Receptor OSC de AIRE iniciado (4 zonas: Norte, Sur, Este, Oeste)!" .postln;
"Escuchando en el puerto OSC por defecto (57120)...".postln;
"Contaminantes sonificados: %".format(pollutantSynths.keys.asArray.sort).postln;
"".postln;
"Para detener todos los sintetizadores, ejecuta: ~aire.stopAll".postln;
"Para limpiar, ejecuta: ~aire.cleanup".postln;
"Si reiniciaste el servidor de audio, ejecuta: ~aire.resetState".postln;

// Registrar como variable de entorno para fácil acceso
currentEnvironment.put(\aire, (
    stopAll: stopAll,
    cleanup: cleanup,
    resetState: resetState,
    activeSynths: activeSynths
));
)
