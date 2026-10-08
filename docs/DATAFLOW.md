# Flujo de observación

```text
Ruta de repo seleccionada
  → Policy: permitir únicamente observación prevista
  → executable + argv (sin shell)
  → resultado acotado y con plazo
  → RepositoryState
  → Snapshot
  → CLI / puente C / SwiftUI
```

Los fallos y timeouts son resultados, no repos limpios ni servicios sanos.
Los datos locales del snapshot son privados: no se envían a la landing.
Los eventos registran operación y resultado, no tokens, credenciales ni
contenido íntegro de la salida de herramientas.

iOS no ejecuta Git, gh ni procesos locales generales. Importar un snapshot no
significa observar el Mac en directo. El control remoto requiere otra frontera
autenticada todavía no implementada.
