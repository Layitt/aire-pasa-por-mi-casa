# AIRE CDMX - Sonificación (2004-2024)

Sonificación interactiva de los datos históricos de calidad del aire de la Ciudad de México (RAMA 2004-2024).

## Estructura del Proyecto

```
Aire pasa por mi casa/
├── 04RAMA/                    # Datos originales (Excel, 2004-2024)
├── data/
│   ├── years.json             # Años disponibles (selector del mapa)
│   └── air_quality_YYYY.json  # Promedios diarios por estación, un archivo por año
├── scripts/
│   ├── download_rama.py       # Descarga zips de RAMA + catálogo de estaciones
│   ├── cat_estacion.csv       # Catálogo oficial de estaciones (SEDEMA)
│   └── convert_data.py        # Conversor Excel → JSON por año
├── map/
│   ├── index.html             # Mapa interactivo (MapLibre GL, paleta por hora)
│   ├── osc_bridge.js          # Puente WebSocket → OSC
│   └── package.json           # Dependencias Node.js
└── supercollider/
    ├── synthdefs.scd          # Definiciones de síntesis
    └── osc_receiver.scd       # Receptor OSC
```

## Inicio Rápido

### 1. Preparar Datos

```bash
# Descargar bases de RAMA 2004-2024 (una sola vez)
cd scripts
python3 download_rama.py
python3 convert_data.py
```

Requiere `pandas` y `xlrd`. Si no hay un entorno virtual:

```bash
python3 -m venv .venv
.venv/bin/pip install pandas xlrd
```

Cada año se escribe en su propio archivo (`data/air_quality_YYYY.json`) con el
promedio diario por estación, porque el padrón de estaciones cambia mucho entre
años: 25 estaciones en 2011 frente a 35 en 2015. Los 21 archivos juntos pesan
unos 16 MB y el mapa los carga de una vez. Nombres y coordenadas salen del
catálogo oficial de SEDEMA (`scripts/cat_estacion.csv`), no de valores
aproximados.

La base original trae lecturas cada hora; `04RAMA/` las conserva por si hace
falta recalcular con otra granularidad.

### 2. Iniciar Mapa Interactivo

El mapa pide los JSON con rutas relativas (`../data/...`), así que el servidor
va en la raíz del proyecto, no dentro de `map/`:

```bash
# Terminal 1: Servidor HTTP (desde la raíz del proyecto)
python3 -m http.server 3000

# Terminal 2: Puente OSC (la primera vez instala dependencias)
cd map && npm install && node osc_bridge.js
```

Abrir **http://localhost:3000/map/** en el navegador. Sin el puente OSC el mapa
funciona igual; sólo se queda sin audio.

El indicador `OSC` de la consola habla del **puente**, no de SuperCollider: si
sale apagado falta la Terminal 2, aunque SuperCollider ya esté escuchando en el
puerto 57120. El mapa se reconecta solo en unos segundos (sin recargar) y
reenvía su estado cada 3 s, que es lo que mantiene vivos los sintetizadores en
SuperCollider.

### 3. Iniciar SuperCollider

1. Abrir SuperCollider
2. Ejecutar `osc_receiver.scd`

No hace falta ejecutar `synthdefs.scd` aparte: el receptor lo reenvía al
servidor cada vez que arranca (es idempotente). Eso evita el silencio más
común, que es ejecutar el receptor sin SynthDefs cargados —el mapa manda los
datos y SuperCollider los recibe, pero `Synth` no puede crearse y no suena—.
Por eso `synthdefs.scd` tiene que estar junto a `osc_receiver.scd`.

Si el receptor contesta `el servidor de audio no está corriendo`, arranca el
servidor (Ctrl+B / `Server.default.boot`) y vuelve a ejecutarlo.

Si reinicias el servidor de audio, ejecuta `~aire.resetState`: el receptor
guarda sus sintetizadores en memoria y, tras un reinicio, esos nodos ya no
existen (los mensajes sólo actualizarían fantasmas y no sonaría nada).

El receptor además:

- barre al arrancar los nodos `aire_*` que dejó sonando una corrida anterior,
- cierra los suyos si el mapa deja de enviar datos (pestaña cerrada, puente
  caído) durante 10 s, en vez de dejarlos sonando para siempre,
- y al volver a ejecutarlo apaga al receptor anterior, para no quedar con dos
  `OSCdef` sobre `/aire`.

### 4. Conectar

- El mapa envía el promedio del contaminante activo en cada zona cardinal
- Cada zona tiene su frecuencia base y hoy su propio paneo estéreo
- Para parar todo: `~aire.stopAll` en SuperCollider

Si el mapa manda `0 0 0 0` no es un fallo del audio: significa que el periodo
visible no tiene datos del contaminante activo (o que la página cargada no es
la de este proyecto). El receptor, a propósito, no crea sonido con promedios
nulos; el log del puente (`map/osc_bridge.js`) muestra los valores que van
saliendo.

