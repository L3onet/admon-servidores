# Instalación y configuración de un servidor DHCP en Ubuntu Server 26.04.1 LTS

> **Servidor DHCP utilizado:** ISC Kea (`kea-dhcp4-server`)
> **Sistema:** Ubuntu Server **26.04.1 LTS** (Resolute Raccoon) · Kea **3.0.3**
> **Plataforma:** máquinas virtuales en Oracle VirtualBox 7.x
> **Nivel:** intermedio · **Duración estimada:** 60–90 min

---

## Índice

1. [Objetivo](#1-objetivo)
2. [¿Por qué Kea y no isc-dhcp-server?](#2-por-qué-kea-y-no-isc-dhcp-server)
3. [Escenario de laboratorio en VirtualBox](#3-escenario-de-laboratorio-en-virtualbox)
4. [Preparación del servidor](#4-preparación-del-servidor)
5. [Instalación de Kea DHCP](#5-instalación-de-kea-dhcp)
6. [Configuración](#6-configuración)
7. [Arranque del servicio](#7-arranque-del-servicio)
8. [Pruebas de funcionamiento](#8-pruebas-de-funcionamiento)
9. [Creación de evidencias](#9-creación-de-evidencias)
10. [Solución de problemas](#10-solución-de-problemas)
11. [Rúbrica sugerida](#11-rúbrica-sugerida)
12. [Anexo: isc-dhcp-server (método heredado)](#anexo-isc-dhcp-server-método-heredado)

---

## 1. Objetivo

Al terminar esta práctica, el estudiante podrá:

- Configurar tres adaptadores de red en **VirtualBox**: NAT, un puente a la red de prácticas anteriores y un puente a la nueva red DHCP.
- Calcular una red DHCP propia a partir del último octeto de su IP, para no chocar con otros servidores DHCP.
- Configurar una IP estática en Ubuntu Server con **Netplan**.
- Instalar y configurar el servidor **Kea DHCPv4**, con un rango dinámico y una reservación por MAC.
- Verificar que el servidor entregue direcciones a uno o más clientes.
- Capturar el proceso **DORA** (Discover, Offer, Request, Ack) con `tcpdump`.
- Generar un **paquete de evidencias** verificable con hashes SHA-256.

---

## 2. ¿Por qué Kea y no isc-dhcp-server?

ISC, la organización que desarrolló `isc-dhcp-server`, declaró el fin de su mantenimiento en 2022. Su reemplazo oficial es **Kea**. Ubuntu marca `isc-dhcp-server` como obsoleto y sin soporte desde la 24.04 LTS. En la 26.04 el paquete pasó al repositorio **universe**, y la documentación de Ubuntu Server recomienda Kea para instalaciones nuevas.

| Característica          | isc-dhcp-server                 | Kea                                   |
|-------------------------|---------------------------------|---------------------------------------|
| Estado                  | Sin mantenimiento (EOL)         | Activo                                |
| Formato de configuración| Propio (`dhcpd.conf`)           | JSON (`kea-dhcp4.conf`)               |
| Cambios sin reinicio    | No                              | Sí, mediante API (control socket)     |
| Base de leases          | Archivo de texto                | CSV (memfile), MySQL o PostgreSQL     |
| Versión en Ubuntu 26.04.1 | 4.4.3 (universe)              | 3.0.3 (main)                          |

---

## 3. Escenario de laboratorio en VirtualBox

Este tutorial usa máquinas virtuales en **Oracle VirtualBox 7.x**. El servidor tiene **tres adaptadores de red**:

| Adaptador | Modo en VirtualBox   | Interfaz en Ubuntu | Red                         | IP del servidor              | Para qué sirve                                   |
|:---------:|----------------------|:------------------:|-----------------------------|------------------------------|--------------------------------------------------|
| 1         | **NAT**              | `enp0s3`           | `10.0.2.0/24` (VirtualBox)   | `10.0.2.15` (automática)     | Internet y actualizaciones (`apt`)               |
| 2         | **Adaptador puente** | `enp0s8`           | `192.168.1.0/24`             | `192.168.1.50` (fija)        | Conservar la IP de prácticas anteriores y entrar por SSH |
| 3         | **Adaptador puente** | `enp0s9`           | `192.168.50.0/24`            | `192.168.50.1` (fija)        | Red nueva donde **Kea** reparte direcciones      |

```
                 Internet
                    │
          NAT de VirtualBox (10.0.2.0/24)
                    │ Adaptador 1 · enp0s3
   ┌────────────────┴──────────────────┐
   │  SERVIDOR DHCP  srv-dhcp          │
   │  Ubuntu Server 26.04.1            │
   │  enp0s8 → 192.168.1.50/24         │── Adaptador 2 (puente) ── Red de prácticas anteriores
   │  enp0s9 → 192.168.50.1/24  [Kea]  │── Adaptador 3 (puente) ──┐   192.168.1.0/24
   └───────────────────────────────────┘                          │
                                                     Red DHCP 192.168.50.0/24
                                                                  │
                                                   ┌──────────────┴──────────────┐
                                                   │  CLIENTE(S)  (VM o equipo)   │
                                                   │  enp0s3 → DHCP de Kea        │
                                                   └──────────────────────────────┘
```

### 3.1 La regla del último octeto

Para que cada alumno tenga **su propia red DHCP** y nadie choque con nadie, la red del adaptador 3 se construye con el **último octeto de la IP del adaptador 2**:

> IP del adaptador 2: `192.168.1.`**`X`** → red del adaptador 3: `192.168.`**`X`**`.0/24` → IP del servidor: `192.168.`**`X`**`.1`

| IP en prácticas anteriores (adaptador 2) | Red DHCP (adaptador 3) | IP del servidor Kea | Pool                   | Reservación      |
|------------------------------------------|------------------------|---------------------|------------------------|------------------|
| `192.168.1.50`                           | `192.168.50.0/24`      | `192.168.50.1`      | `.100 – .200`          | `192.168.50.50`  |
| `192.168.1.37`                           | `192.168.37.0/24`      | `192.168.37.1`      | `.100 – .200`          | `192.168.37.50`  |
| `192.168.1.112`                          | `192.168.112.0/24`     | `192.168.112.1`     | `.100 – .200`          | `192.168.112.50` |

Como la IP de cada alumno en `192.168.1.0/24` es única, la red que se obtiene también es única.

Puedes calcular tu red en el propio servidor una vez que `enp0s8` tenga su IP:

```bash
OCT=$(ip -4 -o addr show enp0s8 | awk '{split($4,a,"[./]"); print a[4]}')
echo "Mi red DHCP: 192.168.${OCT}.0/24 · IP del servidor: 192.168.${OCT}.1"
```

> ⚠️ **Casos especiales:**
> - Si tu último octeto es **1**, la red resultante (`192.168.1.0/24`) es la misma que la del adaptador 2. Pide otra IP o usa, por ejemplo, `192.168.101.0/24`.
> - Antes de usar la red, confirma con tu docente o con el administrador que **no exista ya** en la escuela.
> - Escribe siempre **192**: `102.168.x.x` es un rango **público** de internet.

En el resto del tutorial se usa **50** como ejemplo. Si tu octeto es otro, reemplaza `192.168.50.` por `192.168.<tu octeto>.`. En las secciones 4.3 y 6.2 hay un comando que hace el cambio por ti.

### 3.2 ⚠️ Lee esto antes de conectar el adaptador 3

Un adaptador en **puente** pone la VM en el mismo segmento de red que la tarjeta física del anfitrión. El primer mensaje de DHCP (*Discover*) es un **broadcast** que llega a todos los equipos de ese segmento, sin importar su subred. Si el adaptador 3 comparte el segmento con la red de la escuela o la de tu casa, pasan dos cosas:

1. **Tu Kea podría responderle a equipos ajenos**, como laptops o teléfonos, y darles una IP `192.168.50.x` sin internet.
2. **Tu cliente recibiría dos ofertas**, una de Kea y otra del router, y podría quedarse con la del router.

Elige una de estas dos formas de conectar el adaptador 3:

| Opción | Cómo se conecta el adaptador 3 | Ventajas | Lo que necesitas |
|--------|--------------------------------|----------|------------------|
| **A (recomendada)** | Puente a una **segunda tarjeta física** (por ejemplo, un adaptador USB-Ethernet) conectada a un **switch aislado** o directo al equipo cliente | Sin choques posibles. Sirve también con clientes físicos y con Windows | Un adaptador USB-Ethernet, un cable y, opcionalmente, un switch |
| **B** | Puente a la **misma tarjeta** que el adaptador 2 | No requiere hardware extra | Las dos protecciones de este tutorial: Kea solo atiende **MACs registradas** (sección 6.2) y el cliente Linux solo acepta ofertas de **tu** servidor (prueba 3) |

> Con la opción B, **no uses clientes Windows**, porque no permiten filtrar de qué servidor aceptan la oferta. Usa la opción A o pide que se desactive el DHCP del router en ese segmento.

### 3.3 Configurar los adaptadores (interfaz gráfica)

Con las VMs **apagadas**:

**Servidor (`srv-dhcp`) → Configuración → Red**

| Pestaña      | Conectado a            | Nombre                                                                      | Avanzado          |
|--------------|------------------------|-----------------------------------------------------------------------------|-------------------|
| Adaptador 1  | **NAT**                | —                                                                           | Cable conectado ✔ |
| Adaptador 2  | **Adaptador puente**   | Tu tarjeta de la red de prácticas (por ejemplo, `en0: Ethernet` o `enp3s0`) | Cable conectado ✔ |
| Adaptador 3  | **Adaptador puente**   | Opción A: la **segunda** tarjeta (USB-Ethernet). Opción B: la misma del adaptador 2 | Cable conectado ✔ |

En cada pestaña marca **Habilitar adaptador de red**.

**Cliente → Configuración → Red**

| Pestaña      | Conectado a          | Nombre                                    |
|--------------|----------------------|-------------------------------------------|
| Adaptador 1  | **Adaptador puente** | La **misma tarjeta** que el adaptador 3 del servidor |

> 💡 Si el cliente es un equipo físico (opción A), conéctalo con un cable al switch aislado o directamente al adaptador USB-Ethernet.

> 💡 Si puedes, prefiere puentes sobre **Ethernet** antes que sobre Wi-Fi. Algunas redes Wi-Fi institucionales bloquean equipos que muestran varias direcciones MAC.

### 3.4 Configurar los adaptadores (línea de comandos)

Desde el equipo anfitrión, con las VMs apagadas:

```bash
# Ver los nombres exactos de las tarjetas físicas disponibles para puente
VBoxManage list bridgedifs | grep '^Name:'

# Servidor: NAT + puente (red 192.168.1.0/24) + puente (red DHCP)
VBoxManage modifyvm "srv-dhcp" \
  --nic1 nat \
  --nic2 bridged --bridge-adapter2 "en0: Ethernet" --cable-connected2 on \
  --nic3 bridged --bridge-adapter3 "en7: USB 10/100/1000 LAN" --cable-connected3 on

# Cliente: puente a la misma tarjeta que el adaptador 3 del servidor
VBoxManage modifyvm "cliente" \
  --nic1 bridged --bridge-adapter1 "en7: USB 10/100/1000 LAN"

# Comprobar
VBoxManage showvminfo "srv-dhcp" | grep -E '^NIC [123]:'
```

> Sustituye los nombres de las tarjetas por los que te dio `list bridgedifs`, y `"srv-dhcp"` y `"cliente"` por los nombres de tus VMs. En la opción B, usa en `--bridge-adapter3` el mismo nombre que en `--bridge-adapter2`.

### 3.5 Parámetros de la red DHCP

| Parámetro                         | Valor (ejemplo con octeto 50)      |
|-----------------------------------|------------------------------------|
| Red                               | `192.168.50.0/24`                  |
| IP del servidor (adaptador 3)     | `192.168.50.1`                     |
| Rango dinámico (pool)             | `192.168.50.100 – 192.168.50.200`  |
| Puerta de enlace                  | `192.168.50.1`                     |
| DNS                               | `1.1.1.1`, `8.8.8.8`               |
| Dominio                           | `lab.local`                        |
| Reservación fija                  | `192.168.50.50` (por MAC)          |
| Tiempo de concesión               | 3600 s (1 h)                       |

> ⚠️ **Importante:** Kea solo debe escuchar en **`enp0s9`** (adaptador 3). **Nunca** lo configures en `enp0s3` (NAT) ni en `enp0s8` (red de prácticas `192.168.1.0/24`), porque competirías con el router de esa red.

---

## 4. Preparación del servidor

### 4.1 Actualizar el sistema

```bash
sudo apt update && sudo apt -y full-upgrade
sudo hostnamectl set-hostname srv-dhcp
```

### 4.2 Identificar las interfaces

```bash
ip -br link
ip -br addr
```

Ejemplo de salida antes de configurar:

```
lo       UNKNOWN  127.0.0.1/8 ::1/128
enp0s3   UP       10.0.2.15/24 ...         ← Adaptador 1 (NAT)
enp0s8   UP       ...                      ← Adaptador 2 (puente 192.168.1.0/24)
enp0s9   DOWN                              ← Adaptador 3 (puente, red DHCP), aún sin IP
```

> En VirtualBox, los adaptadores 1, 2 y 3 suelen llamarse **`enp0s3`**, **`enp0s8`** y **`enp0s9`**. Si tus nombres son distintos, compara la MAC de `ip link` con la que muestra VirtualBox en **Red → Adaptador N → Avanzado → Dirección MAC**. VirtualBox la muestra sin los dos puntos.

### 4.3 Asignar las IPs con Netplan

> ⚠️ **Si en prácticas anteriores el adaptador 1 era el puente**, tu `192.168.1.50` estaba configurada en `enp0s3`. Ahora `enp0s3` es la NAT y el puente pasó a `enp0s8`. Si no quitas esa configuración vieja, la NAT recibirá la IP equivocada.

Respalda los archivos actuales de Netplan e impide que cloud-init los vuelva a generar:

```bash
ls /etc/netplan/
sudo mkdir -p /root/netplan-respaldo
sudo mv /etc/netplan/*.yaml /root/netplan-respaldo/
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```

Crea un solo archivo para las tres interfaces:

```bash
sudo nano /etc/netplan/60-lab-dhcp.yaml
```

```yaml
network:
  version: 2
  ethernets:
    enp0s3:              # Adaptador 1 - NAT: internet, DNS y ruta por defecto
      dhcp4: true
    enp0s8:              # Adaptador 2 - Puente: red de prácticas 192.168.1.0/24
      dhcp4: false
      addresses:
        - 192.168.1.50/24
    enp0s9:              # Adaptador 3 - Puente: red DHCP de Kea (192.168.<octeto>.0/24)
      dhcp4: false
      addresses:
        - 192.168.50.1/24
```

> - Solo `enp0s3` (NAT) lleva ruta por defecto. **No agregues `routes` ni gateway** a `enp0s8` ni a `enp0s9`, o tendrás dos rutas por defecto y perderás internet.
> - El servidor DHCP **nunca** debe obtener su propia IP por DHCP en la interfaz donde da servicio (`enp0s9`).
> - Antes de fijarla, verifica con `ping` que `192.168.1.50` no la esté usando otro equipo.

Si tu IP del adaptador 2 **no** termina en 50, ajusta el archivo. Cambia `37` por tu octeto:

```bash
OCT=37
sudo sed -i "s/192\.168\.1\.50\//192.168.1.${OCT}\//; s/192\.168\.50\.1\//192.168.${OCT}.1\//" /etc/netplan/60-lab-dhcp.yaml
grep -n '192.168' /etc/netplan/60-lab-dhcp.yaml
```

Aplica la configuración con permisos seguros. Netplan muestra una advertencia si el archivo es legible por todos.

```bash
sudo chmod 600 /etc/netplan/60-lab-dhcp.yaml
sudo netplan try      # Pulsa ENTER para confirmar antes de que pasen 120 s
ip -br addr
```

Salida esperada:

```
enp0s3   UP   10.0.2.15/24 ...
enp0s8   UP   192.168.1.50/24 ...
enp0s9   UP   192.168.50.1/24 ...
```

Comprueba las rutas y la conectividad:

```bash
ip route | grep default        # Debe salir solo por enp0s3 (via 10.0.2.2)
ping -c 3 ubuntu.com           # Internet por NAT
ping -c 3 192.168.1.1          # Red de prácticas por el puente (ajusta a la IP de tu router)
```

Desde tu equipo anfitrión ya puedes entrar por SSH con la IP de siempre: `ssh usuario@192.168.1.50`.

---

## 5. Instalación de Kea DHCP

```bash
sudo apt install -y kea-dhcp4-server
```

> Si la instalación muestra un diálogo sobre la contraseña de **kea-ctrl-agent** (la API REST), puedes elegir *no configurar*. Esta práctica no la necesita.

Verifica la versión instalada:

```bash
kea-dhcp4 -V            # Ubuntu 26.04.1: 3.0.3
dpkg -l | grep kea
systemctl status kea-dhcp4-server --no-pager
```

> **Cambios de Kea 3.0 en Ubuntu 26.04 que afectan esta práctica:**
> - El servicio ya **no corre como root**: usa el usuario **`_kea`**. systemd crea `/run/kea`, `/var/lib/kea` y `/var/log/kea` con permisos `750` y dueño `_kea`.
> - Por seguridad, Kea 3 solo acepta el socket de control dentro de `/run/kea`, el archivo de leases dentro de `/var/lib/kea` y los logs dentro de `/var/log/kea`. Las rutas de este tutorial ya cumplen esa regla.
> - Como esas carpetas son `750`, para leer leases y logs usa siempre `sudo` **con el archivo como argumento** (`sudo column ... archivo`), no con redirección (`sudo column ... < archivo`). La redirección la hace tu usuario, no root, y falla con *Permiso denegado*.
> - `client-class` (en pools) quedó obsoleto: ahora se usa la lista `client-classes`. En los logs, la clave correcta es `output-options`.

Respalda la configuración original:

```bash
sudo cp /etc/kea/kea-dhcp4.conf /etc/kea/kea-dhcp4.conf.orig
```

---

## 6. Configuración

### 6.1 Obtener las MACs de los clientes

Como el pool solo atenderá a clientes registrados, necesitas la MAC de **cada** cliente. En cada máquina cliente, ejecuta:

```bash
ip link show enp0s3     # Linux
```

```powershell
getmac /v               # Windows
```

Anota las MACs, por ejemplo `08:00:27:aa:bb:cc` para el cliente con IP fija y `08:00:27:dd:ee:ff` para un cliente que tomará su IP del pool. En VirtualBox también puedes verlas en **Configuración → Red → Avanzado → Dirección MAC**.

### 6.2 Escribir el archivo de configuración

Reemplaza todo el contenido del archivo:

```bash
sudo nano /etc/kea/kea-dhcp4.conf
```

```json
{
  "Dhcp4": {
    "interfaces-config": {
      "interfaces": [ "enp0s9" ]
    },

    "control-socket": {
      "socket-type": "unix",
      "socket-name": "/run/kea/kea4-ctrl-socket"
    },

    "lease-database": {
      "type": "memfile",
      "persist": true,
      "name": "/var/lib/kea/kea-leases4.csv",
      "lfc-interval": 3600
    },

    "renew-timer": 900,
    "rebind-timer": 1800,
    "valid-lifetime": 3600,
    "authoritative": false,

    "option-data": [
      { "name": "domain-name-servers", "data": "1.1.1.1, 8.8.8.8" },
      { "name": "domain-name",         "data": "lab.local" }
    ],

    "subnet4": [
      {
        "id": 1,
        "subnet": "192.168.50.0/24",
        "pools": [
          {
            "pool": "192.168.50.100 - 192.168.50.200",
            "client-classes": [ "KNOWN" ]
          }
        ],
        "option-data": [
          { "name": "routers", "data": "192.168.50.1" }
        ],
        "reservations": [
          {
            "hw-address": "08:00:27:aa:bb:cc",
            "ip-address": "192.168.50.50",
            "hostname": "cliente-fijo"
          },
          {
            "hw-address": "08:00:27:dd:ee:ff",
            "hostname": "cliente-02"
          }
        ]
      }
    ],

    "loggers": [
      {
        "name": "kea-dhcp4",
        "output-options": [
          { "output": "/var/log/kea/kea-dhcp4.log" }
        ],
        "severity": "INFO"
      }
    ]
  }
}
```

**Explicación de los bloques principales:**

| Bloque               | Función                                                                  |
|----------------------|--------------------------------------------------------------------------|
| `interfaces-config`  | Interfaz en la que Kea escucha: solo `enp0s9` (adaptador 3). **Nunca** pongas `enp0s3` (NAT) ni `enp0s8` (red `192.168.1.0/24`). |
| `authoritative`      | En `false`, Kea no responde con NAK a equipos que no conoce. Es importante si el adaptador 3 comparte red con otro DHCP. |
| `control-socket`     | Socket Unix para consultar y administrar el servicio en caliente.         |
| `lease-database`     | Guarda las concesiones en un CSV persistente.                             |
| `valid-lifetime`     | Duración de la concesión. Renew (T1) es al 25 % y Rebind (T2) al 50 %.    |
| `option-data` global | DNS y dominio que se entregan a todas las subredes.                       |
| `subnet4`            | Subred, rango dinámico, puerta de enlace y reservaciones.                 |
| `reservations`       | Registra las MACs de tus clientes. Con `ip-address`, el cliente recibe una IP fija (conviene que quede **fuera** del pool). Sin `ip-address`, el cliente queda registrado y recibe una IP del pool. |
| `client-classes: ["KNOWN"]`| El pool solo atiende a clientes **registrados** en `reservations`. A cualquier otro equipo, Kea no le ofrece nada. Así tu servidor no le reparte IPs a equipos ajenos si el adaptador 3 comparte red (opción B). |

Para agregar más clientes, copia el bloque de `cliente-02` dentro de `reservations` y cambia la MAC y el `hostname`.

**Si tu octeto no es 50**, cambia la red en todo el archivo de una sola vez:

```bash
OCT=$(ip -4 -o addr show enp0s8 | awk '{split($4,a,"[./]"); print a[4]}')
sudo sed -i "s/192\.168\.50\./192.168.${OCT}./g" /etc/kea/kea-dhcp4.conf
grep -n '192.168' /etc/kea/kea-dhcp4.conf
```

### 6.3 Validar la sintaxis antes de arrancar

```bash
sudo kea-dhcp4 -t /etc/kea/kea-dhcp4.conf
```

Si no hay errores, el comando termina sin mensajes de `ERROR` y con código de salida 0. Compruébalo así:

```bash
echo $?    # Debe imprimir 0
```

### 6.4 Firewall (si UFW está activo)

```bash
sudo ufw status
sudo ufw allow in on enp0s9 to any port 67 proto udp comment 'DHCP server'
```

---

## 7. Arranque del servicio

```bash
sudo systemctl enable --now kea-dhcp4-server
sudo systemctl restart kea-dhcp4-server
sudo systemctl status kea-dhcp4-server --no-pager
```

Salida esperada: `Active: active (running)`.

Comprueba que el servicio escucha en el puerto UDP 67:

```bash
sudo ss -ulnp | grep ':67'
```

```
UNCONN 0 0 192.168.50.1:67   0.0.0.0:*   users:(("kea-dhcp4",pid=...,fd=...))
```

---

## 8. Pruebas de funcionamiento

### Prueba 1 – Estado del servicio mediante la API (control socket)

```bash
sudo apt install -y socat
echo '{ "command": "status-get" }' | sudo socat - UNIX-CONNECT:/run/kea/kea4-ctrl-socket
echo '{ "command": "config-get" }' | sudo socat - UNIX-CONNECT:/run/kea/kea4-ctrl-socket | head -c 600; echo
```

✅ **Éxito:** la respuesta contiene `"result": 0`.

### Prueba 2 – Captura del proceso DORA con tcpdump

**En el servidor**, inicia la captura y déjala corriendo:

```bash
mkdir -p ~/evidencias
sudo tcpdump -i enp0s9 -n -vv 'udp port 67 or udp port 68' -w ~/evidencias/dhcp_dora.pcap
```

Mientras tanto, solicita una IP desde el cliente (Prueba 3). Luego detén la captura con `Ctrl+C` y léela:

```bash
sudo tcpdump -n -vv -r ~/evidencias/dhcp_dora.pcap | grep -E 'DHCP-Message|Requested-IP|Your-IP|Server-ID'
```

✅ **Éxito:** aparecen los cuatro mensajes en orden: **Discover → Offer → Request → ACK**.

> 💡 También puedes abrir `dhcp_dora.pcap` en **Wireshark** con el filtro `dhcp`. Una captura de pantalla de esa vista es una excelente evidencia.

### Prueba 3 – Cliente Linux (Ubuntu 26.04)

El cliente tiene un solo adaptador, en **puente** a la misma tarjeta que el adaptador 3 del servidor (sección 3.3). Configúralo para usar DHCP en `/etc/netplan/50-cloud-init.yaml` o en un archivo nuevo:

```yaml
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: true
```

```bash
sudo chmod 600 /etc/netplan/*.yaml
sudo netplan apply
sudo networkctl renew enp0s3      # Fuerza la renovación
ip -br addr show enp0s3
ip route
resolvectl status enp0s3 | grep -E 'DNS Servers|DNS Domain'
networkctl status enp0s3          # Muestra el servidor DHCP y el lease
```

**Solo con la opción B (red compartida):** haz que el cliente acepte ofertas **únicamente** de tu servidor Kea. Así no se queda con la IP del router. Netplan no tiene esta opción, pero systemd-networkd sí:

```bash
sudo mkdir -p /etc/systemd/network/10-netplan-enp0s3.network.d
sudo tee /etc/systemd/network/10-netplan-enp0s3.network.d/solo-kea.conf > /dev/null <<'EOF'
[DHCPv4]
AllowList=192.168.50.1
EOF
sudo networkctl reload
sudo networkctl reconfigure enp0s3
networkctl status enp0s3 | grep -iE 'address|gateway|DHCP4 Client'
```

> Usa en `AllowList` la IP de **tu** servidor (`192.168.<octeto>.1`). Para quitar el filtro, borra el archivo `solo-kea.conf` y vuelve a ejecutar `networkctl reload`.

✅ **Éxito:**
- La IP está en el rango `192.168.50.100–200`, o es `192.168.50.50` si es el cliente con reservación.
- La ruta por defecto es `default via 192.168.50.1`.
- Los DNS son `1.1.1.1` y `8.8.8.8`, y el dominio es `lab.local`.

Prueba la conectividad con el servidor:

```bash
ping -c 4 192.168.50.1
```

### Prueba 4 – Cliente Windows

```powershell
ipconfig /release
ipconfig /renew
ipconfig /all
```

✅ **Éxito:** en la salida aparecen `DHCP habilitado: Sí`, `Servidor DHCP: 192.168.50.1`, la IP del rango, la puerta de enlace y los DNS configurados.

### Prueba 5 – Verificar la reservación por MAC

En el cliente cuya MAC está en `reservations`:

```bash
sudo networkctl renew enp0s3
ip -br addr show enp0s3     # Debe mostrar 192.168.50.50/24
```

✅ **Éxito:** el cliente recibe **exactamente** `192.168.50.50`.

### Prueba 5b – Verificar que Kea ignora equipos no registrados

Esta prueba confirma que tu servidor no le reparte direcciones a equipos ajenos. Desde una VM o un equipo **cuya MAC no esté** en `reservations`, conectado a la misma red que el adaptador 3, ejecuta:

```bash
sudo apt install -y nmap
sudo nmap --script broadcast-dhcp-discover -e enp0s3
```

En el servidor:

```bash
sudo grep -E 'ALLOC_FAIL|DHCP4_PACKET_DROP' /var/log/kea/kea-dhcp4.log | tail
```

✅ **Éxito:** `nmap` **no** muestra ninguna oferta con `Server Identifier: 192.168.50.1`. En la opción B solo aparece la oferta del router. El log de Kea registra que no asignó dirección por restricción de clase.

### Prueba 6 – Revisar la base de concesiones (leases) en el servidor

```bash
sudo column -s, -t /var/lib/kea/kea-leases4.csv | less -S
```

✅ **Éxito:** aparece una fila por cliente con `address`, `hwaddr`, `valid_lifetime`, `expire` y `hostname`.

### Prueba 7 – Revisar los logs

```bash
sudo journalctl -u kea-dhcp4-server --since "15 min ago" --no-pager
sudo tail -n 50 /var/log/kea/kea-dhcp4.log
sudo grep -E 'DHCP4_LEASE_ALLOC|DHCP4_PACKET_SEND' /var/log/kea/kea-dhcp4.log | tail
```

✅ **Éxito:** hay mensajes `DHCP4_LEASE_ALLOC` que indican la IP asignada y la MAC del cliente.

### Prueba 8 (opcional) – Descubrimiento con nmap

Desde un cliente **registrado** en la red del adaptador 3:

```bash
sudo apt install -y nmap
sudo nmap --script broadcast-dhcp-discover -e enp0s3
```

✅ **Éxito:** se muestra `Server Identifier: 192.168.50.1` junto con las opciones ofrecidas (router, DNS, dominio, lease time).

### Prueba 9 (opcional) – Recargar la configuración sin reiniciar

Cambia, por ejemplo, `valid-lifetime` a `7200`. Después ejecuta:

```bash
sudo kea-dhcp4 -t /etc/kea/kea-dhcp4.conf && \
echo '{ "command": "config-reload" }' | sudo socat - UNIX-CONNECT:/run/kea/kea4-ctrl-socket
```

✅ **Éxito:** la respuesta es `"result": 0` y el servicio no se reinicia.

---

## 9. Creación de evidencias

### 9.1 ¿Qué entregar?

| # | Evidencia                                   | Tipo                       |
|---|---------------------------------------------|----------------------------|
| 1 | IP estática del servidor                     | Texto (`ip addr`)          |
| 2 | Paquete instalado y versión                  | Texto                      |
| 3 | Validación de la configuración               | Texto (`kea-dhcp4 -t`)     |
| 4 | Servicio activo y puerto 67 escuchando       | Texto                      |
| 5 | Respuesta de la API (`status-get`)           | Texto JSON                 |
| 6 | Captura DORA                                 | `.pcap` + captura Wireshark|
| 7 | Cliente con IP, gateway y DNS                | Captura de pantalla        |
| 8 | Reservación funcionando                      | Captura de pantalla        |
| 9 | Tabla de leases                              | Texto                      |
| 10| Logs con asignaciones                        | Texto                      |
| 11| Integridad del paquete de evidencias         | `SHA256SUMS.txt`           |

### 9.2 Grabar la sesión completa de terminal

Antes de empezar las pruebas, inicia una grabación:

```bash
script -q -T ~/evidencias/sesion.timing ~/evidencias/sesion.log
# ... ejecuta todas tus pruebas ...
exit    # Termina la grabación
```

Para **reproducir** la sesión, por ejemplo frente al docente:

```bash
scriptreplay -T ~/evidencias/sesion.timing ~/evidencias/sesion.log
```

### 9.3 Script automático de recolección de evidencias

Crea el script en el servidor:

```bash
nano ~/recolectar_evidencias.sh
```

```bash
#!/usr/bin/env bash
# Recolector de evidencias - Servidor DHCP Kea (Ubuntu 26.04.1 LTS, Kea 3.0)
# Uso: sudo ./recolectar_evidencias.sh <interfaz> "<Nombre del alumno>"

set -uo pipefail

IFACE="${1:-enp0s9}"
ALUMNO="${2:-Sin nombre}"
FECHA="$(date +%Y%m%d_%H%M%S)"
DIR="evidencias_dhcp_${FECHA}"
SOCK="/run/kea/kea4-ctrl-socket"
CONF="/etc/kea/kea-dhcp4.conf"
LEASES="/var/lib/kea/kea-leases4.csv"

if [[ $EUID -ne 0 ]]; then
  echo "Ejecuta con sudo." >&2
  exit 1
fi

mkdir -p "$DIR"

# Ejecuta un comando, guarda la salida en un archivo con encabezado y la muestra en pantalla.
ev() {
  local archivo="$1"; shift
  {
    echo "=================================================="
    echo " Evidencia : $archivo"
    echo " Alumno    : $ALUMNO"
    echo " Host      : $(hostname)"
    echo " Fecha     : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo " Comando   : $*"
    echo "=================================================="
    bash -c "$*" 2>&1
    echo
  } | tee "$DIR/$archivo"
}

ev 01_sistema.txt          "cat /etc/os-release; uname -a; hostnamectl"
ev 02_red_servidor.txt     "ip -br addr; ip route; cat /etc/netplan/*.yaml"
ev 03_paquete.txt          "kea-dhcp4 -V; dpkg -l | grep -i kea"
ev 04_validacion_conf.txt  "kea-dhcp4 -t $CONF && echo 'RESULTADO: configuracion valida'"
ev 05_configuracion.txt    "cat $CONF"
ev 06_servicio.txt         "systemctl is-enabled kea-dhcp4-server; systemctl status kea-dhcp4-server --no-pager"
ev 07_puerto_67.txt        "ss -ulnp | grep ':67'"
ev 08_api_status.txt       "echo '{ \"command\": \"status-get\" }' | socat - UNIX-CONNECT:$SOCK"
ev 09_leases.txt           "column -s, -t $LEASES"
ev 10_logs_journal.txt     "journalctl -u kea-dhcp4-server --since '2 hours ago' --no-pager"
ev 11_logs_asignaciones.txt "grep -E 'DHCP4_LEASE_ALLOC|DHCP4_RESERVED|DHCP4_PACKET_SEND' /var/log/kea/kea-dhcp4.log | tail -n 100"
ev 12_firewall.txt         "ufw status verbose || echo 'UFW no instalado'"

# Captura DORA de 60 s: renueva la IP en el cliente mientras corre.
echo ">>> Capturando tráfico DHCP durante 60 s en $IFACE. Renueva la IP en el cliente AHORA..."
timeout 60 tcpdump -i "$IFACE" -n 'udp port 67 or udp port 68' -w "$DIR/13_dhcp_dora.pcap" 2>/dev/null
ev 13_dhcp_dora_resumen.txt "tcpdump -n -vv -r $DIR/13_dhcp_dora.pcap 2>/dev/null | grep -E 'DHCP-Message|Your-IP|Client-Ethernet|Requested-IP'"

# Integridad y empaquetado
( cd "$DIR" && sha256sum * > SHA256SUMS.txt )
tar -czf "${DIR}.tar.gz" "$DIR"
sha256sum "${DIR}.tar.gz" | tee "${DIR}.tar.gz.sha256"

echo
echo "✅ Evidencias generadas en: $DIR/"
echo "✅ Paquete: ${DIR}.tar.gz"
```

Ejecútalo:

```bash
chmod +x ~/recolectar_evidencias.sh
sudo apt install -y socat tcpdump
sudo ~/recolectar_evidencias.sh enp0s9 "Nombre Apellido"
```

Mientras corren los 60 segundos de captura, ve al cliente y ejecuta `sudo networkctl renew enp0s3` (Linux) o `ipconfig /renew` (Windows).

### 9.4 Evidencias del lado del cliente

**Linux:**

```bash
{
  echo "Alumno: Nombre Apellido | Fecha: $(date)"
  hostnamectl
  ip -br addr
  ip route
  networkctl status enp0s3
  resolvectl status enp0s3
  ping -c 4 192.168.50.1
} 2>&1 | tee evidencia_cliente_$(hostname)_$(date +%Y%m%d_%H%M).txt
```

**Windows (PowerShell):**

```powershell
$f = "evidencia_cliente_$env:COMPUTERNAME_$(Get-Date -f yyyyMMdd_HHmm).txt"
"Alumno: Nombre Apellido | Fecha: $(Get-Date)" | Out-File $f
ipconfig /all | Out-File $f -Append
Get-NetIPConfiguration | Out-File $f -Append
Test-Connection 192.168.50.1 -Count 4 | Out-File $f -Append
```

### 9.5 Copiar las evidencias del servidor a tu equipo

```bash
# Desde tu equipo anfitrión, por la IP del adaptador puente
scp usuario@192.168.1.50:~/evidencias_dhcp_*.tar.gz .
```

### 9.6 Capturas de pantalla recomendadas

Las capturas deben mostrar el **nombre del host**, la **fecha y hora** y, de preferencia, el nombre del alumno en el prompt. Puedes poner tu nombre en el prompt así:

```bash
export PS1="[\u@\h \$(date +%H:%M) NombreAlumno] \w\$ "
```

1. `systemctl status kea-dhcp4-server` mostrando *active (running)*.
2. Wireshark con el filtro `dhcp` y los 4 paquetes DORA visibles.
3. El cliente con la IP recibida (`ip addr` o `ipconfig /all`).
4. El cliente con reservación recibiendo `192.168.50.50`.
5. La tabla de leases en el servidor.

### 9.7 Verificar la integridad (para el docente)

```bash
sha256sum -c evidencias_dhcp_*.tar.gz.sha256
tar -xzf evidencias_dhcp_*.tar.gz
cd evidencias_dhcp_*/ && sha256sum -c SHA256SUMS.txt
```

Si algún archivo fue modificado después de generarse, la verificación marca **FAILED**.

---

## 10. Solución de problemas

| Síntoma                                         | Causa probable                                    | Solución                                                                 |
|-------------------------------------------------|---------------------------------------------------|--------------------------------------------------------------------------|
| El servicio no arranca                           | Error de sintaxis JSON                             | `sudo kea-dhcp4 -t /etc/kea/kea-dhcp4.conf` y revisa comas y llaves       |
| `DHCP4_SUBNET_SELECTION_FAILED` en el log        | La IP de la interfaz no pertenece a la subred      | Verifica que `enp0s9` tenga `192.168.50.1/24`                             |
| No escucha en el puerto 67                       | Nombre de interfaz incorrecto                      | Compara `ip -br link` con `interfaces-config`                             |
| El cliente obtiene IP del router (`192.168.1.x`) | El adaptador 3 comparte red con otro DHCP (opción B) | Aplica `AllowList` en el cliente (prueba 3) o usa la opción A (tarjeta y switch aislados) |
| Equipos ajenos reciben `192.168.50.x`            | Falta `"client-classes": [ "KNOWN" ]` en el pool o Kea escucha en `enp0s8` | Restringe el pool a `KNOWN`, deja solo `enp0s9` en `interfaces` y reinicia Kea |
| El cliente registrado no recibe IP               | Su MAC no está en `reservations` o está mal escrita | Agrega o corrige la MAC (sección 6.1) y recarga la configuración |
| El cliente no ve al servidor                     | El cliente está en puente a otra tarjeta o el cable está desconectado | El cliente debe usar la **misma** tarjeta que el adaptador 3. Marca **Cable conectado** |
| El servidor perdió internet                      | Hay más de una ruta por defecto, o la NAT quedó con la config vieja de `enp0s3` | `ip route`: solo debe haber `default via 10.0.2.2 dev enp0s3`. Revisa la sección 4.3 |
| `enp0s8` no tiene `192.168.1.50`                 | Quedó un archivo viejo de Netplan o el adaptador 2 está en otra tarjeta | Revisa `/etc/netplan/` y el **Nombre** del adaptador 2 en VirtualBox |
| El cliente no recibe nada                        | Firewall o adaptador en otra red                   | `sudo ufw allow in on enp0s9 to any port 67 proto udp`; revisa los adaptadores |
| La reservación no se aplica                      | MAC mal escrita o el cliente ya tiene un lease     | Corrige la MAC, borra el lease del cliente y renueva                      |
| Error de permisos en el log                      | AppArmor o ruta no permitida                       | Usa `/var/log/kea/` y revisa `sudo journalctl -k \| grep apparmor`         |
| `'socket-name' is invalid: socket path:/run/kea does not exist or has more relaxed permissions than 750` | `/run/kea` no existe o tiene permisos abiertos (Kea 3) | Arranca el servicio con `systemctl`, que crea la carpeta, o ejecuta `sudo install -d -o _kea -g _kea -m 750 /run/kea` |
| `Permission denied` al leer leases o logs        | Las carpetas de Kea son `750` y la redirección `<` la hace tu usuario | Pasa el archivo como argumento: `sudo column -s, -t /var/lib/kea/kea-leases4.csv` |
| `DHCPSRV_CLIENT_CLASS_DEPRECATED` en el log      | Se usó `client-class` (sintaxis de Kea 2.x)       | Cámbialo por `"client-classes": [ "KNOWN" ]`                             |
| `socat: No such file` en el socket               | El servicio está caído o el socket tiene otra ruta | `ls -l /run/kea/` y `systemctl status kea-dhcp4-server`                   |

Para ver los logs con más detalle temporalmente, cambia `"severity": "INFO"` por `"DEBUG"` y agrega `"debuglevel": 50` en el bloque `loggers`. Después reinicia el servicio.

---

## 11. Rúbrica sugerida

| Criterio                                             | Puntos |
|------------------------------------------------------|:------:|
| Tres adaptadores de VirtualBox (NAT + 2 puentes), red por octeto e IPs en Netplan | 10 |
| Instalación de Kea y configuración validada           | 15     |
| Servicio activo, habilitado y escuchando en 67/udp    | 10     |
| Cliente recibe IP, gateway, DNS y dominio correctos   | 20     |
| Reservación por MAC funcionando                       | 10     |
| Captura DORA completa (pcap + Wireshark)              | 15     |
| Paquete de evidencias con hashes verificables         | 10     |
| Reporte: explicación de DORA y de la configuración    | 10     |
| **Total**                                            | **100**|

---

## Anexo: isc-dhcp-server (método heredado)

Úsalo solo si el programa de la materia lo exige. En Ubuntu 26.04.1 el paquete (versión 4.4.3) sigue disponible, pero está en el repositorio **universe** y **ya no recibe mantenimiento de ISC**. Si `apt` no lo encuentra, habilita universe con `sudo add-apt-repository universe`.

```bash
sudo apt install -y isc-dhcp-server
sudo cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.orig
```

Indica la interfaz en `/etc/default/isc-dhcp-server`:

```bash
INTERFACESv4="enp0s9"
INTERFACESv6=""
```

Configura `/etc/dhcp/dhcpd.conf`:

```conf
# Sin 'authoritative': así no envía NAK a equipos ajenos si la red es compartida
default-lease-time 3600;
max-lease-time 7200;

option domain-name "lab.local";
option domain-name-servers 1.1.1.1, 8.8.8.8;

subnet 192.168.50.0 netmask 255.255.255.0 {
  option routers 192.168.50.1;
  pool {
    range 192.168.50.100 192.168.50.200;
    deny unknown-clients;    # Solo clientes declarados con 'host'
  }
  option broadcast-address 192.168.50.255;
}

host cliente-fijo {
  hardware ethernet 08:00:27:aa:bb:cc;
  fixed-address 192.168.50.50;
}

host cliente-02 {
  hardware ethernet 08:00:27:dd:ee:ff;   # Toma su IP del pool
}
```

Valida, arranca y revisa:

```bash
sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf
sudo systemctl enable --now isc-dhcp-server
sudo systemctl status isc-dhcp-server --no-pager
cat /var/lib/dhcp/dhcpd.leases
sudo journalctl -u isc-dhcp-server --no-pager | tail
```

Las pruebas de la sección 8 (cliente, tcpdump, nmap) son las mismas. Lo único que cambia es la ubicación de los leases (`/var/lib/dhcp/dhcpd.leases`) y el nombre del servicio en el script de evidencias.

> ⚠️ No instales Kea e isc-dhcp-server activos a la vez en la misma interfaz, porque ambos compiten por el puerto 67.

---

### Si usas Ubuntu 24.04 LTS (Kea 2.4)

Todo el tutorial funciona igual, con dos cambios en `kea-dhcp4.conf`:

| Ubuntu 26.04.1 (Kea 3.0)            | Ubuntu 24.04 (Kea 2.4)          |
|-------------------------------------|---------------------------------|
| `"client-classes": [ "KNOWN" ]`     | `"client-class": "KNOWN"`       |
| `"output-options": [ ... ]`         | `"output_options": [ ... ]`     |

### Referencias

- Ubuntu Server docs – *How to install and configure isc-kea*: <https://documentation.ubuntu.com/server/how-to/networking/install-isc-kea/>
- Kea Administrator Reference Manual: <https://kea.readthedocs.io/>
- RFC 2131 – Dynamic Host Configuration Protocol: <https://www.rfc-editor.org/rfc/rfc2131>
