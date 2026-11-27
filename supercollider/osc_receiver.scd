// ===========================================
// AIRE CDMX - Receptor OSC (cuadrafonía: una bocina por punto cardinal)
// ===========================================
// Recibe del mapa un promedio de contaminación por zona cardinal (Norte, Sur,
// Este y Oeste) y hace sonar un sintetizador por zona. La asignación de
// estaciones a zonas se hace una sola vez en scripts/convert_data.py a partir
// del catálogo oficial de SEDEMA, así que aquí no hace falta conocer el padrón
// de estaciones (que cambia entre años).
//
// Salida: cada zona suena en su propia bocina (Norte, Este, Sur, Oeste en
// sentido horario), así que hace falta que el servidor de audio tenga 4 canales
// de salida. Si sólo tiene 2, el reparto se colapsa a estéreo para poder
// escuchar igual. Ver "Salida" más abajo.
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

// Rango típico de cada contaminante (el mismo de la tabla del README). Es la
// única conversión de dato a sonido: el promedio de la zona se divide entre su
// rango, así que 0 es silencio y el máximo típico es amplitud 1. Cada
// instrumento ya está calibrado a esa misma escala (ver synthdefs.scd), así que
// los siete suenan parejo y no hace falta una escala por contaminante.
var pollutantRanges = Dictionary.newFrom([
    \CO, 10,      // 0-10 ppm
    \NO, 200,     // 0-200 ppb
    \NO2, 120,    // 0-120 ppb
    \NOX, 250,    // 0-250 ppb
    \O3, 200,     // 0-200 ppb
    \PM25, 150,   // 0-150 μg/m³
    \SO2, 50      // 0-50 ppb
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

// Volumen general del arreglo (se cambia con ~aire.volumen(0.6)). Los
// instrumentos ya vienen parejos entre sí, así que este es el único nivel
// global.
var masterGain = 1.0;

// Sintetizadores activos por zona:
// cada entrada guarda (synth: Synth, defName: Symbol)
var activeSynths = Dictionary.new;

// Un bus de audio mono por zona. Los instrumentos escriben ahí y \aire_salida
// es quien reparte a las bocinas; así el mismo instrumento sirve para
// cuadrafonía y para estéreo.
var zoneBuses;

// El nodo que hace el reparto (ver crearSalida)
var salida;

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

// Vuelve a leer cuántas salidas tiene el servidor y recrea el reparto. Hace
// falta después de cambiar numOutputBusChannels y reiniciar el servidor.
var crearSalida = {
    var cuadrafonico = Server.default.options.numOutputBusChannels >= 4;
    var defName = if (cuadrafonico) { \aire_salida_cuadrafonico } { \aire_salida_estereo };
    if (salida.notNil) { salida.free };
    salida = nil;
    if (zoneBuses.notNil and: { Server.default.serverRunning }) {
        if (SynthDescLib.global.at(defName).notNil) {
            salida = Synth(defName, [
                \bNorte, zoneBuses[\Norte].index,
                \bEste,  zoneBuses[\Este].index,
                \bSur,   zoneBuses[\Sur].index,
                \bOeste, zoneBuses[\Oeste].index,
                \amp, masterGain
            ]);
        } {
            "AIRE: falta el SynthDef %; ejecuta synthdefs.scd".format(defName).postln;
        };
    };
    salida
};

// Volumen general: afecta a las cuatro bocinas por igual. Recibe el entorno
// como primer argumento (así funcionan las funciones guardadas en ~aire), por
// eso busca el número entre sus argumentos.
var setVolumen = { arg ...args;
    var v = args.detect { |a| a.isNumber } ? 1.0;
    masterGain = v;
    if (salida.notNil) { salida.set(\amp, v) };
    "AIRE: volumen general %".format(v).postln;
};

// Olvida los synths registrados sin apagarlos. Sirve después de reiniciar el
// servidor de audio: los nodos de antes ya no existen, pero el diccionario
// seguiría apuntándoles y los mensajes sólo actualizarían fantasmas. También
// vuelve a crear el reparto, que el reinicio se llevó.
// (Se expone como ~aire.resetState y no como .reset porque `reset` es un método
// de Object y taparía la entrada del diccionario.)
var resetState = {
    activeSynths.clear;
    crearSalida.value;
    "AIRE: estado vaciado; los synths se recrearán al siguiente mensaje".postln;
};

// Cierra los nodos `aire_*` que quedaron sonando de una ejecución anterior (por
// ejemplo si sclang murió de golpe sin pasar por stopAll). El árbol se recorre
// como una lista deslizante: [nodeID, -1, defName] es un synth y
// [nodeID, numChildren] un grupo, así que basta buscar ese patrón.
var closeLeftovers = {
    var reply;
    reply = OSCFunc({ |msg|
        var i = 1;
        reply.free;
        while { i < msg.size } {
            var defName = msg[i + 2];
            if (msg[i + 1] == -1
                and: { defName.isKindOf(Symbol) or: { defName.isKindOf(String) } }
                and: { defName.asString.beginsWith("aire_") }) {
                // Los instrumentos se apagan con release; el reparto no tiene
                // gate y hay que liberarlo, si no quedaría un segundo nodo
                // leyendo los mismos buses.
                if (defName.asString.beginsWith("aire_salida")) {
                    Server.default.sendMsg(\n_free, msg[i]);
                } {
                    Server.default.sendMsg(\n_set, msg[i], \gate, 0);
                };
            };
            i = i + 1;
        };
    }, '/g_queryTree.reply');
    Server.default.sendMsg(\g_queryTree, 0, 0);
};

// Si el mapa deja de mandar datos (pausa definitiva, pestaña cerrada, puente
// caído) los synths se cierran solos en vez de quedarse sonando indefinidamente.
// El mapa reenvía el estado cada pocos segundos justamente para esto.
var lastMsgTime = Main.elapsedTime;
var idleTimeout = 10;
var watchdog = Routine({
    loop {
        1.0.wait;
        if (activeSynths.notEmpty and: { Main.elapsedTime - lastMsgTime > idleTimeout }) {
            cleanup.value;
            "AIRE: % s sin datos del mapa, sintetizadores cerrados".format(idleTimeout).postln;
        };
    };
}).play(AppClock);

// Apaga este receptor; se ejecuta al volver a correr el archivo para cerrar los
// nodos, el reparto, sus buses y el vigilante de la instancia anterior.
var shutdown = {
    watchdog.stop;
    cleanup.value;
    if (salida.notNil) { salida.free };
    salida = nil;
    if (zoneBuses.notNil) { zoneBuses.do { |bus| bus.free } };
    zoneBuses = nil;
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

// Si esta sclang ya tenía un receptor de una corrida anterior, cerrarlo: si no,
// quedan dos OSCdef sobre /aire y los nodos de los dos.
if (~aire.notNil and: { ~aire[\shutdown].notNil }) {
    ~aire[\shutdown].value;
};

// Salida: las bocinas. Se pregunta al servidor cuántos canales tiene de verdad.
// Los SynthDefs viajan en paquetes grandes, que SuperCollider agenda con
// latencia: por eso el reparto se crea en una Routine que primero espera al
// servidor (`sync`). Sin esa espera el /s_new llega antes que el /d_recv y el
// servidor contesta "SynthDef not found", dejando el arreglo sin canal.
if (Server.default.serverRunning) {
    closeLeftovers.value;
    Routine {
        Server.default.sync;
        // Cuatro buses nuevos por corrida; los de la anterior ya se liberaron.
        zoneBuses = Dictionary.newFrom(
            zoneOrder.collect { |zone| [zone, Bus.audio(Server.default, 1)] }.flatten
        );
        crearSalida.value;
        if (Server.default.options.numOutputBusChannels >= 4) {
            "AIRE: salida cuadrafónica: Norte=1, Este=2, Sur=3, Oeste=4".postln;
        } {
            "AIRE: el servidor tiene % canales de salida, así que las cuatro zonas se\n"
            "  mezclan en estéreo. Para el arreglo de cuatro bocinas:\n"
            "      s.options.numOutputBusChannels = 4; s.reboot;\n"
            "  y vuelve a ejecutar este archivo.".format(
                Server.default.options.numOutputBusChannels).postln;
        };
    }.play(AppClock);
};

// Manejador OSC
OSCdef(\aireReceiver, { |msg|
    var period = msg[1].asString;
    var pollutant = msg[2].asSymbol;
    var avgs = msg[3..6].collect(_.asFloat);  // Norte, Sur, Este, Oeste

    var synthDefName = pollutantSynths[pollutant];
    var rango = pollutantRanges[pollutant];
    var status = List.new;
    var aviso;

    lastMsgTime = Main.elapsedTime;

    // Los tres motivos por los que un mensaje no puede sonar, con su arreglo a
    // mano. El formato es fijo: periodo, contaminante y 4 promedios de zona;
    // una página vieja manda fecha + hora + 23 estaciones y sin este aviso el
    // síntoma es sólo "no suena" (el contaminante llega como \18).
    if (msg.size != 7) {
        aviso = "AIRE: esperaba 6 argumentos (/aire periodo contaminante N S E O) y llegaron %; recarga el mapa (http://localhost:3000/map/)".format(msg.size - 1);
    };
    if (aviso.isNil and: { synthDefName.isNil }) {
        aviso = "AIRE: contaminante sin instrumento: %".format(pollutant);
    };
    if (aviso.isNil and: { zoneBuses.isNil }) {
        aviso = "AIRE: no hay buses de audio; ejecuta este archivo con el servidor de audio corriendo";
    };

    if (aviso.notNil) {
        aviso.postln;
    } {
        // Actualizar o crear el sintetizador de cada zona
        zoneOrder.do { |zone, i|
            var avg = avgs[i] ? 0.0;
            var freq = zoneFreqs[zone] ? 200;
            var amp = (avg / (rango ? 100)).clip(0, 1);
            var existing = activeSynths[zone];
            var syn;

            status.add(avg.round(0.01));

            if (amp > 0.001) {  // Solo reproducir si el promedio de la zona es significativo
                if (existing.notNil and: { existing[\defName] == synthDefName }) {
                    // Mismo instrumento: actualizar en tiempo real, sin clicks ni acumulación
                    existing[\synth].set(\freq, freq, \amp, amp);
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
                            \out, zoneBuses[zone].index,   // su bocina
                            \freq, freq,
                            \amp, amp,
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

}, '/aire');

"¡Receptor OSC de AIRE iniciado (4 zonas: Norte, Sur, Este, Oeste)!" .postln;
"Escuchando en el puerto OSC por defecto (57120)...".postln;
"Contaminantes sonificados: %".format(pollutantSynths.keys.asArray.sort).postln;
"".postln;
"Para detener todos los sintetizadores, ejecuta: ~aire.stopAll".postln;
"Para limpiar, ejecuta: ~aire.cleanup".postln;
"Para cambiar el volumen general: ~aire.volumen(0.6)".postln;
"Si reiniciaste el servidor de audio, ejecuta: ~aire.resetState".postln;

// Registrar como variable de entorno para fácil acceso
currentEnvironment.put(\aire, (
    stopAll: stopAll,
    cleanup: cleanup,
    resetState: resetState,
    volumen: setVolumen,
    shutdown: shutdown,
    activeSynths: activeSynths
));
)
