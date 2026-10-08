# Fuentes de verdad e integración

| Concepto | Propietario | Frontera |
|---|---|---|
| Motor del Cubo | neos-cube | API local consumida solo por choisys API |
| Producto, auth y persistencia | choisys | API y contratos públicos |
| Contratos del producto | @scenarys/shared, en choisys | Tipos/DTO, sin cálculo |
| Geometría web | neo-cube-web | Datos públicos → representación |
| Landing | scenarys | Contenido expresamente público |
| Coordinación nativa | daemon-core | Snapshot y política, sin motor |
| Base de datos | Neon, desde choisys API | Credenciales solo en servidor |

`pop++` no fue encontrado en el ámbito accesible verificado. No se declara una
dependencia inexistente. Las ramas históricas no demuestran actividad de un agente.

Tailscale es el acceso privado. La landing, las descargas autorizadas y los docs
públicos son otra superficie. El motor nunca se expone directamente por LAN,
Tailscale, Funnel ni Internet. El build nativo no cambia DNS ni reglas de red.

La verificación SQL de Neon se hace con el diagnóstico de choisys. Un snapshot
de Daemon no debe elevar a healthy una base de datos por ver una variable de entorno.
