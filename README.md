# AIRE CDMX 2004 - Sonificación

Sonificación interactiva de los datos de calidad del aire de la Ciudad de México (RAMA 2004).

## Estructura del Proyecto

```
Aire pasa por mi casa/
├── 04RAMA/                    # Datos originales (Excel)
├── data/
│   └── air_quality_2004.json  # Datos convertidos
├── scripts/
│   └── convert_data.py        # Conversor Excel → JSON
├── map/
│   ├── index.html             # Mapa interactivo (Leaflet)
│   ├── osc_bridge.js          # Puente WebSocket → OSC
│   └── package.json           # Dependencias Node.js
└── supercollider/
    ├── synthdefs.scd          # Definiciones de síntesis
    └── osc_receiver.scd       # Receptor OSC
```

## Inicio Rápido

### 1. Preparar Datos (ya ejecutado)

```bash
cd scripts
source ../.venv/bin/activate
python convert_data.py
```

### 2. Iniciar Mapa Interactivo

```bash
cd map

# Terminal 1: Servidor HTTP
python3 -m http.server 3000

# Terminal 2: Puente OSC
node osc_bridge.js
```

Abrir http://localhost:3000 en el navegador.

### 3. Iniciar SuperCollider

1. Abrir SuperCollider
2. Ejecutar `synthdefs.scd` (carga las definiciones de sonido)
3. Ejecutar `osc_receiver.scd` (inicia el receptor OSC)

### 4. Conectar

- El mapa envía datos vía OSC a SuperCollider
- Los valores de contaminantes controlan amplitud y timbre
- Cada estación tiene una frecuencia base diferente

## Controles del Mapa

| Control | Función |
|---------|---------|
| Slider inferior | Navegar por los días del año |
| Slider horario | Navegar por las horas (0-23) |
| Botón Reproducir | Avance automático |
| Botones 1x/2x/4x | Velocidad de reproducción |
| Botones CO/NO/etc | Seleccionar contaminante activo |

## Sonificación

Cada contaminante tiene un instrumento único:

| Contaminante | Sonido | Rango Típico |
|--------------|--------|--------------|
| CO | Drone de bajo profundo | 0-10 ppm |
| NO | Textura de viento | 0-200 ppb |
| NO2 | Raspado metálico | 0-120 ppb |
| NOX | Clusters armónicos | 0-250 ppb |
| O3 | Pads brillantes | 0-200 ppb |
| PM10 | Textura granular | 0-300 μg/m³ |
| PM25 | Partículas finas | 0-150 μg/m³ |
| SO2 | Drone de ronroneo | 0-50 ppb |

## OSC Format

```
/aire [fecha] [hora] [contaminante] [val1] [val2] ... [val23]
```

Las 23 posiciones corresponden a las estaciones RAMA en orden alfabético.

## Estaciones RAMA

| Código | Nombre | Coordenadas |
|--------|--------|-------------|
| LAG | Tlalnepantla | 19.54, -99.24 |
| TAC | Tacuba | 19.46, -99.20 |
| FAC | Ferrería | 19.49, -99.18 |
| TLA | Tláhuac | 19.27, -99.01 |
| XAL | Xalostoc | 19.50, -99.12 |
| MER | Merced | 19.43, -99.12 |
| PED | Pedregal | 19.33, -99.18 |
| CES | Cerro de la Estrella | 19.36, -99.06 |
| PLA | Plateros | 19.38, -99.15 |
| HAN | Hangares | 19.43, -99.08 |
| UIZ | UAM Iztapalapa | 19.36, -99.11 |
| ARA | Aragón | 19.47, -99.12 |
| IMP | Impresora | 19.45, -99.13 |
| BJU | Benito Juárez | 19.38, -99.15 |
| TAX | Taxqueña | 19.40, -99.13 |
| MIN | Minería | 19.33, -99.18 |
| TLI | Tlalnepantla (ALT) | 19.53, -99.23 |
| ATI | Atizapán | 19.57, -99.23 |
| VIF | Villa Francisca | 19.42, -99.13 |
| SAG | San Agustín | 19.40, -99.17 |
| VAL | Vallejo | 19.48, -99.15 |
| AZC | Azcapotzalco | 19.48, -99.18 |
| SUR | Sur | 19.30, -99.15 |

## Para Agregar Más Años

1. Colocar los archivos Excel en una carpeta con el formato `04RAMA`
2. Modificar `convert_data.py` para apuntar a la nueva carpeta
3. Ejecutar el script de conversión
4. Actualizar `dataUrl` en `map/index.html`
