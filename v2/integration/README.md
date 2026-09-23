# Matriz De Integración V2

La matriz ejecuta el agente V2 sobre Ubuntu, Debian, Fedora y Rocky Linux. Crea únicamente interfaces `dummy` llamadas `wswan*`/`wslan*`, cadenas `iptables` administradas y luego valida dos WAN, una LAN por VLAN, una LAN en acceso y el rollback completo.

## Matriz Automática En GitHub

El workflow `.github/workflows/linux-matrix.yml` inicia una imagen real de cada distribución dentro de un namespace de red privilegiado y desechable. No usa mocks: ejecuta `ip`, `sysctl` e `iptables`, aplica la topología y comprueba que el rollback restaure direcciones, enlaces, reglas y forwarding. Cada trabajo publica `report.json` como evidencia.

También puede repetirse una distribución localmente desde la raíz del repositorio:

```bash
mkdir -p test-results/linux-matrix/ubuntu-24.04
docker run --rm --privileged --network bridge \
  -v "$PWD:/workspace" -w /workspace \
  -e WANSIM_EXPECTED_DISTRO=ubuntu \
  -e WANSIM_INTEGRATION_REPORT=/workspace/test-results/linux-matrix/ubuntu-24.04/report.json \
  ubuntu:24.04 bash /workspace/v2/integration/container-entrypoint.sh
```

## Matriz Completa Del Instalador En VMs

Requisitos en la estación que lanza las pruebas: Vagrant y un proveedor de VMs. VirtualBox es el predeterminado; VMware se usa con `VAGRANT_PROVIDER=vmware_desktop` si está disponible.

```bash
cd v2/integration
chmod +x provision.sh run-matrix.sh
./run-matrix.sh
```

Cada VM ejecuta el ciclo integral: instalación nueva, `doctor`, respaldo, fallo inducido durante `repair`, rollback automático, reparación, reinicio, transacción real de red, restauración, desinstalación conservadora, reinstalación y desinstalación total. Los reportes quedan en `test-results/vagrant/<distribución>/`.

Para ejecutar una sola distribución:

```bash
vagrant up ubuntu
vagrant provision ubuntu
```

Cuando termine, destruye las VMs de laboratorio:

```bash
vagrant destroy -f
```

La matriz automática de namespaces es requisito para declarar una versión pre-estable. La ejecución adicional de Vagrant y la revisión del log de cada VM continúan siendo requisitos para declarar estable la versión 2.0.
