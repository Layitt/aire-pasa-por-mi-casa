// ===========================================
// AIRE CDMX 2004 - Definiciones de Síntesis (SynthDefs)
// ===========================================
// Cada contaminante está asignado a un instrumento/carácter sonoro único.
// Los valores del mapa controlan la amplitud, frecuencia y timbre.
//
// Uso: Seleccionar todo y ejecutar (Ctrl+A, Ctrl+Enter)
// Luego cargar osc_receiver.scd para recibir datos del mapa.

(
// ==================== CO - Monóxido de Carbono ====================
// Drone de bajo profundo - representa la naturaleza invisible y penetrante del CO
SynthDef(\aire_co, {
    |out = 0, freq = 60, amp = 0.5, gate = 1, pan = 0, detune = 0.5|
    var sig, env, sub, filtered;
    /* .set sobre amp llega como salto; el lag evita el clic sin retrasar el nivel */
    amp = amp.lag(0.2);

    env = EnvGen.kr(Env.asr(0.1, 1, 0.5), gate, doneAction: 2);

    // Sub-bajo con ligera desafinación para darle cuerpo
    sub = SinOsc.ar(freq, 0, 0.4);
    sub = sub + SinOsc.ar(freq * 1.003, 0, 0.3);  // Ligera desafinación

    // Agregar contenido armónico
    filtered = LPF.ar(
        Pulse.ar(freq * 0.5, 0.3, 0.2),
        freq * 4
    );

    sig = (sub + filtered) * env * amp;
    sig = Splay.ar(sig!2, 0.3, 1, pan);
    sig = LeakDC.ar(sig);

    Out.ar(out, sig);
}).add;

// ==================== NO - Óxido Nítrico ====================
// Textura de viento con aire - representa su naturaleza reactiva y gaseosa
SynthDef(\aire_no, {
    |out = 0, freq = 400, amp = 0.3, gate = 1, pan = 0,
     breathiness = 0.5, resonance = 0.3|
    var sig, env, noise, filtered, modulated;
    /* .set sobre amp llega como salto; el lag evita el clic sin retrasar el nivel */
    amp = amp.lag(0.2);

    env = EnvGen.kr(Env.asr(0.2, 1, 0.8), gate, doneAction: 2);

    // Ruido filtrado para dar cualidad de soplo/aire
    noise = WhiteNoise.ar(0.3);
    filtered = BPF.ar(noise, freq, resonance);

    // Modular con un LFO lento para darle movimiento
    modulated = filtered * SinOsc.kr(0.3).range(0.5, 1.0);

    // Agregar componente tonal
    sig = SinOsc.ar(freq, 0, breathiness);
    sig = sig + modulated;

    sig = sig * env * amp;
    sig = Pan2.ar(sig, pan);
    sig = FreeVerb.ar(sig, 0.3, 0.5, 0.3);

    Out.ar(out, sig);
}).add;

// ==================== NO2 - Dióxido de Nitrógeno ====================
// Raspado metálico - representa su naturaleza irritante y corrosiva
SynthDef(\aire_no2, {
    |out = 0, freq = 800, amp = 0.2, gate = 1, pan = 0,
     metallic = 0.7, scrape = 0.3|
    var sig, env, mod, partials;
    /* .set sobre amp llega como salto; el lag evita el clic sin retrasar el nivel */
    amp = amp.lag(0.2);

    env = EnvGen.kr(Env.asr(0.05, 1, 0.3), gate, doneAction: 2);

    // Parciales inarmónicos para sonido metálico
    partials = (1..5).collect { |i|
        var partialFreq = freq * (i * 0.7 + TRand.kr(0, 0.1, gate));
        PMOsc.ar(partialFreq, partialFreq * 1.1, scrape * i, 0, 0.1 / i)
    };

    mod = Mix.new(partials);

    // Agregar textura granular
    sig = mod + Dust.ar(20) * LPF.ar(WhiteNoise.ar(0.1), freq * 2);

    sig = sig * env * amp * metallic;
    sig = Pan2.ar(sig, pan);
    sig = AllpassL.ar(sig, 0.1, TRand.kr(0.01, 0.05, gate), 0.3);

    Out.ar(out, sig);
}).add;

// ==================== NOX - Óxidos de Nitrógeno ====================
// Clusters armónicos complejos - representa su naturaleza compuesta
SynthDef(\aire_nox, {
    |out = 0, freq = 300, amp = 0.25, gate = 1, pan = 0,
     clusters = 0.6, dissonance = 0.3|
    var sig, env, cluster;
    /* .set sobre amp llega como salto; el lag evita el clic sin retrasar el nivel */
    amp = amp.lag(0.2);

    env = EnvGen.kr(Env.asr(0.15, 1, 0.6), gate, doneAction: 2);

    // Construir cluster armónico con ligera disonancia
    cluster = (1..7).collect { |i|
        var ratio = [1, 1.06, 1.12, 1.5, 1.67, 2, 2.5].at(i - 1) ? 1;
        var det = LFNoise1.kr(0.5).range(-0.01, 0.01);
        SinOsc.ar(freq * ratio * (1 + det), 0, 0.15 / i)
    };

    sig = Mix.new(cluster);

    // Agregar modulación pulsante
    sig = sig * (1 + SinOsc.kr(0.8).range(-0.2, 0.2));

    sig = sig * env * amp * clusters;
    sig = Splay.ar(sig!2, 0.4, 1, pan);

    Out.ar(out, sig);
}).add;

// ==================== O3 - Ozono ====================
// Pads brillantes y centelleantes - representa la capa protectora a gran altitud
SynthDef(\aire_o3, {
    |out = 0, freq = 600, amp = 0.2, gate = 1, pan = 0,
     shimmer = 0.8, brightness = 0.5|
    var sig, env, pad, shimmerLFO;
    /* .set sobre amp llega como salto; el lag evita el clic sin retrasar el nivel */
    amp = amp.lag(0.2);

    env = EnvGen.kr(Env.asr(0.3, 1, 1.2), gate, doneAction: 2);

    // Sonido de pad rico con muchos armónicos
    pad = (1..12).collect { |i|
        var harmFreq = freq * i;
        var ampScale = 1 / (i * 0.8);
        var phase = LFNoise1.kr(0.3).range(0, 2 * pi);
        SinOsc.ar(harmFreq, phase, ampScale * brightness)
    };

    sig = Mix.new(pad);

    // Efecto centelleante (shimmer)
    shimmerLFO = LFNoise1.kr(0.2).range(0.8, 1.2);
    sig = sig * shimmerLFO;

    sig = sig * env * amp * shimmer;
    sig = FreeVerb.ar(sig, 0.4, 0.6, 0.5);
    sig = Splay.ar(sig!2, 0.5, 1, pan);

    Out.ar(out, sig);
}).add;

// ==================== PM25 - Material Particulado 2.5μm ====================
// Partículas finas de alta frecuencia - representa micropartículas invisibles
SynthDef(\aire_pm25, {
    |out = 0, freq = 1200, amp = 0.15, gate = 1, pan = 0,
     fineness = 0.9, sparkle = 0.4|
    var sig, env, fine, sparkleSig;
    /* .set sobre amp llega como salto; el lag evita el clic sin retrasar el nivel */
    amp = amp.lag(0.2);

    env = EnvGen.kr(Env.asr(0.05, 1, 0.2), gate, doneAction: 2);

    // Granos muy finos de alta frecuencia
    fine = GrainIn.ar(2, gate, 0.02,
        LFNoise1.ar(50).range(freq, freq * 3),
        LFNoise1.kr(5).range(-0.5, 0.5)
    );

    // Efecto de destello
    sparkleSig = Dust.ar(100) * BPF.ar(WhiteNoise.ar(0.05), freq, 0.1);

    sig = (fine * fineness) + (sparkleSig * sparkle);

    sig = sig * env * amp;
    sig = Pan2.ar(sig, pan);
    sig = HPF.ar(sig, 800);

    Out.ar(out, sig);
}).add;

// ==================== SO2 - Dióxido de Azufre ====================
// Drone de retumbo grave - representa su naturaleza volcánica y ácida
SynthDef(\aire_so2, {
    |out = 0, freq = 50, amp = 0.35, gate = 1, pan = 0,
     rumble = 0.7, acidity = 0.3|
    var sig, env, drone, rumbleSig;
    /* .set sobre amp llega como salto; el lag evita el clic sin retrasar el nivel */
    amp = amp.lag(0.2);

    env = EnvGen.kr(Env.asr(0.4, 1, 0.8), gate, doneAction: 2);

    // Drone de muy baja frecuencia
    drone = SinOsc.ar(freq, 0, 0.3);
    drone = drone + SinOsc.ar(freq * 1.5, 0, 0.2);
    drone = drone + SinOsc.ar(freq * 2, 0, 0.1);

    // Retumbo sub-bajo
    rumbleSig = LFNoise1.kr(0.5).range(freq * 0.5, freq * 1.5);
    rumbleSig = SinOsc.ar(rumbleSig, 0, 0.2);

    // Agregar algo de ruido para textura
    sig = drone + (rumbleSig * rumble);
    sig = sig + (BrownNoise.ar(0.05) * acidity);

    sig = sig * env * amp;
    sig = Splay.ar(sig!2, 0.2, 1, pan);
    sig = LPF.ar(sig, 200);

    Out.ar(out, sig);
}).add;

"¡SynthDefs de Aire CDMX cargados!".postln;
"Contaminantes: CO, NO, NO2, NOX, O3, PM25, SO2".postln;
)
