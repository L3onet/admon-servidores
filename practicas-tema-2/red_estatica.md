# Configurar una IP estática en Ubuntu Server

> Válido para **Ubuntu Server 22.04 LTS y 24.04 LTS**, que usan **Netplan** con el backend `systemd-networkd`.

---

## Índice

1. [Requisitos](#1-requisitos)
2. [Identificar la interfaz y la configuración actual](#2-identificar-la-interfaz-y-la-configuración-actual)
3. [Respaldar la configuración existente](#3-respaldar-la-configuración-existente)
4. [Desactivar la red de cloud-init](#4-desactivar-la-red-de-cloud-init)
5. [Crear el archivo de IP estática](#5-crear-el-archivo-de-ip-estática)
6. [Validar y aplicar](#6-validar-y-aplicar)
7. [Verificar](#7-verificar)
8. [Variantes útiles](#8-variantes-útiles)
9. [Solución de problemas](#9-solución-de-problemas)
10. [Restaurar la configuración original](#10-restaurar-la-configuración-original)

---

## 1. Requisitos

- Acceso con un usuario con `sudo`.
- De preferencia, **acceso por consola** (física, de la VM o del proveedor). Si solo tienes SSH, usa `netplan try` (sección 6).
- Estos datos de tu red:

| Parámetro | Ejemplo | Cómo obtenerlo |
|-----------|---------|----------------|
| Interfaz | `enp0s3` | Sección 2 |
| IP / máscara (CIDR) | `192.168.1.50/24` | Elige una libre, **fuera del rango DHCP** del router |
| Gateway | `192.168.1.1` | `ip route \| grep default` |
| DNS | `1.1.1.1`, `8.8.8.8` | Los de tu red o públicos |

> **Máscara en formato CIDR:** `255.255.255.0` = `/24`, `255.255.0.0` = `/16`, `255.255.255.128` = `/25`.

---

## 2. Identificar la interfaz y la configuración actual

```bash
ip -br link
```

```
lo               UNKNOWN        00:00:00:00:00:00
enp0s3           UP             08:00:27:ab:cd:ef
```

La interfaz de este ejemplo es **`enp0s3`**. Sustitúyela por la tuya en todo el tutorial.

Anota la configuración actual:

```bash
ip -br -4 addr show enp0s3       # IP y máscara actuales
ip route | grep default          # gateway
resolvectl status enp0s3         # DNS
```

Comprueba que la IP que vas a usar **no esté ocupada** (desde el mismo servidor):

```bash
ping -c 3 192.168.1.50
```

Si responde, otro equipo ya la está usando: elige otra.

---

## 3. Respaldar la configuración existente

```bash
ls -l /etc/netplan/
sudo mkdir -p /root/netplan-backup
sudo cp -a /etc/netplan/*.yaml /root/netplan-backup/
```

Ahora retira los archivos originales para que no se mezclen con el nuevo. Netplan combina todos los `.yaml` de la carpeta, y dos archivos para la misma interfaz producen una configuración contradictoria.

```bash
sudo rm /etc/netplan/*.yaml
```

---

## 4. Desactivar la red de cloud-init

En muchas instalaciones, sobre todo en la nube y en VMs, cloud-init regenera `50-cloud-init.yaml` al reiniciar y borra tus cambios. Desactívalo:

```bash
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```

> Si el directorio `/etc/cloud/cloud.cfg.d/` no existe, cloud-init no está instalado y puedes omitir este paso.

---

## 5. Crear el archivo de IP estática

```bash
sudo nano /etc/netplan/01-netcfg.yaml
```

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s3:
      dhcp4: false
      dhcp6: false
      addresses:
        - 192.168.1.50/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses:
          - 1.1.1.1
          - 8.8.8.8
```

Qué hace cada clave:

| Clave | Significado |
|-------|-------------|
| `renderer: networkd` | Usa `systemd-networkd` (lo estándar en Ubuntu Server) |
| `dhcp4: false` | Desactiva el DHCP de IPv4 |
| `addresses` | IP fija con su máscara en CIDR |
| `routes` → `to: default` | Ruta por defecto (gateway) |
| `nameservers` | Servidores DNS |

> ⚠️ **YAML es sensible a la indentación.** Usa **espacios**, nunca tabuladores.
> 📝 No uses `gateway4:`: está **obsoleta** y Netplan muestra una advertencia. Usa `routes:` como arriba.

Asigna permisos restringidos (Netplan advierte si el archivo es legible por otros usuarios):

```bash
sudo chmod 600 /etc/netplan/01-netcfg.yaml
```

---

## 6. Validar y aplicar

**1. Validar la sintaxis** sin aplicar nada:

```bash
sudo netplan generate
```

Si no muestra nada, el archivo es válido.

**2. Aplicar con reversión automática:**

```bash
sudo netplan try
```

`netplan try` aplica la configuración y espera tu confirmación. Si no pulsas **Enter** en 120 segundos, **revierte los cambios** automáticamente. Así no te quedas sin acceso si algo sale mal.

> **Por SSH:** si la nueva IP es distinta de la actual, tu sesión se cortará. Abre una nueva conexión a la nueva IP (`ssh usuario@192.168.1.50`) y confirma ahí antes de que pasen los 120 s, o deja que se revierta y revisa el archivo.

**3. Aplicar de forma definitiva** (si no usaste `try` o ya confirmaste):

```bash
sudo netplan apply
```

---

## 7. Verificar

```bash
ip -br -4 addr show enp0s3     # debe mostrar 192.168.1.50/24
ip route | grep default        # default via 192.168.1.1
resolvectl status enp0s3       # DNS configurados
```

Prueba de conectividad por capas:

```bash
ping -c 3 192.168.1.1          # 1. llega al gateway
ping -c 3 1.1.1.1              # 2. sale a Internet
ping -c 3 ubuntu.com           # 3. resuelve nombres (DNS)
```

Comprueba que la IP ya **no es dinámica**: en la salida siguiente **no** debe aparecer la palabra `dynamic`.

```bash
ip -4 addr show enp0s3
```

En **Ubuntu 24.04** también puedes ver un resumen:

```bash
sudo netplan status
```

Finalmente, reinicia y confirma que la configuración persiste:

```bash
sudo reboot
# tras reiniciar:
ip -br -4 addr show enp0s3
```

---

## 8. Variantes útiles

### 8.1 Varias IPs en la misma interfaz

```yaml
      addresses:
        - 192.168.1.50/24
        - 192.168.1.51/24
```

### 8.2 Dominio de búsqueda DNS

Permite escribir `ping servidor1` en lugar de `ping servidor1.miempresa.local`:

```yaml
      nameservers:
        search: [miempresa.local]
        addresses: [192.168.1.10, 1.1.1.1]
```

### 8.3 IP estática también en IPv6

```yaml
      addresses:
        - 192.168.1.50/24
        - 2001:db8:1::50/64
      routes:
        - to: default
          via: 192.168.1.1
        - to: default
          via: 2001:db8:1::1
```

### 8.4 Identificar la interfaz por MAC

Útil si el nombre de la interfaz puede cambiar (por ejemplo, al mover una VM):

```yaml
  ethernets:
    lan:
      match:
        macaddress: 08:00:27:ab:cd:ef
      set-name: lan
      dhcp4: false
      addresses: [192.168.1.50/24]
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
```

---

## 9. Solución de problemas

| Síntoma | Causa probable | Solución |
|---------|----------------|----------|
| `Error in network definition` | Indentación incorrecta o tabuladores | Corrige el YAML; valida con `sudo netplan generate` |
| `Permissions for /etc/netplan/... are too open` | Permisos amplios | `sudo chmod 600 /etc/netplan/*.yaml` |
| `gateway4 has been deprecated` | Sintaxis antigua | Cambia a `routes:` con `to: default` |
| Tras reiniciar vuelve la IP anterior | cloud-init regenera la red | Sección 4 |
| Aparecen dos IPs en la interfaz | Quedó otro `.yaml` o sigue activo el DHCP | Deja solo `01-netcfg.yaml` y revisa `dhcp4: false` |
| Hay IP pero no hay Internet | Gateway incorrecto | Revisa `routes:` y `ip route` |
| Hay ping a `1.1.1.1` pero no a `ubuntu.com` | DNS incorrecto | Revisa `nameservers:` y `resolvectl status` |
| Conectividad intermitente | IP duplicada en la red | Usa una IP fuera del rango DHCP o reserva la IP en el router |
| Perdí el acceso por SSH | Cambió la IP o falló la config | Espera 120 s si usaste `try`, o entra por consola |

Revisar los registros de red:

```bash
journalctl -u systemd-networkd -b --no-pager | tail -n 30
```

---

## 10. Restaurar la configuración original

```bash
sudo rm /etc/netplan/01-netcfg.yaml
sudo cp -a /root/netplan-backup/*.yaml /etc/netplan/
sudo rm -f /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
sudo netplan apply
```

---

**Resumen:** un único archivo `/etc/netplan/01-netcfg.yaml` con `dhcp4: false`, la IP en `addresses`, el gateway en `routes` y los DNS en `nameservers`; permisos `600`; y `netplan try` antes de dar el cambio por bueno.