// ===========================================
// AIRE CDMX 2004 - Receptor OSC (4 Zonas)
// ===========================================
// Recibe datos del mapa interactivo vía OSC, agrupa las estaciones
// en 4 zonas geográficas (Norte, Sur, Este y Oeste) y genera sonido
// únicamente con el promedio de contaminación de cada zona.
//
// Requisitos previos:
//   1. Ejecutar primero synthdefs.scd para cargar todos los SynthDefs
//   2. Iniciar el puente OSC: cd map && node osc_bridge.js
//   3. Abrir map/index.html en el navegador (http://localhost:3000)
//   4. Ejecutar este archivo
//
// Formato OSC:
//   /aire [fecha_string] [hora] [contaminante] [val1] [val2] ... [val23]
//   Los valores corresponden a las 23 estaciones de monitoreo en orden:
//   LAG, TAC, FAC, TLA, XAL, MER, PED, CES, PLA, HAN, UIZ, ARA,
//   IMP, BJU, TAX, MIN, TLI, ATI, VIF, SAG, VAL, AZC, SUR

(
// Códigos de estación en orden (coincide con los datos JSON)
var stationCodes = [
    \LAG, \TAC, \FAC, \TLA, \XAL, \MER, \PED, \CES, \PLA, \HAN,
    \UIZ, \ARA, \IMP, \BJU, \TAX, \MIN, \TLI, \ATI, \VIF, \SAG,
    \VAL, \AZC, \SUR
];

// Agrupación de estaciones en 4 zonas geográficas
var zoneStations = Dictionary.newFrom([
    \Norte, [\ATI, \LAG, \TLI, \XAL, \FAC, \VAL],
    \Sur,   [\TLA, \SUR, \PED, \MIN, \BJU, \TAX],
    \Este,  [\HAN, \CES, \UIZ, \ARA, \MER, \IMP, \VIF],
    \Oeste, [\TAC, \AZC, \SAG, \PLA]
]);

// Orden fijo de las 4 zonas
var zoneOrder = [\Norte, \Sur, \Este, \Oeste];

// Frecuencia base para cada zona (armonía espacial de 4 voces)
var zoneFreqs = Dictionary.newFrom([
    \Sur,   110,  // La2 (grave)
    \Oeste, 165,  // Mi3
    \Este,  220,  // La3
    \Norte, 330   // Mi4 (agudo)
]);

// Paneo estéreo para cada zona (-1 izquierda / Oeste, +1 derecha / Este)
var zonePans = Dictionary.newFrom([
    \Oeste, -0.8,
    \Norte, -0.25,
    \Sur,    0.25,
    \Este,   0.8
]);

// Sintetizadores activos - uno por zona (4 en total)
var activeSynths = Dictionary.new;

// Mapeo de contaminante a SynthDef
var pollutantSynths = Dictionary.newFrom([
    \CO, \aire_co,
    \NO, \aire_no,
    \NO2, \aire_no2,
    \NOX, \aire_nox,
    \O3, \aire_o3,
    \PM10, \aire_pm10,
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
    \PM10, 0.003,   // 0-300 μg/m³
    \PM25, 0.006,   // 0-150 μg/m³
    \SO2, 0.02      // 0-50 ppb
]);

// Función de limpieza
var cleanup = {
    activeSynths.valuesDo { |syn|
        if (syn.isRunning) { syn.free };
    };
    activeSynths.clear;
    "Todos los sintetizadores han sido limpiados".postln;
};

// Función para detener todo
var stopAll = {
    cleanup.value;
    "Todos los sintetizadores de AIRE detenidos".postln;
};

// Manejador OSC
OSCdef(\aireReceiver, { |msg|
    var dateStr = msg[1].asString;
    var hour = msg[2].asInteger;
    var pollutant = msg[3].asSymbol;
    var values = msg[4..];  // Arreglo de 23 valores flotantes

    var synthDefName = pollutantSynths[pollutant];
    var baseAmp = ampScale[pollutant] ? 0.01;
    var stationValues = Dictionary.new;
    var zoneAverages = Dictionary.new;

    // Asociar cada código de estación con su valor recibido
    values.asArray.do { |val, i|
        var code = stationCodes[i];
        if (code.notNil) {
            stationValues[code] = val.asFloat;
        };
    };

    // Detener sintetizadores previos
    activeSynths.keysValuesDo { |key, oldSyn|
        if (oldSyn.isRunning) { oldSyn.free };
    };
    activeSynths.clear;

    // Calcular promedio por zona y crear 1 sintetizador por cada zona
    zoneOrder.do { |zone|
        var codes = zoneStations[zone];
        // Filtrar estaciones con medición activa (> 0) para el promedio
        var validVals = codes.collect({ |c| stationValues[c] ? 0.0 }).select({ |v| v > 0 });
        var avg = if (validVals.size > 0) { validVals.sum / validVals.size } { 0.0 };
        var freq = zoneFreqs[zone] ? 200;
        var pan = zonePans[zone] ? 0;
        var amp = (avg * baseAmp).max(0).min(1);
        var synthKey = (pollutant ++ "_" ++ zone).asSymbol;

        zoneAverages[zone] = avg.round(0.01);

        if (amp > 0.001) {  // Solo reproducir si el promedio de la zona es significativo
            var syn = Synth(synthDefName, [
                \freq, freq,
                \amp, amp,
                \pan, pan,
                \gate, 1
            ]);

            activeSynths[synthKey] = syn;
        };
    };

    // Mostrar estado en consola con el promedio de cada zona
    "AIRE: % %h [%] | N: % | S: % | E: % | O: %".format(
        dateStr,
        hour,
        pollutant,
        zoneAverages[\Norte],
        zoneAverages[\Sur],
        zoneAverages[\Este],
        zoneAverages[\Oeste]
    ).postln;

}, '/aire');

"¡Receptor OSC de AIRE iniciado (Modo 4 Zonas: Norte, Sur, Este, Oeste)!".postln;
"Escuchando en el puerto OSC por defecto (57120)...".postln;
"Sintetizadores de contaminantes: %".format(pollutantSynths.keys.asArray.sort).postln;
"".postln;
"Para detener todos los sintetizadores, ejecuta: ~AIRE.stopAll".postln;
"Para limpiar, ejecuta: ~AIRE.cleanup".postln;

// Registrar como variable de entorno para fácil acceso
currentEnvironment.put(\AIRE, (
    stopAll: stopAll,
    cleanup: cleanup,
    activeSynths: activeSynths
));
)
