# Criterios Para V2.0 Estable

La etiqueta `v2.0.0-stable` no se crea por avance de interfaz: requiere evidencia de operación en Linux y revisión de seguridad.

- [x] Todas las pruebas unitarias V1 y V2 en verde, además de compilación ReactUI y validación Docker Compose.
- [x] Matriz automática `v2/integration` aprobada en Ubuntu 24.04, Debian 12, Fedora 42 y Rocky Linux 9, con dos WAN, LAN VLAN, LAN acceso y rollback real.
- [ ] Matriz Vagrant completa preparada para instalación, rollback inducido, reparación, Bridge/L3, `netem`, backup/restore y desinstalación; falta registrar una ejecución aprobada en los cuatro hipervisores invitados.
- [ ] Revisión de la migración V1→V2 y prueba de retorno a `v1.119-stable` en una VM dedicada.
- [ ] Tokens Telegram cifrados, secretos de webhook configurados y bots con chats/roles mínimos necesarios, verificados contra Telegram real.
- [ ] API operativa protegida con una clave robusta, rotación probada y ausencia de credenciales en URL, logs o repositorio.
- [ ] Proxy HTTPS probado con certificado real, SQLite respaldada y recuperación validada.

La evidencia automática de namespaces se publica en cada ejecución de `.github/workflows/linux-matrix.yml`. `v2.0.7-prestable` añade la matriz completa del instalador en Vagrant, pero no se declarará estable hasta registrar su ejecución aprobada en Ubuntu, Debian, Fedora y Rocky y completar los puntos manuales restantes. Mientras tanto, V1.119 permanece como instalación recomendada.
