# Operación De WAN_SIM 2

Esta guía aplica a `v2.0.7-prestable`. La versión estable para entornos operativos continúa siendo `v1.119-stable`.

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
sudo wansim update v2.0.7-prestable
sudo wansim repair
```

`update` sólo descarga una etiqueta V2 permitida, comprueba que el checkout coincide exactamente, respalda y ejecuta el instalador transaccional. `repair` reinstala los componentes de la versión local conservando configuración, secretos, certificados y datos.

## Modo De Red

```bash
sudo wansim enable-host-apply --confirm
sudo wansim disable-host-apply
```

`dry-run` es el valor predeterminado. En modo `host`, ReactUI todavía exige la frase `APLICAR <ID_CONFIGURACION>` correspondiente al borrador que se desplegará.

## Desinstalación

```bash
sudo wansim uninstall
sudo wansim uninstall --purge
```

La primera variante crea un respaldo y conserva `/etc/wansim` y `/var/lib/wansim`, lo cual permite reinstalar con `sudo ./install-v2.sh repair --non-interactive`. `--purge` elimina configuración, datos y usuario de servicio después de crear el respaldo. Ninguna variante elimina Docker ni `/var/backups/wansim`.
