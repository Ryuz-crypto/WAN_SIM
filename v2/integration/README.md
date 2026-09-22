# Matriz De Integración V2

La matriz ejecuta el agente V2 en cuatro VMs desechables: Ubuntu, Debian, Fedora y Rocky Linux. Crea únicamente interfaces `dummy` llamadas `wswan*`/`wslan*`, una cadena `WANSIM_POSTROUTING` propia y luego valida dos WAN, una LAN por VLAN, una LAN en acceso y el rollback.

Requisitos en la estación que lanza las pruebas: Vagrant y un proveedor de VMs. VirtualBox es el predeterminado; VMware se usa con `VAGRANT_PROVIDER=vmware_desktop` si está disponible.

```bash
cd v2/integration
chmod +x provision.sh run-matrix.sh
./run-matrix.sh
```

Para ejecutar una sola distribución:

```bash
vagrant up ubuntu
vagrant ssh ubuntu -c 'sudo PYTHONPATH=/vagrant/v2/backend python3 /vagrant/v2/integration/host_apply.py'
```

Cuando termine, destruye las VMs de laboratorio:

```bash
vagrant destroy -f
```

La ejecución de esta matriz y la revisión del log de cada VM son requisitos para declarar estable la versión 2.0.
