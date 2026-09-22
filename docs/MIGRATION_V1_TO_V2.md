# Migración De V1.119 A V2

V1 y V2 no comparten archivos de estado ni deben instalarse sobre el mismo host de producción. Conserva V1 como referencia estable y despliega V2 primero en una VM de laboratorio.

## 1. Respaldar V1

En el host V1, conserva la etiqueta y guarda los archivos de configuración antes de cualquier prueba:

```bash
cd WAN_SIM
git fetch --tags
git switch --detach v1.119-stable
mkdir -p ~/wansim-v1-backup
cp -a ~/emix_abundix.conf ~/wansim_dashboard.py ~/wansim_netem_state.json ~/.wansim ~/wansim-v1-backup/ 2>/dev/null || true
```

No copies tokens de Telegram ni llaves TLS a V2. V2 cifra sus propios secretos en `~/.wansim-v2/secret.key` cuando se ejecuta de forma nativa, o en el volumen `wansim_state` al usar Compose.

## 2. Levantar V2 En Paralelo

Clona V2 en otro directorio y utiliza puertos distintos a V1:

```bash
git clone --branch main https://github.com/Ryuz-crypto/WAN_SIM.git WAN_SIM-v2
cd WAN_SIM-v2
```

Sigue la sección **Instalación V2 Pre-Beta** del README. V1 conserva el dashboard en `5000`; V2 nativa usa `8080` para FastAPI y `5173` para ReactUI. Compose publica el proxy en `8080` por defecto.

## 3. Recrear La Topología Como Borrador

No importes directamente `~/emix_abundix.conf`: V2 valida el modelo antes de aplicar cambios. Desde ReactUI recrea los pares WAN/LAN, modo VLAN o acceso, segmentos, DHCP y WAN manual/DHCP. Selecciona **Validar y planear** y compara el diagrama con V1 antes de desplegar.

## 4. Validar Y Volver Atrás

Mantén V2 en `dry-run` durante la primera revisión. Cuando la matriz de integración haya sido aprobada para tu distribución, realiza el primer despliegue en una VM aislada, comprueba interfaces, DHCP, NAT y `netem`, y usa el botón **Rollback** si el plan no coincide con lo esperado.

La migración a un host operativo sólo se aprueba después de una versión V2 estable; hasta entonces V1.119 sigue siendo la ruta soportada.
