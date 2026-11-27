// ===========================================
// AIRE CDMX 2004-2024 - Definiciones de Síntesis (SynthDefs)
// ===========================================
// Cada contaminante está asignado a un instrumento/carácter sonoro único.
//
// Dos reglas que valen para todos:
//  1. Son MONO y escriben en el bus `out`. El reparto a las bocinas (y el
//     colapso a estéreo cuando no hay 4 canales) lo hace \aire_salida, no cada
//     instrumento: así el mismo instrumento suena igual en cualquier punto
//     cardinal.
//  2. `amp` es siempre 0-1 y cada SynthDef está calibrado para que a amp = 1
//     los siete suenen parejos (~-16 dBFS de RMS). Sin esa calibración los
//     instrumentos más filtrados quedaban 15-20 dB abajo y parecía que no
//     sonaban.
//
// Uso: Seleccionar todo y ejecutar (Ctrl+A, Ctrl+Enter)
// Luego cargar osc_receiver.scd para recibir datos del mapa.

(
// ==================== CO - Monóxido de Carbono ====================
// Drone de bajo profundo - representa la naturaleza invisible y penetrante del CO
SynthDef(\aire_co, {
    |out = 0, freq = 60, amp = 1, gate = 1,
     detune = 0.004, brillo = 0.5, nivel = 1.8|
    var sig, env, sub, cuerpo, aire;
    /* .set sobre amp llega como salto; el lag evita el clic sin retrasar el nivel */
    amp = amp.lag(0.2);

    env = EnvGen.kr(Env.asr(0.1, 1, 0.5), gate, doneAction: 2);

    // Sub-grave: dos senos casi iguales (batido lento) más los armónicos 2 y 3,
    // que son los que se alcanzan a oír en bocinas chicas.
    sub = SinOsc.ar(freq, 0, 1);
    sub = sub + SinOsc.ar(freq * (1 + detune), 0, 0.8);
    sub = sub + SinOsc.ar(freq * 2, 0, 0.45);
    sub = sub + SinOsc.ar(freq * 3, 0, 0.18);

    // Cuerpo: pulso grave con el ancho modulado muy lento (respiración)
    cuerpo = Pulse.ar(freq * 0.5, SinOsc.kr(0.05).range(0.25, 0.55), 0.5);
    cuerpo = LPF.ar(cuerpo, (freq * 6).max(600));

    // Aire: ruido angosto y agudo, da presencia cuando el drone se abre
    aire = BPF.ar(WhiteNoise.ar(0.5), freq * 8, 0.5) * brillo;

    sig = sub + cuerpo + aire;
    sig = (sig * nivel).tanh;           // saturación suave: engorda el grave
    sig = LeakDC.ar(sig) * env * amp;

    Out.ar(out, sig);
}).add;

// ==================== NO - Óxido Nítrico ====================
// Textura de viento con aire - representa su naturaleza reactiva y gaseosa
SynthDef(\aire_no, {
    |out = 0, freq = 400, amp = 1, gate = 1,
     soplo = 0.6, resonancia = 0.35, nivel = 7.3|
    var sig, env, viento, silbido;
    /* .set sobre amp llega como salto; el lag evita el clic sin retrasar el nivel */
    amp = amp.lag(0.2);

    env = EnvGen.kr(Env.asr(0.2, 1, 0.8), gate, doneAction: 2);

    // Dos bandas de ruido que se mueven despacio: el soplo del viento. La
    // segunda, más aguda y estrecha, hace el silbido del aire al pasar.
    viento = BPF.ar(WhiteNoise.ar(1), freq * LFNoise2.kr(0.15).range(0.7, 1.4), resonancia);
    viento = viento + BPF.ar(WhiteNoise.ar(0.7), freq * 2.1 * LFNoise2.kr(0.11).range(0.8, 1.3), resonancia * 1.5);
    viento = viento * SinOsc.kr(0.07).range(0.55, 1.0);

    // Componente tonal que aparece y desaparece (amplitud por ruido lento)
    silbido = SinOsc.ar(freq * 1.5, 0, 0.25) * LFNoise1.kr(0.2).range(0.1, 1);

    sig = viento + (silbido * (1 - soplo));
    sig = LPF.ar(sig, 6000);            // el aire no chilla
    sig = sig * nivel * env * amp;

    Out.ar(out, sig);
}).add;

// ==================== NO2 - Dióxido de Nitrógeno ====================
// Raspado metálico - representa su naturaleza irritante y corrosiva
SynthDef(\aire_no2, {
    |out = 0, freq = 800, amp = 1, gate = 1,
     metal = 0.8, rascado = 0.3, nivel = 0.83|
    var sig, env, parciales, golpes, reso;
    /* .set sobre amp llega como salto; el lag evita el clic sin retrasar el nivel */
    amp = amp.lag(0.2);

    env = EnvGen.kr(Env.asr(0.05, 1, 0.3), gate, doneAction: 2);

    // Parciales inarmónicos (PM) con desafinación lenta: el filo del metal
    parciales = (1..5).collect { |i|
        var f = freq * (i * 0.7 + LFNoise1.kr(0.1 + (i * 0.03)).range(-0.02, 0.02));
        PMOsc.ar(f, f * 1.31, rascado * i * 3, 0, 0.3 / i)
    };
    sig = Mix(parciales);

    // Rascado: impulsos cortos que excitan un banco de resonadores metálicos
    golpes = Dust.ar(LFNoise1.kr(3).range(8, 30));
    reso = Ringz.ar(golpes, freq * [2.4, 3.9, 5.3], 0.04, 0.35).sum;

    sig = (sig * metal) + reso;
    sig = sig * nivel * env * amp;

    Out.ar(out, sig);
}).add;

// ==================== NOX - Óxidos de Nitrógeno ====================
// Clusters armónicos complejos - representa su naturaleza compuesta
SynthDef(\aire_nox, {
    |out = 0, freq = 300, amp = 1, gate = 1,
     disonancia = 0.3, nivel = 0.78|
    var sig, env, cluster;
    /* .set sobre amp llega como salto; el lag evita el clic sin retrasar el nivel */
    amp = amp.lag(0.2);

    env = EnvGen.kr(Env.asr(0.15, 1, 0.6), gate, doneAction: 2);

    // Cluster de siete parciales: cada uno desafina y respira a su propio
    // ritmo, así el acorde nunca queda quieto.
    cluster = (1..7).collect { |i|
        var ratio = [1, 1.06, 1.12, 1.5, 1.67, 2, 2.5].at(i - 1);
        var desvio = LFNoise1.kr(0.15 + (i * 0.05)).range(-1, 1) * disonancia * 0.02;
        var respira = SinOsc.kr(0.05 + (i * 0.013)).range(0.5, 1);
        SinOsc.ar(freq * ratio * (1 + desvio), 0, (0.4 / (i ** 0.6)) * respira)
    };
    sig = Mix(cluster);
    sig = (sig * nivel).tanh;           // el cluster se vuelve filoso al subir
    sig = sig * env * amp;

    Out.ar(out, sig);
}).add;

// ==================== O3 - Ozono ====================
// Pads brillantes y centelleantes - representa la capa protectora a gran altitud
SynthDef(\aire_o3, {
    |out = 0, freq = 600, amp = 1, gate = 1,
     centelleo = 0.8, brillo = 0.6, nivel = 0.78|
    var sig, env, pad, shimmer, destello;
    /* .set sobre amp llega como salto; el lag evita el clic sin retrasar el nivel */
    amp = amp.lag(0.2);

    env = EnvGen.kr(Env.asr(0.3, 1, 1.2), gate, doneAction: 2);

    // Pad: cada armónico es un par de senos desafinados (coro) con fase
    // derivando, que es lo que le da el brillo ancho y nunca idéntico.
    pad = (1..10).collect { |i|
        var harm = freq * i;
        var fase = LFNoise1.kr(0.3).range(0, 2 * pi);
        var peso = (1 / (i ** 1.3)) * brillo;
        SinOsc.ar(harm, fase, peso) + SinOsc.ar(harm * 1.004, fase + 0.5, peso * 0.7)
    };
    sig = Mix(pad);

    // Centelleo: el pad respira, y un destello agudo lo corona de vez en cuando
    shimmer = LFNoise1.kr(0.2).range(0.7, 1.2);
    destello = Ringz.ar(Dust.ar(6), freq * 8, 0.3, 0.05);
    sig = (sig * shimmer * centelleo) + destello;

    sig = sig * nivel * env * amp;

    Out.ar(out, sig);
}).add;

// ==================== PM25 - Material Particulado 2.5μm ====================
// Partículas finas de alta frecuencia - representa micropartículas invisibles
SynthDef(\aire_pm25, {
    |out = 0, freq = 1200, amp = 1, gate = 1,
     finura = 0.8, chispa = 0.5, nivel = 0.61|
    var sig, env, granos, destellos;
    /* .set sobre amp llega como salto; el lag evita el clic sin retrasar el nivel */
    amp = amp.lag(0.2);

    env = EnvGen.kr(Env.asr(0.05, 1, 0.2), gate, doneAction: 2);

    // Nube de granos: Dust dispara y GrainSin vuelca cada partícula con su
    // ventana. (Antes el grano se disparaba con `gate`, que es una constante:
    // sólo sonaba un grano al crear el synth, o sea, prácticamente nada.)
    granos = GrainSin.ar(1,
        Dust.ar(LFNoise1.kr(0.5).range(20, 90)),
        0.04,
        freq * LFNoise1.kr(8).range(0.7, 2.2),
        0, -1, 512, 1
    );

    // Chispas: golpes cortos y agudos, como el polvo que rebrilla
    destellos = Ringz.ar(Dust.ar(60), freq * [4.5, 6.3, 9.1], 0.01, 0.25).sum;

    sig = (granos * finura) + (destellos * chispa);
    sig = HPF.ar(sig, 400);             // "fino": nada de cuerpo grave
    sig = sig * nivel * env * amp;

    Out.ar(out, sig);
}).add;

// ==================== SO2 - Dióxido de Azufre ====================
// Drone de retumbo grave - representa su naturaleza volcánica y ácida
SynthDef(\aire_so2, {
    |out = 0, freq = 50, amp = 1, gate = 1,
     retumbo = 0.7, acidez = 0.3, nivel = 1.5|
    var sig, env, drone, rumbleSig, acido;
    /* .set sobre amp llega como salto; el lag evita el clic sin retrasar el nivel */
    amp = amp.lag(0.2);

    env = EnvGen.kr(Env.asr(0.4, 1, 0.8), gate, doneAction: 2);

    // Drone: fundamental más 3º, 4º y 6º armónico. Los dos últimos son los que
    // quedan audibles cuando el retumbo grave no se reproduce.
    drone = SinOsc.ar(freq, 0, 1);
    drone = drone + SinOsc.ar(freq * 1.5, 0, 0.6);
    drone = drone + SinOsc.ar(freq * 2, 0, 0.5);
    drone = drone + SinOsc.ar(freq * 3, 0, 0.3);

    // Retumbo: un seno grave enorme cuya afinación vaga (tierra moviéndose)
    rumbleSig = SinOsc.ar(LFNoise2.kr(0.3).range(freq * 0.5, freq * 1.6), 0, 0.6);

    // Acidez: ruido café en banda media, el "raspado" del gas
    acido = BPF.ar(BrownNoise.ar(0.8), freq * 6, 0.5) * acidez;

    sig = drone + (rumbleSig * retumbo) + acido;
    sig = LPF.ar(sig, (freq * 8).max(700));
    sig = (sig * nivel).tanh;
    sig = LeakDC.ar(sig) * env * amp;

    Out.ar(out, sig);
}).add;

// ==================== SALIDA - reparto a las bocinas ====================
// Lee las cuatro zonas (un bus mono por zona) y las manda a la tarjeta. Este
// SynthDef es el ÚNICO lugar que sabe en qué salida cae cada punto cardinal:
// cambiar de interfaz o reordenar bocinas no obliga a tocar los instrumentos.
//
// Canales en sentido horario, visto desde el centro del arreglo:
//   1 = Norte   2 = Este   3 = Sur   4 = Oeste
SynthDef(\aire_salida_cuadrafonico, {
    |bNorte = 0, bEste = 2, bSur = 4, bOeste = 6, amp = 1|
    var norte, este, sur, oeste;
    // Se leen las cuatro zonas y se limpia el bus en el mismo bloque: un bus de
    // audio conserva su última muestra, y sin limpiarlo la zona que se apaga
    // dejaría un zumbido fijo en su bocina.
    norte = In.ar(bNorte, 1); ReplaceOut.ar(bNorte, 0);
    este  = In.ar(bEste, 1);  ReplaceOut.ar(bEste, 0);
    sur   = In.ar(bSur, 1);   ReplaceOut.ar(bSur, 0);
    oeste = In.ar(bOeste, 1); ReplaceOut.ar(bOeste, 0);

    Out.ar(0, Limiter.ar([norte, este, sur, oeste] * amp, 0.98, 0.01));
}).add;

// Sin 4 canales de salida no hay cuadrafonía: el anillo se colapsa a un par
// estéreo para poder escuchar (y mezclar) con audífonos o con una interfaz
// estéreo. El reparto es el mismo que usaba la versión anterior a cuadrafonía.
SynthDef(\aire_salida_estereo, {
    |bNorte = 0, bEste = 2, bSur = 4, bOeste = 6, amp = 1,
     pNorte = -0.25, pEste = 0.8, pSur = 0.25, pOeste = -0.8|
    var norte, este, sur, oeste, sig;
    norte = In.ar(bNorte, 1); ReplaceOut.ar(bNorte, 0);
    este  = In.ar(bEste, 1);  ReplaceOut.ar(bEste, 0);
    sur   = In.ar(bSur, 1);   ReplaceOut.ar(bSur, 0);
    oeste = In.ar(bOeste, 1); ReplaceOut.ar(bOeste, 0);

    sig = Pan2.ar(norte, pNorte) + Pan2.ar(este, pEste)
        + Pan2.ar(sur, pSur) + Pan2.ar(oeste, pOeste);

    Out.ar(0, Limiter.ar(sig * amp, 0.98, 0.01));
}).add;

"¡SynthDefs de Aire CDMX cargados!".postln;
"Contaminantes: CO, NO, NO2, NOX, O3, PM25, SO2 (+ salida cuadrafónica)".postln;
)
