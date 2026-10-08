# Cubo de Neo: prototipo de consola

Abre neo-cube.exe e introduce fila y columna separadas por un espacio (por ejemplo, 2 3). Cada selección válida avanza de fase. Escribe q para terminar antes y consultar la pantalla final.

## Pantalla final

- Total de intentos de entrada y selecciones.
- Entradas vacías y entradas inválidas, contadas por separado.
- Recorrido de coordenadas seleccionadas entre fases.
- NO SELECTION: fase presentada que quedó sin selección al terminar.
- NOT REACHED: fase que no llegó a presentarse.
- Historial ordenado de entradas y resultados, incluido el motivo de salida.

Un intento es una línea enviada durante una fase: selección, entrada vacía, entrada inválida o q. Pulsar Intro sin contenido registra una entrada vacía y mantiene la fase. El cierre del flujo de entrada se registra sin contar como intento. El Intro de cierre de la pantalla final tampoco cuenta. No se infieren motivos psicológicos ni decisiones deliberadas de una entrada vacía o inválida.

Los contadores corresponden a una única ejecución, no al número histórico de partidas. Los datos se conservan en memoria y no se guardan en disco.

## Código y compilación

main.cpp contiene el prototipo. phaseCount, rowCount y columnCount configuran las cantidades; cambiarlas requiere recompilar. Ejecuta build.ps1 desde PowerShell. Utiliza MSYS2 en C:\msys64\mingw64\bin.

La estructura de botones es cube[phase][row][column]. Cada Button conserva selected. Los índices internos empiezan en cero; la consola muestra posiciones desde uno. PhaseRecord guarda los contadores y la selección de cada fase; InputEvent registra los eventos en orden.

Verificado con g++ 16.2 y C++17, sin avisos: recorrido completo, entradas vacías e inválidas, conteos por fase, salida inmediata, fases no alcanzadas y fin del flujo de entrada. No incluye interfaz gráfica, persistencia, probabilidades ni consecuencias narrativas.
