# Operación De WAN_SIM 2

Esta guía aplica a `v2.0.12-stable`. La versión `v1.119-stable` se conserva como estable anterior para el dashboard clásico.

## Estado Y Diagnóstico

```bash
sudo wansim status
sudo wansim doctor
sudo wansim doctor --export /var/tmp/wansim-doctor.txt
sudo wansim logs
sudo wansim logs agent
sudo wansim logs control
```

`doctor` comprueba plataforma, comandos, Docker Compose, servicios habilitados/activos, permisos del socket y configuración, contenedores, API HTTP/HTTPS, vigencia TLS, integridad SQLite, bots Telegram habilitados y espacio libre. El reporte no imprime tokens ni claves.

## Servicios

```bash
sudo wansim start
sudo wansim stop
sudo wansim restart
```

Los servicios administrados son `wansim-agent.service` y `wansim-control-plane.service`. Docker se mantiene como dependencia compartida y no se elimina al desinstalar WAN_SIM.

## Respaldo Y Restauración

```bash
sudo wansim backup
sudo wansim backup /root/backups/wansim-lab.tar.gz
sudo wansim restore /root/backups/wansim-lab.tar.gz
```

El respaldo detiene brevemente el plano de control para mantener consistente SQLite, incluye `/etc/wansim` y `/var/lib/wansim`, usa permisos `0600` y genera un archivo `.sha256`. Antes de restaurar se valida checksum y contenido, y se crea un respaldo de seguridad del estado actual.

## Actualización Y Reparación

```bash
sudo wansim upgrade v2.0.12-stable
sudo wansim rollback-version
sudo wansim repair
```

`update` sólo descarga una etiqueta V2 permitida, comprueba que el checkout coincide exactamente, respalda y ejecuta el instalador transaccional. `repair` reinstala los componentes de la versión local conservando configuración, secretos, certificados y datos.

## Recuperación, Doctor Y Soporte

ReactUI muestra snapshots transaccionales y respaldos completos del host con fecha, versión, topología, checksum e integridad. Sólo un `admin` puede restaurarlos o volver al último estado funcional. Cada restauración queda registrada en auditoría.

Doctor reúne agente, interfaces, servicios, SQLite, espacio, Telegram y TLS. El reporte puede descargarse desde ReactUI o generarse sin secretos desde consola:

```bash
sudo wansim doctor --export /var/tmp/wansim-doctor.txt
sudo wansim support-bundle
```

## Usuarios Y Roles

La clave API de instalación continúa disponible para transición. Úsala para crear el primer administrador en **Acceso** y opera después con sesiones personales. `viewer` consulta, `operator` aplica topologías y `admin` recupera, reinicia y administra usuarios. Cambios, restauraciones, reinicios y rotaciones quedan auditados.

## Modo De Red

```bash
sudo wansim enable-host-apply --confirm
sudo wansim disable-host-apply
```

`dry-run` es el valor predeterminado. En modo `host`, ReactUI exige la frase `APLICAR <ID_CONFIGURACION>` correspondiente al borrador que se desplegará. Si el cambio afecta la ruta de administración, solicita una segunda frase de riesgo y abre una ventana de confirmación de conectividad de 45 segundos. Sin confirmación, el agente revierte el snapshot automáticamente; el plazo puede ajustarse con `WANSIM_V2_CONFIRMATION_TIMEOUT`.

## Desinstalación

```bash
sudo wansim uninstall
sudo wansim uninstall --purge
```

La primera variante crea un respaldo y conserva `/etc/wansim` y `/var/lib/wansim`, lo cual permite reinstalar con `sudo ./install-v2.sh repair --non-interactive`. `--purge` elimina configuración, datos y usuario de servicio después de crear el respaldo. Ninguna variante elimina Docker ni `/var/backups/wansim`.
