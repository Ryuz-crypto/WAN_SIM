# Evidencia De Estabilidad V2.0

La etiqueta `v2.0.13-stable` conserva la versión estable de la plataforma V2 con evidencia automática reproducible:

- [x] Pruebas unitarias V1/V2, compilación ReactUI y validación Docker Compose.
- [x] Matriz de red real en Ubuntu 24.04, Ubuntu 26.04, Debian 12, Fedora 42 y Rocky Linux 9, con dos WAN, LAN VLAN/acceso, Bridge, `netem` y rollback.
- [x] Resolución por wheels e importación del agente en Python 3.9, 3.12 y 3.14, sin compilación nativa durante la instalación.
- [x] Matriz Vagrant con `systemd`: instalación, fallo inducido, rollback, reparación, backup/restore, reinstalación y purga en las cuatro distribuciones.
- [x] Referencia `v1.119-stable` clonada y validada después del ciclo V2 para comprobar la ruta de retorno.
- [x] Tokens y secretos webhook de Telegram cifrados en SQLite; permisos y endpoints cubiertos por pruebas. La conectividad con cada bot se valida desde ReactUI al registrarlo.
- [x] API protegida, sesiones RBAC, rotación de contraseña, revocación y auditoría verificadas.
- [x] HTTPS autofirmado y certificado PEM firmado por CA de prueba, integridad SQLite, soporte sanitizado y recuperación validados.
- [x] Paquetes DEB/RPM, checksums y procedencia generados por el workflow de publicación.

La evidencia se publica en los workflows `checks.yml`, `linux-matrix.yml`, `vagrant-matrix.yml` y `packages.yml`. La matriz Vagrant hospedada utiliza contenedores Linux con `systemd` administrados por Vagrant; el mismo `Vagrantfile` conserva VirtualBox para pruebas locales en VMs completas.

V2 inicia en `dry-run`. La etiqueta estable certifica el software y su instalador, pero el primer cambio de red de cada entorno debe validarse con acceso por consola y el plan de ReactUI. El desarrollo posterior continúa en V3 y no modifica esta etiqueta.
