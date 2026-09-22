# Criterios Para V2.0 Estable

La etiqueta `v2.0.0-stable` no se crea por avance de interfaz: requiere evidencia de operación en Linux y revisión de seguridad.

- Todas las pruebas unitarias V1 y V2 en verde, además de compilación ReactUI y validación Docker Compose.
- Matriz `v2/integration` aprobada en Ubuntu, Debian, Fedora y Rocky Linux, con evidencias de dos WAN, LAN VLAN, LAN acceso y rollback.
- Prueba manual de Bridge L2, DHCP, `netem`, reinicio de daemon y restauración de configuración activa anterior.
- Revisión de la migración V1→V2 y prueba de retorno a `v1.119-stable` en una VM dedicada.
- Tokens Telegram cifrados, secretos de webhook configurados y bots con chats/roles mínimos necesarios.
- API operativa protegida con una clave robusta, rotación probada y ausencia de credenciales en URL, logs o repositorio.
- Proxy HTTPS probado con certificado real, SQLite respaldada y recuperación validada.

Mientras alguna condición esté pendiente, la versión permanece `2.0.x-prebeta` y V1.119 es la instalación recomendada.
