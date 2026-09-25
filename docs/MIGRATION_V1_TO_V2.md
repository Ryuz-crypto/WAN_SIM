# Migración De V1.119 A V2

V1 y V2 no comparten archivos de estado ni deben instalarse sobre el mismo host. Conserva V1 como referencia anterior y valida V2 primero en una VM de laboratorio antes de migrar un host operativo.

## 1. Respaldar V1

En el host V1, conserva la etiqueta y guarda los archivos de configuración antes de cualquier prueba:

```bash
cd WAN_SIM
git fetch --tags
git switch --detach v1.119-stable
mkdir -p ~/wansim-v1-backup
cp -a ~/emix_abundix.conf ~/wansim_dashboard.py ~/wansim_netem_state.json ~/.wansim ~/wansim-v1-backup/ 2>/dev/null || true
```

No copies tokens de Telegram ni llaves TLS a V2. El instalador crea secretos independientes en `/etc/wansim` y conserva el estado cifrado en `/var/lib/wansim`.

## 2. Levantar V2 En Paralelo

Clona V2 en otro directorio y utiliza puertos distintos a V1:

```bash
git clone --branch v2.0.11-stable --depth 1 https://github.com/Ryuz-crypto/WAN_SIM.git WAN_SIM-v2
cd WAN_SIM-v2
sudo ./install-v2.sh install
```

Sigue la sección **Instalación 2: Versión Más Actual** del README. V1 conserva el dashboard en `5000`; V2 publica ReactUI y la API mediante su proxy HTTPS.

## 3. Recrear La Topología Como Borrador

No importes directamente `~/emix_abundix.conf`: V2 valida el modelo antes de aplicar cambios. Desde ReactUI recrea los pares WAN/LAN, modo VLAN o acceso, segmentos, DHCP y WAN manual/DHCP. Selecciona **Validar y planear** y compara el diagrama con V1 antes de desplegar.

## 4. Validar Y Volver Atrás

Mantén V2 en `dry-run` durante la primera revisión. Cuando la matriz de integración haya sido aprobada para tu distribución, realiza el primer despliegue en una VM aislada, comprueba interfaces, DHCP, NAT y `netem`, y usa el botón **Rollback** si el plan no coincide con lo esperado.

`v2.0.11-stable` es la ruta recomendada para instalaciones nuevas. Conserva el respaldo y la referencia V1.119 hasta completar tus pruebas de aceptación locales.
