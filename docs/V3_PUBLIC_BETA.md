# WAN_SIM 3 Public Beta

`v3.0.0-beta.1` es la primera publicación de la rama V3. Reutiliza el instalador transaccional de V2 y conserva la base SQLite, los snapshots, certificados y secretos existentes.

## Convención De Versiones

- `v3.X.Y-beta.N`: evaluación pública; puede incorporar cambios de interfaz o contratos.
- `v3.X.Y-rc.N`: candidata a estable; sólo recibe correcciones.
- `v3.X.Y-stable`: recomendada para producción.

No se publicarán etiquetas ambiguas como `latest`, `rev1` o ramas instalables. ReactUI y `wansim upgrade` aceptan únicamente etiquetas oficiales.

## Instalación Nueva

```bash
git clone --branch v3.0.0-beta.1 --depth 1 https://github.com/Ryuz-crypto/WAN_SIM.git WAN_SIM-v3
cd WAN_SIM-v3
chmod +x install-v2.sh
sudo ./install-v2.sh install
```

## Actualización Desde V2

```bash
sudo wansim backup
sudo wansim upgrade v3.0.0-beta.1
sudo wansim doctor
```

También puede realizarse desde **Sistema > Actualizaciones** en ReactUI con un usuario `admin`. La tarea crea un respaldo, descarga la etiqueta exacta y aplica el instalador en segundo plano. ReactUI se desconectará brevemente durante el reinicio.

Para regresar a V2 estable:

```bash
sudo wansim rollback-version v2.0.13-stable
```

## Cambios Iniciales

- Eliminación protegida de usuarios y revocación de sus sesiones.
- Inventario de configuraciones, topología activa y reutilización como borrador editable.
- Estado Netem aplicado, parámetros efectivos y ancho de banda actual por interfaz.
- Interfaces administrables con acciones `up`, `down` y `restart`; la ruta administrativa queda protegida.
- Despliegues desplegables y auditoría explicada en lenguaje operativo.
- Actualizaciones oficiales desde ReactUI, créditos y contacto para donaciones.