### Si el mapa envía pero no suena

El puente avisa al arrancar (y al conectarse el navegador) si nadie escucha en
el puerto OSC. Ese aviso importa: si otro proceso ocupa el 57120, SuperCollider
arranca en el 57121 y los mensajes se pierden en silencio. En ese caso hay que
cerrar el otro proceso —o arrancar `sclang -u 57130` y el puente con
`node osc_bridge.js 8080 127.0.0.1 57130`—.

Comprobar en SuperCollider que el receptor está vivo: la ventana de post debe
mostrar una línea `AIRE: <periodo> [<contaminante>] | N: … | S: … | E: … | O: …`
cada vez que el mapa cambia. Si no aparece ninguna, el receptor no está
ejecutado o su sclang escucha en otro puerto.

## Controles del Mapa

| Control | Función |
|---------|---------|
| Botón Reproducir | Avance automático, un periodo por tick |
| Botones 1×/2×/4× | Velocidad de reproducción |
| Botones Día/Semana/Año | Granularidad de la línea de tiempo |
| Slider de periodo | Recorre la serie completa (7,671 días, 1,097 semanas o 21 años) |
| Slider de hora | Tiñe el mapa (amanecer, día, atardecer, noche); no cambia los datos |
| Botones CO/NO/etc | Seleccionar contaminante activo |

El mapa no recorre las horas: cada estación tiene un **promedio diario** y la
línea de tiempo agrupa esos días según el paso elegido:

| Paso | Periodos | Ejemplo |
|------|----------|---------|
| Día | 7,671 | `2004-01-01` |
| Semana | 1,097 | `2004-S30` |
| Año | 21 | `2004` |

Una semana es de lunes a domingo, así que cruza los fines de año sin problema.
El valor de cada periodo es la media de los promedios diarios disponibles.

## Sonificación

Cada contaminante tiene un instrumento único. Se sonifican siete: PM2.5 es la
fracción de partículas que se usa para seguir el deterioro del aire, así que
PM10 y PMCO quedan fuera del pipeline.

| Contaminante | Sonido | Rango Típico |
|--------------|--------|--------------|
| CO | Drone de bajo profundo | 0-10 ppm |
| NO | Textura de viento | 0-200 ppb |
| NO2 | Raspado metálico | 0-120 ppb |
| NOX | Clusters armónicos | 0-250 ppb |
| O3 | Pads brillantes | 0-200 ppb |
| PM25 | Partículas finas | 0-150 μg/m³ |
| SO2 | Drone de ronroneo | 0-50 ppb |

## Zonas y salida

Cada estación se asigna a uno de los cuatro puntos cardinales según el eje que
domina respecto al centro de la zona metropolitana (19.4326, -99.1332): si el
desplazamiento vertical es mayor que el horizontal la estación cae en Norte o
Sur, si no, en Este u Oeste. La regla vive en `zone_for()` dentro de
`scripts/convert_data.py`, el resultado se escribe en el campo `zone` de cada
estación del JSON, y el mapa promedia el contaminante activo por zona. Con el
catálogo completo quedan 17 estaciones al Norte, 24 al Sur, 13 al Este y 15 al
Oeste.

El plan es un arreglo cuadrafónico con una bocina por zona. Hoy
`osc_receiver.scd` sigue mezclando las cuatro zonas a estéreo con `\pan`; cuando
haya tarjeta de 4 canales basta con pasar `\out` distinto por zona al crear cada
`Synth`.

## OSC Format

```
/aire [periodo] [contaminante] [norte] [sur] [este] [oeste]
```

El periodo es un día (`2024-05-01`), una semana (`2024-S18`) o un año (`2024`).
Los cuatro valores son el promedio del contaminante en cada zona durante ese
periodo. El cálculo se hace en el mapa, así que el receptor no necesita conocer
el padrón de estaciones de cada año.

## Estaciones RAMA

Los nombres y coordenadas de cada estación salen del catálogo oficial de SEDEMA
(`scripts/cat_estacion.csv`, 70 estaciones con sus coordenadas y la nota de
cuándo terminó la operación de cada una). Cada archivo anual incluye sólo las
estaciones que reportaron ese año:

| Año | Estaciones en el JSON |
|-----|-----------------------|
| 2004 | 32 |
| 2011 | 25 (cierre masivo de estaciones en 2010) |
| 2019 | 34 |
| 2024 | 32 |

## Para Agregar Más Años

1. Ajustar el rango en `scripts/download_rama.py` (`for year in range(...)`)
2. Ejecutar `python3 scripts/download_rama.py` y luego `python3 scripts/convert_data.py`
3. No hay que tocar el mapa: el selector de año se arma desde `data/years.json`

## Qué se versiona

Los JSON de `data/` sí se versionan (el mapa los necesita para correr).
`04RAMA/*.xls` está en `.gitignore`: son 300 MB que se regeneran con
`scripts/download_rama.py`.
