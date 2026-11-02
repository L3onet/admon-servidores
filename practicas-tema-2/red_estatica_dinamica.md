# Configurar la red en Ubuntu Server: IP estática, IP dinámica (DHCP) y cómo cambiar entre ellas

> Probado para **Ubuntu Server 22.04 LTS y 24.04 LTS**, que usan **Netplan** con el backend `systemd-networkd`. La misma sintaxis aplica en **26.04 LTS**.

> ⚠️ **Antes de copiar cualquier bloque, revisa cómo se llama tu interfaz de red (sección 2).**
> Todos los ejemplos usan **`enp2s0`**, que es el nombre en la VM de VMware Fusion usada para este tutorial. En tu equipo puede llamarse distinto (`enp0s3`, `ens33`, `ens18`, `eth0`...). Si el nombre del YAML no coincide con el real, **Netplan no muestra ningún error**: simplemente ignora la configuración y la interfaz se queda con la IP que ya tenía.

---

## Índice

1. [Conceptos rápidos](#1-conceptos-rápidos)
2. [Identificar la interfaz de red](#2-identificar-la-interfaz-de-red)
3. [Respaldar y preparar Netplan](#3-respaldar-y-preparar-netplan)
4. [Configurar IP dinámica (DHCP)](#4-configurar-ip-dinámica-dhcp)
5. [Configurar IP estática](#5-configurar-ip-estática)
6. [Aplicar cambios de forma segura](#6-aplicar-cambios-de-forma-segura)
7. [Cambiar entre estática y dinámica con perfiles](#7-cambiar-entre-estática-y-dinámica-con-perfiles)
8. [Script para alternar con un solo comando](#8-script-para-alternar-con-un-solo-comando)
9. [Verificación](#9-verificación)
10. [Solución de problemas](#10-solución-de-problemas)

---

## 1. Conceptos rápidos

| Tipo | Quién asigna la IP | Uso típico |
|------|--------------------|------------|
| **Dinámica (DHCP)** | El router / servidor DHCP | Laptops, pruebas, redes que cambian |
| **Estática** | Tú, en la configuración | Servidores, bases de datos, servicios que otros deben encontrar siempre en la misma IP |

Netplan lee los archivos `*.yaml` de `/etc/netplan/` (solo el primer nivel, no subcarpetas), los combina en orden alfabético y genera la configuración para `systemd-networkd`.

> ⚠️ **YAML es sensible a la indentación.** Usa **espacios**, nunca tabuladores.

---

## 2. Identificar la interfaz de red

> ⚠️ **Este paso no es opcional.** El nombre de la interfaz depende del hardware (real o virtual), así que no lo copies de un tutorial: compruébalo en tu equipo.

```bash
ip -br link
```

Salida de ejemplo:

```
lo               UNKNOWN        00:00:00:00:00:00
enp2s0           UP             00:50:56:20:28:6c
```

La interfaz es la que **no** es `lo`. Si hay varias, la que tiene salida a Internet es esta:

```bash
ip route show default | awk '{print $5; exit}'
```

En este tutorial la interfaz es **`enp2s0`**. Nombres habituales según dónde corre Ubuntu (orientativos; manda lo que diga `ip -br link`):

| Entorno | Nombre habitual |
|---------|-----------------|
| VMware Fusion / Workstation | `enp2s0`, `ens160`, `ens33` |
| VirtualBox | `enp0s3` |
| KVM / Proxmox | `ens18`, `enp1s0` |
| Equipo físico | `eno1`, `enp3s0`, `eth0` |

El nombre también puede cambiar si mueves la VM a otro hipervisor o cambias su hardware virtual, así que vuelve a revisarlo en ese caso.

**Si tu interfaz no se llama `enp2s0`**, sustituye el nombre en cada bloque de este tutorial. Si ya creaste los archivos con otro nombre, ve a [Corregir el nombre de la interfaz](#corregir-el-nombre-de-la-interfaz).

Anota también tu configuración actual; te servirá para la IP estática:

```bash
ip -br addr show enp2s0      # IP y máscara actuales
ip route | grep default      # gateway (puerta de enlace)
resolvectl status enp2s0     # servidores DNS
```

---

## 3. Respaldar y preparar Netplan

### 3.1 Ver los archivos existentes

```bash
ls -l /etc/netplan/
```

Normalmente verás algo como `50-cloud-init.yaml` o `00-installer-config.yaml`.

### 3.2 Hacer respaldo

```bash
sudo mkdir -p /root/netplan-backup
sudo cp -a /etc/netplan/*.yaml /root/netplan-backup/
```

### 3.3 Evitar que cloud-init sobrescriba tu configuración

Si existe `50-cloud-init.yaml`, cloud-init puede regenerarlo al reiniciar. Desactívalo:

```bash
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```

### 3.4 Dejar un solo archivo de red

Para evitar que dos archivos se mezclen y configuren la misma interfaz de forma contradictoria, retira los originales (ya están respaldados):

```bash
sudo rm /etc/netplan/*.yaml
```

A partir de aquí usaremos un único archivo: **`/etc/netplan/01-netcfg.yaml`**.

---

## 4. Configurar IP dinámica (DHCP)

```bash
sudo nano /etc/netplan/01-netcfg.yaml
```

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp2s0:
      dhcp4: true
      dhcp6: false
```

> La clave `enp2s0:` debe ser el nombre exacto que viste en la sección 2.

Permisos correctos (Netplan advierte si el archivo es legible por otros usuarios):

```bash
sudo chmod 600 /etc/netplan/01-netcfg.yaml
```

Aplica (ver sección 6):

```bash
sudo netplan apply
```

---

## 5. Configurar IP estática

Datos de ejemplo (ajústalos a tu red):

| Parámetro | Valor |
|-----------|-------|
| IP / máscara | `192.168.1.50/24` |
| Gateway | `192.168.1.1` |
| DNS | `1.1.1.1`, `8.8.8.8` |

> Elige una IP **fuera del rango DHCP** del router para evitar conflictos.

> ⚠️ Comprueba que `enp2s0` sea el nombre real de tu interfaz (`ip -br link`). Con un nombre equivocado el comando termina sin errores, pero la IP estática no se aplica.

```bash
sudo nano /etc/netplan/01-netcfg.yaml
```

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp2s0:
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

```bash
sudo chmod 600 /etc/netplan/01-netcfg.yaml
sudo netplan try
```

> 📝 La clave antigua `gateway4:` está **obsoleta**. Usa `routes:` con `to: default`, como arriba.

---

## 6. Aplicar cambios de forma segura

| Comando | Qué hace |
|---------|----------|
| `sudo netplan generate` | Valida la sintaxis y genera la configuración sin aplicarla |
| `sudo netplan try` | Aplica los cambios y **los revierte en 120 s** si no confirmas con Enter |
| `sudo netplan apply` | Aplica los cambios de forma definitiva |

**Si estás conectado por SSH**, usa siempre `netplan try`: si pierdes la conexión, la configuración anterior se restaura sola.

> Ojo: al pasar de DHCP a estática (o al revés) **la IP puede cambiar**, así que tu sesión SSH se cortará. Vuelve a conectarte a la nueva IP dentro de los 120 s y confirma, o hazlo desde la consola física / de la VM.

---

## 7. Cambiar entre estática y dinámica con perfiles

En lugar de editar el archivo cada vez, guarda ambas configuraciones como **perfiles** en una subcarpeta (Netplan no lee subcarpetas, así que no interfieren).

> ⚠️ Los dos perfiles llevan el nombre de la interfaz. Si la tuya no es `enp2s0`, cámbialo en **ambos** antes de crearlos.

### 7.1 Crear la carpeta de perfiles

```bash
sudo mkdir -p /etc/netplan/perfiles
```

### 7.2 Perfil DHCP

```bash
sudo tee /etc/netplan/perfiles/dhcp.yaml > /dev/null <<'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    enp2s0:
      dhcp4: true
      dhcp6: false
EOF
```

### 7.3 Perfil estático

```bash
sudo tee /etc/netplan/perfiles/estatica.yaml > /dev/null <<'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    enp2s0:
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
EOF
```

```bash
sudo chmod 600 /etc/netplan/perfiles/*.yaml
```

### 7.4 Cambiar manualmente

**A estática:**

```bash
sudo install -m 600 /etc/netplan/perfiles/estatica.yaml /etc/netplan/01-netcfg.yaml
sudo netplan try
```

**A DHCP:**

```bash
sudo install -m 600 /etc/netplan/perfiles/dhcp.yaml /etc/netplan/01-netcfg.yaml
sudo netplan try
```

> `install -m 600` copia el archivo y fija los permisos en un solo paso.

---

## 8. Script para alternar con un solo comando

```bash
sudo nano /usr/local/sbin/red-perfil
```

```bash
#!/usr/bin/env bash
# Alterna entre perfiles de red de Netplan
set -euo pipefail

PERFILES="/etc/netplan/perfiles"
DESTINO="/etc/netplan/01-netcfg.yaml"

uso() {
  echo "Uso: sudo red-perfil {estatica|dhcp|estado}"
  exit 1
}

[[ $EUID -eq 0 ]] || { echo "Error: ejecuta con sudo."; exit 1; }

case "${1:-}" in
  estatica|dhcp)
    ORIGEN="$PERFILES/$1.yaml"
    [[ -f "$ORIGEN" ]] || { echo "Error: no existe $ORIGEN"; exit 1; }
    install -m 600 -o root -g root "$ORIGEN" "$DESTINO"
    netplan generate            # valida antes de aplicar
    netplan apply
    echo "✔ Perfil '$1' aplicado."
    ip -br -4 addr show scope global
    ;;
  estado)
    if grep -q 'dhcp4: true' "$DESTINO"; then
      echo "Perfil actual: DHCP"
    else
      echo "Perfil actual: estática"
    fi
    ip -br -4 addr show scope global
    ip route | grep default || true
    ;;
  *)
    uso
    ;;
esac
```

```bash
sudo chmod 750 /usr/local/sbin/red-perfil
```

### Uso

```bash
sudo red-perfil estado      # ver perfil e IP actuales
sudo red-perfil estatica    # cambiar a IP estática
sudo red-perfil dhcp        # cambiar a DHCP
```

El script comprueba que la interfaz escrita en el perfil exista antes de aplicarlo, y `estado` distingue entre el perfil **configurado** y la IP **realmente en uso**. Si no coinciden (perfil "estática" pero IP "obtenida por DHCP"), el nombre de la interfaz en el YAML está mal.

> ⚠️ El script usa `netplan apply` (no `try`) para poder ejecutarse sin intervención. Si trabajas por SSH, prefiere los comandos manuales de la sección 7.4 con `netplan try`.

---

## 9. Verificación

```bash
ip -br -4 addr show enp2s0        # IP asignada
ip route | grep default           # gateway
resolvectl status enp2s0          # DNS en uso
ping -c 3 192.168.1.1             # alcanza el gateway
ping -c 3 1.1.1.1                 # sale a Internet
ping -c 3 ubuntu.com              # resuelve nombres (DNS)
```

En **Ubuntu 24.04** también tienes un resumen completo:

```bash
sudo netplan status
```

Para saber si la IP vino por DHCP, busca la palabra `dynamic` en:

```bash
ip -4 addr show enp2s0
```

Con el perfil estático **no** debe aparecer `dynamic`, y la ruta por defecto debe decir `proto static` en lugar de `proto dhcp`:

```bash
ip route | grep default
```

Si sigues viendo `dynamic` y `proto dhcp` después de aplicar el perfil estático, la configuración no se aplicó: revisa el nombre de la interfaz.

---

## 10. Solución de problemas

| Síntoma | Causa probable | Solución |
|---------|----------------|----------|
| El perfil es estático pero la IP sigue siendo la de DHCP (`dynamic`), sin ningún error | El nombre de la interfaz en el YAML no existe en el equipo (p. ej. `enp0s3` en una VM de VMware) | [Corregir el nombre de la interfaz](#corregir-el-nombre-de-la-interfaz) |
| Tras reiniciar, la interfaz queda sin IP | Mismo motivo: ningún YAML configura la interfaz real | [Corregir el nombre de la interfaz](#corregir-el-nombre-de-la-interfaz) |
| `Error in network definition` | Indentación o tabuladores en el YAML | Revisa con `sudo netplan generate`; usa solo espacios |
| `Permissions ... are too open` | Archivo legible por otros | `sudo chmod 600 /etc/netplan/*.yaml` |
| La configuración vuelve a la original tras reiniciar | cloud-init regenera la red | Paso 3.3 |
| Hay IP pero no hay Internet | Gateway incorrecto | Revisa `routes:` y `ip route` |
| Hay ping a `1.1.1.1` pero no a `ubuntu.com` | DNS mal configurado | Revisa `nameservers:` y `resolvectl status` |
| Dos IPs en la interfaz | Quedó otro `.yaml` en `/etc/netplan/` | Deja solo `01-netcfg.yaml` |
| Perdí el acceso por SSH | Cambió la IP | Espera 120 s si usaste `try`, o entra por consola |

### Corregir el nombre de la interfaz

Si copiaste los archivos con un nombre que no es el de tu equipo (en el ejemplo, `enp0s3` en lugar de `enp2s0`):

```bash
# 1. Nombre real de la interfaz
ip -br link

# 2. Dónde aparece el nombre equivocado (archivo activo y perfiles)
sudo grep -rn enp0s3 /etc/netplan/

# 3. Reemplazarlo en todos los archivos
sudo grep -rl enp0s3 /etc/netplan/ | sudo xargs sed -i 's/enp0s3/enp2s0/g'

# 4. Permisos y aplicar
sudo chmod 600 /etc/netplan/*.yaml /etc/netplan/perfiles/*.yaml
sudo ip addr flush dev enp2s0
sudo netplan apply

# 5. Verificar: sin "dynamic" y con "proto static"
ip -4 addr show enp2s0
ip route | grep default
```

> Hazlo desde la consola de la VM, no por SSH: `ip addr flush` quita la IP actual y corta la sesión.

### Restaurar la configuración original

```bash
sudo rm /etc/netplan/01-netcfg.yaml
sudo cp -a /root/netplan-backup/*.yaml /etc/netplan/
sudo netplan apply
```

---

**Resumen:** comprueba primero el nombre de la interfaz con `ip -br link`; después, un solo archivo activo (`01-netcfg.yaml`), dos perfiles guardados en `/etc/netplan/perfiles/`, y `netplan try` como red de seguridad cada vez que cambias.