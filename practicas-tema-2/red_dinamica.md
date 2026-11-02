# Configurar una IP dinámica (DHCP) en Ubuntu Server

> Válido para **Ubuntu Server 22.04 LTS y 24.04 LTS**, que usan **Netplan** con el backend `systemd-networkd`.

---

## Índice

1. [¿Qué es DHCP?](#1-qué-es-dhcp)
2. [Identificar la interfaz](#2-identificar-la-interfaz)
3. [Respaldar la configuración existente](#3-respaldar-la-configuración-existente)
4. [Desactivar la red de cloud-init](#4-desactivar-la-red-de-cloud-init)
5. [Crear el archivo DHCP](#5-crear-el-archivo-dhcp)
6. [Validar y aplicar](#6-validar-y-aplicar)
7. [Verificar](#7-verificar)
8. [Renovar la IP](#8-renovar-la-ip)
9. [Variantes útiles](#9-variantes-útiles)
10. [Solución de problemas](#10-solución-de-problemas)
11. [Restaurar la configuración original](#11-restaurar-la-configuración-original)

---

## 1. ¿Qué es DHCP?

Con DHCP, el **router o servidor DHCP** de la red entrega automáticamente al equipo:

- Dirección IP y máscara
- Gateway (puerta de enlace)
- Servidores DNS
- Tiempo de concesión (*lease*): cuánto dura la asignación antes de renovarse

Es la opción más sencilla y la adecuada para equipos de prueba o redes donde la IP del servidor no necesita ser fija.

> 💡 Si necesitas que el servidor tenga **siempre la misma IP** pero quieres seguir usando DHCP, configura una **reserva DHCP** en el router usando la MAC del servidor (sección 9.1).

---

## 2. Identificar la interfaz

```bash
ip -br link
```

```
lo               UNKNOWN        00:00:00:00:00:00
enp0s3           UP             08:00:27:ab:cd:ef
```

La interfaz de este ejemplo es **`enp0s3`**. Sustitúyela por la tuya en todo el tutorial. Anota también la **MAC** (`08:00:27:ab:cd:ef`); te servirá para reservas DHCP.

---

## 3. Respaldar la configuración existente

```bash
ls -l /etc/netplan/
sudo mkdir -p /root/netplan-backup
sudo cp -a /etc/netplan/*.yaml /root/netplan-backup/
```

Retira los archivos originales para que no se mezclen con el nuevo (Netplan combina todos los `.yaml` de la carpeta):

```bash
sudo rm /etc/netplan/*.yaml
```

---

## 4. Desactivar la red de cloud-init

Si el sistema usa cloud-init, puede regenerar `50-cloud-init.yaml` al reiniciar y sobrescribir tu archivo. Desactívalo:

```bash
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```

> Si `/etc/cloud/cloud.cfg.d/` no existe, cloud-init no está instalado y puedes omitir este paso.

---

## 5. Crear el archivo DHCP

```bash
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

| Clave | Significado |
|-------|-------------|
| `renderer: networkd` | Usa `systemd-networkd` (estándar en Ubuntu Server) |
| `dhcp4: true` | Pide IPv4 por DHCP |
| `dhcp6: false` | No pide IPv6 por DHCP (cámbialo a `true` si tu red lo ofrece) |

> ⚠️ **YAML es sensible a la indentación.** Usa **espacios**, nunca tabuladores.

Permisos restringidos (Netplan advierte si el archivo es legible por otros):

```bash
sudo chmod 600 /etc/netplan/01-netcfg.yaml
```

---

## 6. Validar y aplicar

**1. Validar la sintaxis:**

```bash
sudo netplan generate
```

Si no muestra nada, el archivo es válido.

**2. Aplicar con reversión automática:**

```bash
sudo netplan try
```

Si no pulsas **Enter** en 120 segundos, los cambios se revierten solos.

> **Por SSH:** al pasar de IP estática a DHCP, el servidor puede recibir **otra IP** y tu sesión se cortará. Averigua la nueva IP en la lista de clientes DHCP del router (o por consola), vuelve a conectarte y confirma antes de 120 s.

**3. Aplicar de forma definitiva:**

```bash
sudo netplan apply
```

---

## 7. Verificar

```bash
ip -4 addr show enp0s3
```

Busca la palabra **`dynamic`** en la línea `inet`; indica que la IP vino por DHCP y muestra cuánto le queda a la concesión:

```
inet 192.168.1.87/24 metric 100 brd 192.168.1.255 scope global dynamic enp0s3
   valid_lft 86123sec preferred_lft 86123sec
```

Gateway y DNS entregados por DHCP:

```bash
ip route | grep default
resolvectl status enp0s3
```

Detalle de la concesión (servidor DHCP, tiempo, etc.):

```bash
networkctl status enp0s3
```

Prueba de conectividad por capas:

```bash
ping -c 3 "$(ip route | awk '/default/ {print $3; exit}')"   # 1. gateway
ping -c 3 1.1.1.1                                           # 2. Internet
ping -c 3 ubuntu.com                                        # 3. DNS
```

En **Ubuntu 24.04** también:

```bash
sudo netplan status
```

---

## 8. Renovar la IP

`systemd-networkd` renueva la concesión automáticamente. Para forzar una renovación inmediata:

```bash
sudo networkctl renew enp0s3
```

Para reiniciar la interfaz por completo (pide una concesión nueva):

```bash
sudo networkctl reconfigure enp0s3
```

> Por SSH, ambos comandos pueden cambiar la IP y cortar la sesión.

---

## 9. Variantes útiles

### 9.1 Reserva DHCP (IP "fija" desde el router)

Obtén la MAC de la interfaz:

```bash
cat /sys/class/net/enp0s3/address
```

En el panel del router, busca **Reserva DHCP / Static lease / Address reservation** y asocia esa MAC a la IP deseada. Luego renueva:

```bash
sudo networkctl renew enp0s3
```

Para que el servidor se identifique siempre por su MAC ante el router (evita que una VM clonada o reinstalada reciba otra IP):

```yaml
    enp0s3:
      dhcp4: true
      dhcp-identifier: mac
```

### 9.2 Usar tus propios DNS en lugar de los del DHCP

```yaml
    enp0s3:
      dhcp4: true
      dhcp4-overrides:
        use-dns: false
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
```

### 9.3 Enviar el nombre del equipo al router

Así el servidor aparece con su nombre en la lista de clientes del router:

```yaml
    enp0s3:
      dhcp4: true
      dhcp4-overrides:
        send-hostname: true
```

### 9.4 No esperar la red al arrancar

Si el servidor tiene una interfaz que a veces está desconectada, marcarla como opcional evita esperas de hasta 2 minutos en el arranque:

```yaml
    enp0s3:
      dhcp4: true
      optional: true
```

### 9.5 DHCP en varias interfaces

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s3:
      dhcp4: true
    enp0s8:
      dhcp4: true
      dhcp4-overrides:
        route-metric: 200     # ruta secundaria; enp0s3 tiene prioridad
```

---

## 10. Solución de problemas

| Síntoma | Causa probable | Solución |
|---------|----------------|----------|
| `Error in network definition` | Indentación o tabuladores | Corrige el YAML; valida con `sudo netplan generate` |
| `Permissions ... are too open` | Permisos amplios | `sudo chmod 600 /etc/netplan/*.yaml` |
| La interfaz no recibe IP | Cable/red virtual desconectada o sin servidor DHCP | `ip -br link` (debe decir `UP`); revisa el adaptador de la VM (NAT/puente) |
| Recibe una IP `169.254.x.x` | No hubo respuesta DHCP | Revisa el servidor DHCP y la conexión física |
| Aparecen dos IPs | Quedó otro `.yaml` con IP estática | Deja solo `01-netcfg.yaml` |
| La IP cambia en cada reinicio | Concesión nueva o VM clonada | Reserva DHCP + `dhcp-identifier: mac` (9.1) |
| Tras reiniciar vuelve la config anterior | cloud-init regenera la red | Sección 4 |
| Arranque lento ("waiting for network") | Interfaz sin conexión | `optional: true` (9.4) |

Revisar los registros de DHCP:

```bash
journalctl -u systemd-networkd -b --no-pager | grep -i dhcp | tail -n 20
```

---

## 11. Restaurar la configuración original

```bash
sudo rm /etc/netplan/01-netcfg.yaml
sudo cp -a /root/netplan-backup/*.yaml /etc/netplan/
sudo rm -f /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
sudo netplan apply
```

---

**Resumen:** un único archivo `/etc/netplan/01-netcfg.yaml` con `dhcp4: true`, permisos `600` y `netplan try` antes de confirmar. Si necesitas una IP que no cambie, usa una reserva DHCP en el router.