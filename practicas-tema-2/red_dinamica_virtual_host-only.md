# Configurar una IP dinámica (DHCP) en Ubuntu Server con VirtualBox: adaptador "Solo-Anfitrión"

> Válido para **Ubuntu Server 22.04, 24.04 y 26.04 LTS** en **VirtualBox 7.x**, con anfitrión Windows, Linux o macOS (Intel).

---

## Índice

1. [Qué es el adaptador Solo-Anfitrión](#1-qué-es-el-adaptador-solo-anfitrión)
2. [Revisar la red Solo-Anfitrión en VirtualBox](#2-revisar-la-red-solo-anfitrión-en-virtualbox)
3. [Configurar el adaptador de la máquina virtual](#3-configurar-el-adaptador-de-la-máquina-virtual)
4. [Identificar la interfaz dentro de Ubuntu Server](#4-identificar-la-interfaz-dentro-de-ubuntu-server)
5. [Configurar DHCP con Netplan](#5-configurar-dhcp-con-netplan)
6. [Verificar la IP asignada](#6-verificar-la-ip-asignada)
7. [Probar la conexión desde el anfitrión](#7-probar-la-conexión-desde-el-anfitrión)
8. [Configuración recomendada: NAT + Solo-Anfitrión (con Internet)](#8-configuración-recomendada-nat--solo-anfitrión-con-internet)
9. [Reservar siempre la misma IP por DHCP (opcional)](#9-reservar-siempre-la-misma-ip-por-dhcp-opcional)
10. [Configuración por línea de comandos (VBoxManage)](#10-configuración-por-línea-de-comandos-vboxmanage)
11. [Solución de problemas](#11-solución-de-problemas)

---

## 1. Qué es el adaptador Solo-Anfitrión

El modo **Solo-Anfitrión** (*Host-only*) crea una red privada entre **tu equipo físico (anfitrión)** y **las máquinas virtuales**.

```
┌────────────────────── Equipo anfitrión ──────────────────────┐
│                                                              │
│   Adaptador virtual del anfitrión: 192.168.56.1              │
│          │                                                   │
│   ┌──────┴──────── Red Solo-Anfitrión 192.168.56.0/24 ─────┐ │
│   │   Servidor DHCP de VirtualBox: 192.168.56.100          │ │
│   │          │                          │                  │ │
│   │   VM Ubuntu Server            Otra VM (opcional)       │ │
│   │   192.168.56.101 (DHCP)       192.168.56.102 (DHCP)    │ │
│   └────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
          ✗ Sin acceso a Internet ni a la red física
```

| Característica | Solo-Anfitrión |
|----------------|----------------|
| Anfitrión ↔ VM | ✅ Sí |
| VM ↔ VM (misma red) | ✅ Sí |
| VM → Internet | ❌ No |
| Otros equipos de la red física → VM | ❌ No |
| Asignación de IP | Servidor DHCP integrado de VirtualBox |

Valores por defecto de VirtualBox:

| Parámetro | Valor |
|-----------|-------|
| Red | `192.168.56.0/24` |
| IP del anfitrión | `192.168.56.1` |
| Servidor DHCP | `192.168.56.100` |
| Rango DHCP | `192.168.56.101` – `192.168.56.254` |

> Ideal para laboratorios: el servidor es accesible desde tu equipo (SSH, web, Samba) pero queda aislado del resto de la red.
> Si además necesitas Internet en la VM (por ejemplo, para `apt`), usa la configuración de la **sección 8**.

---

## 2. Revisar la red Solo-Anfitrión en VirtualBox

### 2.1 Abrir el administrador de redes

En VirtualBox 7: **Archivo → Herramientas → Administrador de red** (*File → Tools → Network Manager*), pestaña **Redes solo-anfitrión** (*Host-only Networks*).

Debe existir una red:

| Anfitrión | Nombre habitual |
|-----------|-----------------|
| Windows | `VirtualBox Host-Only Ethernet Adapter` |
| Linux / macOS (Intel) | `vboxnet0` |

Si no existe, pulsa **Crear**.

### 2.2 Pestaña "Adaptador"

| Campo | Valor |
|-------|-------|
| Configurar adaptador | Manual |
| Dirección IPv4 | `192.168.56.1` |
| Máscara de red IPv4 | `255.255.255.0` |

### 2.3 Pestaña "Servidor DHCP"

Es **imprescindible** para la IP dinámica:

| Campo | Valor |
|-------|-------|
| ☑ **Habilitar servidor** | **Marcado** |
| Dirección del servidor | `192.168.56.100` |
| Máscara del servidor | `255.255.255.0` |
| Límite inferior de direcciones | `192.168.56.101` |
| Límite superior de direcciones | `192.168.56.254` |

Pulsa **Aplicar**.

> 💡 **Anfitrión Linux:** VirtualBox 7 solo permite por defecto redes Solo-Anfitrión dentro de `192.168.56.0/21`. Para usar otro rango, crea `/etc/vbox/networks.conf` con, por ejemplo:
>
> ```
> * 10.0.0.0/8 192.168.0.0/16
> ```

### 2.4 Comprobar el adaptador en el anfitrión

**Windows (PowerShell o CMD):**

```powershell
ipconfig
```

Busca **"Adaptador de Ethernet VirtualBox Host-Only Network"** con `192.168.56.1`.

**Linux:**

```bash
ip -br addr show vboxnet0
```

**macOS:**

```bash
ifconfig vboxnet0
```

---

## 3. Configurar el adaptador de la máquina virtual

Con la VM **apagada** (no en estado guardado):

1. Selecciona la VM → **Configuración → Red**.
2. **Adaptador 1**:

| Campo | Valor |
|-------|-------|
| ☑ Habilitar adaptador de red | Marcado |
| Conectado a | **Adaptador solo-anfitrión** (*Host-only Adapter*) |
| Nombre | `VirtualBox Host-Only Ethernet Adapter` (Windows) o `vboxnet0` |
| Avanzadas → Tipo de adaptador | Intel PRO/1000 MT Desktop (por defecto) |
| Avanzadas → Modo promiscuo | Denegar |
| Avanzadas → ☑ Cable conectado | **Marcado** |

3. Anota la **Dirección MAC** que aparece en *Avanzadas*; servirá para identificar la interfaz dentro de Ubuntu.
4. Pulsa **Aceptar** e inicia la VM.

---

## 4. Identificar la interfaz dentro de Ubuntu Server

Inicia sesión en la VM y ejecuta:

```bash
ip -br link
```

```
lo               UNKNOWN        00:00:00:00:00:00 <LOOPBACK,UP,LOWER_UP>
enp0s3           UP             08:00:27:3a:5b:7c <BROADCAST,MULTICAST,UP,LOWER_UP>
```

Relación habitual entre adaptadores de VirtualBox e interfaces:

| Adaptador en VirtualBox | Interfaz en Ubuntu |
|-------------------------|--------------------|
| Adaptador 1 | `enp0s3` |
| Adaptador 2 | `enp0s8` |
| Adaptador 3 | `enp0s9` |
| Adaptador 4 | `enp0s10` |

> Confirma comparando la **MAC**: VirtualBox la muestra sin separadores (`0800273A5B7C`) y Ubuntu con dos puntos (`08:00:27:3a:5b:7c`).

En este tutorial la interfaz Solo-Anfitrión es **`enp0s3`**.

---

## 5. Configurar DHCP con Netplan

### 5.1 Respaldar la configuración actual

```bash
ls -l /etc/netplan/
sudo mkdir -p /root/netplan-backup
sudo cp -a /etc/netplan/*.yaml /root/netplan-backup/
```

### 5.2 Evitar que cloud-init sobrescriba la red

```bash
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```

> Si `/etc/cloud/cloud.cfg.d/` no existe, omite este paso.

### 5.3 Dejar un único archivo de red

```bash
sudo rm /etc/netplan/*.yaml
sudo nano /etc/netplan/01-netcfg.yaml
```

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s3:
      dhcp4: true
      dhcp6: false
```

> ⚠️ YAML es sensible a la indentación: usa **espacios**, nunca tabuladores.

### 5.4 Permisos, validación y aplicación

```bash
sudo chmod 600 /etc/netplan/01-netcfg.yaml
sudo netplan generate        # valida la sintaxis (sin salida = correcto)
sudo netplan apply
```

> Como la red Solo-Anfitrión no tiene Internet, es normal ver avisos o esperas relacionadas con DNS o actualizaciones.

---

## 6. Verificar la IP asignada

```bash
ip -4 addr show enp0s3
```

```
2: enp0s3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ...
    inet 192.168.56.101/24 metric 100 brd 192.168.56.255 scope global dynamic enp0s3
       valid_lft 598sec preferred_lft 598sec
```

| Qué comprobar | Significado |
|---------------|-------------|
| `192.168.56.1xx` | IP dentro del rango DHCP de VirtualBox |
| `dynamic` | La IP se obtuvo por DHCP |
| `valid_lft` | Tiempo restante de la concesión; se renueva sola |

Más detalle, incluido el servidor DHCP que asignó la IP:

```bash
networkctl status enp0s3
```

Renovar la IP manualmente:

```bash
sudo networkctl renew enp0s3
```

---

## 7. Probar la conexión desde el anfitrión

### 7.1 Desde la VM hacia el anfitrión

```bash
ping -c 3 192.168.56.1
```

### 7.2 Desde el anfitrión hacia la VM

**Windows / Linux / macOS:**

```bash
ping 192.168.56.101
```

> Si el ping de la VM al anfitrión falla en **Windows**, el firewall de Windows puede estar bloqueando ICMP en ese adaptador. No afecta a las conexiones del anfitrión hacia la VM.

### 7.3 Conectarse por SSH

En la VM:

```bash
sudo apt install -y openssh-server   # requiere Internet; ver sección 8
```

En el anfitrión:

```bash
ssh usuario@192.168.56.101
```

### 7.4 Comprobar que no hay Internet (comportamiento esperado)

```bash
ping -c 3 1.1.1.1
```

Resultado esperado: `Network is unreachable` o 100 % de paquetes perdidos. **Es normal** en Solo-Anfitrión.

---

## 8. Configuración recomendada: NAT + Solo-Anfitrión (con Internet)

Para que la VM tenga **Internet** (para `apt`) y a la vez sea **accesible desde el anfitrión**, usa dos adaptadores:

| Adaptador | Conectado a | Interfaz en Ubuntu | Función |
|-----------|-------------|--------------------|---------|
| 1 | **NAT** | `enp0s3` | Internet |
| 2 | **Adaptador solo-anfitrión** | `enp0s8` | Acceso desde el anfitrión |

### 8.1 En VirtualBox (VM apagada)

- **Adaptador 1:** Conectado a → **NAT**.
- **Adaptador 2:** ☑ Habilitar → Conectado a → **Adaptador solo-anfitrión** → `vboxnet0` / `VirtualBox Host-Only Ethernet Adapter`.

### 8.2 En Ubuntu

```bash
sudo nano /etc/netplan/01-netcfg.yaml
```

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s3:            # NAT: Internet y ruta por defecto
      dhcp4: true
      dhcp6: false
    enp0s8:            # Solo-Anfitrión: red con el anfitrión
      dhcp4: true
      dhcp6: false
      dhcp4-overrides:
        use-routes: false
        use-dns: false
      optional: true
```

| Opción en `enp0s8` | Motivo |
|--------------------|--------|
| `use-routes: false` | La ruta a Internet debe salir siempre por NAT |
| `use-dns: false` | El DNS lo da la red NAT |
| `optional: true` | El arranque no espera a esta interfaz si está desconectada |

```bash
sudo chmod 600 /etc/netplan/01-netcfg.yaml
sudo netplan generate && sudo netplan apply
```

### 8.3 Verificar

```bash
ip -br -4 addr show scope global
ip route
```

```
enp0s3           UP             10.0.2.15/24
enp0s8           UP             192.168.56.101/24

default via 10.0.2.2 dev enp0s3 proto dhcp src 10.0.2.15 metric 100
10.0.2.0/24 dev enp0s3 proto kernel scope link src 10.0.2.15 metric 100
192.168.56.0/24 dev enp0s8 proto kernel scope link src 192.168.56.101 metric 100
```

- La ruta `default` sale por **`enp0s3` (NAT)**.
- La red `192.168.56.0/24` va por **`enp0s8` (Solo-Anfitrión)**.

Pruebas:

```bash
ping -c 3 ubuntu.com         # Internet por NAT
ping -c 3 192.168.56.1       # anfitrión por Solo-Anfitrión
```

Desde el anfitrión: `ssh usuario@192.168.56.101`.

---

## 9. Reservar siempre la misma IP por DHCP (opcional)

La IP dinámica puede cambiar si creas o clonas VMs. Para que el servidor DHCP de VirtualBox entregue **siempre la misma IP** a esta VM (manteniendo DHCP en Ubuntu), ejecuta en el **anfitrión**, con la VM apagada:

**Windows (CMD o PowerShell):**

```powershell
cd "C:\Program Files\Oracle\VirtualBox"
.\VBoxManage dhcpserver modify --interface="VirtualBox Host-Only Ethernet Adapter" --vm="Ubuntu Server" --nic=1 --fixed-address=192.168.56.110
```

**Linux / macOS:**

```bash
VBoxManage dhcpserver modify --interface=vboxnet0 --vm="Ubuntu Server" --nic=1 --fixed-address=192.168.56.110
```

| Parámetro | Valor |
|-----------|-------|
| `--vm` | Nombre exacto de la VM en VirtualBox |
| `--nic` | Número del adaptador Solo-Anfitrión (`1`, o `2` si usas NAT + Solo-Anfitrión) |
| `--fixed-address` | IP que siempre recibirá |

Reinicia el servidor DHCP de esa red (o reinicia VirtualBox), arranca la VM y comprueba con `ip -4 addr`.

---

## 10. Configuración por línea de comandos (VBoxManage)

Todo lo anterior también puede hacerse desde el anfitrión con `VBoxManage` (en Windows, desde `C:\Program Files\Oracle\VirtualBox`).

### Ver redes y servidores DHCP

```bash
VBoxManage list hostonlyifs
VBoxManage list dhcpservers
```

### Crear la red Solo-Anfitrión con DHCP (si no existe)

```bash
VBoxManage hostonlyif create
VBoxManage hostonlyif ipconfig vboxnet0 --ip=192.168.56.1 --netmask=255.255.255.0

VBoxManage dhcpserver add --interface=vboxnet0 \
  --server-ip=192.168.56.100 --netmask=255.255.255.0 \
  --lower-ip=192.168.56.101 --upper-ip=192.168.56.254 --enable
```

> En Windows, sustituye `vboxnet0` por el nombre que devuelva `hostonlyif create`, por ejemplo `"VirtualBox Host-Only Ethernet Adapter #2"`.

### Conectar la VM a la red (VM apagada)

Solo-Anfitrión en el adaptador 1:

```bash
VBoxManage modifyvm "Ubuntu Server" --nic1=hostonly --host-only-adapter1=vboxnet0 --cable-connected1=on
```

NAT en el adaptador 1 + Solo-Anfitrión en el 2:

```bash
VBoxManage modifyvm "Ubuntu Server" --nic1=nat
VBoxManage modifyvm "Ubuntu Server" --nic2=hostonly --host-only-adapter2=vboxnet0 --cable-connected2=on
```

Comprobar:

```bash
VBoxManage showvminfo "Ubuntu Server" | grep -i "^NIC"
```

---

## 11. Solución de problemas

| Síntoma | Causa probable | Solución |
|---------|----------------|----------|
| La interfaz no recibe IP | Servidor DHCP deshabilitado | Administrador de red → Servidor DHCP → ☑ Habilitar servidor |
| La interfaz aparece `DOWN` | "Cable conectado" desmarcado | Configuración → Red → Avanzadas → ☑ Cable conectado |
| `enp0s8` existe pero sin IP | No está en el archivo de Netplan | Añádela como en la sección 8.2 |
| Nombre del adaptador "No seleccionado" | La red Solo-Anfitrión no existe o se borró | Créala en el Administrador de red (sección 2) |
| La IP es `169.254.x.x` | No hubo respuesta DHCP | Revisa el servidor DHCP y reinicia la VM |
| El anfitrión no llega a la VM | Adaptador del anfitrión sin IP o en otra red | `ipconfig` / `ip a`: el anfitrión debe tener `192.168.56.1` |
| Sin Internet en la VM | Comportamiento normal de Solo-Anfitrión | Usa NAT + Solo-Anfitrión (sección 8) |
| Sin Internet con NAT + Solo-Anfitrión | La ruta por defecto sale por `enp0s8` | Añade `use-routes: false` en `enp0s8`; revisa `ip route` |
| La IP cambia al clonar la VM | Clon con la misma MAC o concesión nueva | Al clonar, elige *"Generar nuevas direcciones MAC"*; reserva la IP (sección 9) |
| Arranque lento ("waiting for network") | Interfaz sin conexión | `optional: true` en esa interfaz |
| Anfitrión Linux: error al crear la red | Rango fuera de lo permitido | `/etc/vbox/networks.conf` (sección 2.3) |
| Tras reiniciar vuelve la configuración anterior | cloud-init regenera la red | Paso 5.2 |

Diagnóstico dentro de la VM:

```bash
ip -br addr
ip route
networkctl status enp0s3
sudo journalctl -u systemd-networkd -b --no-pager | grep -i dhcp | tail -n 20
```

### Restaurar la configuración original

```bash
sudo rm /etc/netplan/01-netcfg.yaml
sudo cp -a /root/netplan-backup/*.yaml /etc/netplan/
sudo rm -f /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
sudo netplan apply
```

---

**Resumen:** en VirtualBox, activa el **servidor DHCP** de la red Solo-Anfitrión y conecta el adaptador de la VM a ella. En Ubuntu, pon `dhcp4: true` en esa interfaz dentro de `/etc/netplan/01-netcfg.yaml` y aplica con `netplan apply`. Si la VM necesita Internet, añade un adaptador **NAT** como adaptador 1 y deja el Solo-Anfitrión en el 2 con `use-routes: false`.