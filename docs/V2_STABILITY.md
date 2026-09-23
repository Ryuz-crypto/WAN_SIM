# Criterios Para V2.0 Estable

La etiqueta `v2.0.0-stable` no se crea por avance de interfaz: requiere evidencia de operación en Linux y revisión de seguridad.

- [x] Todas las pruebas unitarias V1 y V2 en verde, además de compilación ReactUI y validación Docker Compose.
- [x] Matriz automática `v2/integration` aprobada en Ubuntu 24.04, Debian 12, Fedora 42 y Rocky Linux 9, con dos WAN, LAN VLAN, LAN acceso y rollback real.
- [ ] Matriz Vagrant completa y prueba manual de Bridge L2, DHCP, `netem`, reinicio de daemon y restauración de configuración activa anterior.
- [ ] Revisión de la migración V1→V2 y prueba de retorno a `v1.119-stable` en una VM dedicada.
- [ ] Tokens Telegram cifrados, secretos de webhook configurados y bots con chats/roles mínimos necesarios, verificados contra Telegram real.
- [ ] API operativa protegida con una clave robusta, rotación probada y ausencia de credenciales en URL, logs o repositorio.
- [ ] Proxy HTTPS probado con certificado real, SQLite respaldada y recuperación validada.

La evidencia automatizada que habilita `2.0.5-prestable` está en [GitHub Actions run 35820610126](https://github.com/Ryuz-crypto/WAN_SIM/actions/runs/35820610126). Mientras alguna condición manual siga pendiente, V1.119 permanece como instalación recomendada y no se crea `v2.0.0-stable`.
