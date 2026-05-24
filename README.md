# Mundo de Aaron 🧱

Un juego 3D estilo voxel hecho con [Three.js](https://threejs.org) para que Aaron
construya, explore y guarde su propio mundo.

## Características

- 🌍 Mundo 3D de 64×64 generado con ruido fractal (playas, bosques, montañas, nieve)
- 🧱 Romper y colocar bloques (10 tipos)
- 🎨 **Editor de texturas pixel art** dentro del juego (tecla `E`)
- 💬 Consola de comandos al estilo Minecraft Java (tecla `T` o `/`)
- 🤪 Comandos locos: `/explosion`, `/cohete`, `/torre`, `/disco`, `/lluvia`, `/vader`...
- 💾 Guardado automático en `localStorage` + exportación a `.json` para backup
- 🚀 Una sola página HTML, sin build step

## Ejecutar en local

Requiere servidor estático (los `import` ES modules no funcionan con `file://`):

```bash
npx serve .
# o
vercel dev
```

Abre `http://localhost:3000`.

## Controles

| Tecla | Acción |
|---|---|
| `W A S D` | Caminar |
| `← → ↑ ↓` | Girar cámara / mirar |
| `Espacio` | Saltar (o subir en creativo) |
| `Mayús` | Bajar en creativo |
| `Clic` | Romper bloque |
| `Mayús + Clic` | Poner bloque |
| `1-9` | Elegir bloque |
| `T` o `/` | Abrir consola de comandos |
| `E` | Editor de texturas pixel art |

Escribe `/help` dentro del juego para ver todos los comandos.

## Stack

- HTML + CSS + JS vanilla (un solo archivo)
- Three.js 0.160 vía importmap (CDN unpkg)
- localStorage para persistencia

## Licencia

Proyecto personal de Aaron. Three.js es MIT.

Nada relacionado con Mojang/Microsoft — esto es un homenaje hecho desde cero.
