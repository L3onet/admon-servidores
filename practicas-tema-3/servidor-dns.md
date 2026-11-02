# Servidor DNS con BIND 9 en Ubuntu Server 26.04.1 LTS

> **Continuación de:** *Instalación y configuración de un servidor DHCP en Ubuntu Server 26.04.1 LTS*
> **Sistema:** Ubuntu Server **26.04.1 LTS** · BIND **9.20** · Kea **3.0**
> **Plataforma:** máquinas virtuales en Oracle VirtualBox 7.x
> **Modo de trabajo:** servidor **sin conexión a internet**
> **Nivel:** intermedio · **Duración estimada:** 90–120 min

---

## Índice

1. [Objetivo](#1-objetivo)
2. [Continuidad con la práctica de DHCP](#2-continuidad-con-la-práctica-de-dhcp)
3. [Elige tu dominio y calcula tus datos](#3-elige-tu-dominio-y-calcula-tus-datos)
4. [Instalación de BIND y desconexión de internet](#4-instalación-de-bind-y-desconexión-de-internet)
5. [Configuración de BIND](#5-configuración-de-bind)
6. [El servidor usa su propio DNS](#6-el-servidor-usa-su-propio-dns)
7. [Kea entrega el nuevo DNS a los clientes](#7-kea-entrega-el-nuevo-dns-a-los-clientes)
8. [Pruebas de funcionamiento](#8-pruebas-de-funcionamiento)
9. [Creación de evidencias](#9-creación-de-evidencias)
10. [Extra: registro automático de clientes (DDNS)](#10-extra-registro-automático-de-clientes-ddns)
11. [Solución de problemas](#11-solución-de-problemas)
12. [Rúbrica sugerida](#12-rúbrica-sugerida)

---

## 1. Objetivo

Al terminar esta práctica, el estudiante podrá:

- Instalar **BIND 9** en el mismo servidor donde ya funciona Kea DHCP.
- Crear una **zona directa** (nombre → IP) y una **zona inversa** (IP → nombre) para un dominio elegido por él.
- Configurar Kea para que los clientes reciban automáticamente **su propio DNS** y su dominio.
- Hacer que todo funcione **sin conexión a internet**.
- Dejar preparados los nombres `www`, `ftp` y `mail` para las siguientes prácticas: Web, FTP y Correo.
- Generar un paquete de evidencias verificable.

---

## 2. Continuidad con la práctica de DHCP

Partimos del servidor que ya tienes funcionando:

| Elemento                      | Valor (ejemplo con octeto 50)                      |
|-------------------------------|----------------------------------------------------|
| Nombre del servidor           | `srv-dhcp`                                         |
| Adaptador 1 (NAT, `enp0s3`)   | Internet. **En esta práctica se desconecta.**       |
| Adaptador 2 (puente, `enp0s8`) | `192.168.1.50`, para SSH desde tu equipo           |
| Adaptador 3 (puente, `enp0s9`) | `192.168.50.1`, red DHCP de Kea                   |
| Red de los clientes           | `192.168.50.0/24`, con pool `.100 – .200` y reservación `.50` |

**Lo que cambia en esta práctica:**

| Antes (práctica DHCP)                          | Después (esta práctica)                              |
|------------------------------------------------|------------------------------------------------------|
| Kea entrega DNS `1.1.1.1, 8.8.8.8`              | Kea entrega **`192.168.50.1`**, tu propio servidor DNS |
| Dominio `lab.local`                             | Tu dominio, por ejemplo **`leonel.mx`**               |
| Los clientes solo se conocen por IP             | Los clientes y servicios tienen **nombre**            |
| El servidor sale a internet por NAT             | El servidor trabaja **sin internet**                  |

```
   ┌────────────────────────────────────────────┐
   │  srv-dhcp.leonel.mx  /  ns1.leonel.mx       │
   │  Ubuntu Server 26.04.1                      │
   │  ┌──────────────┐     ┌──────────────────┐  │
   │  │ Kea DHCP     │────▶│ BIND 9 (DNS)     │  │
   │  │ "tu DNS es   │     │ zona leonel.mx   │  │
   │  │ 192.168.50.1"│     │ zona inversa .50 │  │
   │  └──────────────┘     └──────────────────┘  │
   │  enp0s9 → 192.168.50.1                      │
   └──────────────┬─────────────────────────────┘
                  │  Red DHCP 192.168.50.0/24
        ┌─────────┴─────────┐
        │ cliente-fijo      │  192.168.50.50  → "ping www.leonel.mx"
        │ clientes del pool │  192.168.50.100–200
        └───────────────────┘
```

> 💡 **¿Por qué el orden DHCP → DNS?** El DHCP les dice a los clientes *cuál* es su servidor DNS. Primero construimos la red y después le damos nombres. Al final de esta práctica, el DHCP anunciará el DNS que acabas de instalar.

---

## 3. Elige tu dominio y calcula tus datos

Cada alumno elige **su propio dominio**. En este tutorial el ejemplo es **`leonel.mx`**, pero puedes usar cualquier terminación: `.com`, `.io`, `.si`, `.net`, `.dev`, etc. Por ejemplo, `ana.io`, `equipo3.com` o `carlosr.si`.

| Dato              | Cómo se obtiene                                   | Ejemplo                     |
|-------------------|---------------------------------------------------|-----------------------------|
| `DOMINIO`         | Lo eliges tú                                       | `leonel.mx`                 |
| `OCT`             | Último octeto de tu IP del adaptador 2 (práctica DHCP) | `50`                    |
| IP del servidor   | `192.168.OCT.1`                                    | `192.168.50.1`              |
| Zona inversa      | `OCT.168.192.in-addr.arpa`                         | `50.168.192.in-addr.arpa`   |

> ⚠️ **Reglas para elegir el dominio:**
> - Como el laboratorio **no tiene internet**, tu servidor será la autoridad de ese dominio **solo dentro de tu red**. Aunque `leonel.mx` exista en internet o tenga otro dueño, en tu red mandará tu servidor. Este esquema se conoce como *split-horizon*.
> - **No uses dominios de servicios reales que necesites**, como `google.com`, `gmail.com` o el de tu escuela. Dentro de tu red los "secuestrarías" y dejarían de funcionar para tus clientes.
> - **No uses `.local`**: está reservado para mDNS (RFC 6762) y choca con systemd-resolved, Avahi, macOS e iOS.
> - Usa solo letras minúsculas, números y guiones.

Guarda tus datos en variables. Los usarás en varios comandos:

```bash
DOMINIO=leonel.mx
OCT=$(ip -4 -o addr show enp0s8 | awk '{split($4,a,"[./]"); print a[4]}')
echo "Dominio: $DOMINIO · Servidor: 192.168.${OCT}.1 · Zona inversa: ${OCT}.168.192.in-addr.arpa"
```

> Las variables se pierden al cerrar la sesión. Si abres otra terminal, vuelve a definirlas.

### 3.1 Nombres que vas a registrar

| Nombre                     | Tipo  | Apunta a          | Para qué                               |
|----------------------------|-------|-------------------|----------------------------------------|
| `leonel.mx`                | A     | `192.168.50.1`    | El dominio "pelón"                     |
| `ns1.leonel.mx`            | A     | `192.168.50.1`    | El servidor DNS (obligatorio)          |
| `srv-dhcp.leonel.mx`       | A     | `192.168.50.1`    | Nombre del servidor                    |
| `www.leonel.mx`            | CNAME | `srv-dhcp`        | Preparado para la práctica de **Web**    |
| `ftp.leonel.mx`            | CNAME | `srv-dhcp`        | Preparado para la práctica de **FTP**    |
| `mail.leonel.mx`           | A     | `192.168.50.1`    | Preparado para la práctica de **Correo** |
| `leonel.mx` → MX           | MX    | `mail.leonel.mx`  | Servidor de correo del dominio         |
| `cliente-fijo.leonel.mx`   | A     | `192.168.50.50`   | El cliente con reservación en Kea      |

> El registro MX apunta a `mail`, que es un registro **A** y no un CNAME. Los registros MX no deben apuntar a un CNAME (RFC 2181).

---

## 4. Instalación de BIND y desconexión de internet

### 4.1 Instalar los paquetes (última vez con internet)

Con el adaptador 1 (NAT) todavía conectado, instala todo lo que necesitarás en esta práctica y en el extra de DDNS:

```bash
sudo apt update
sudo apt install -y bind9 bind9-utils bind9-dnsutils kea-dhcp-ddns-server
named -v
```

Salida esperada:

```
BIND 9.20.xx-...-Ubuntu (Stable Release) ...
```

| Paquete                | Contiene                                                              |
|------------------------|-----------------------------------------------------------------------|
| `bind9`                | El servidor DNS (`named`)                                             |
| `bind9-utils`          | `named-checkconf`, `named-checkzone`, `rndc`, `tsig-keygen`           |
| `bind9-dnsutils`       | `dig`, `nslookup`, `nsupdate`                                         |
| `kea-dhcp-ddns-server` | Solo para el extra de la sección 10                                   |

> 💡 Si tus clientes Linux no tienen `dig`, instálalo ahora en cada uno con `sudo apt install -y bind9-dnsutils`, mientras todavía tengan acceso a internet. Si no, usa `resolvectl` y `nslookup`, que funcionan igual.

### 4.2 Desconectar internet

En VirtualBox, con la VM encendida, ve a **Dispositivos → Red → Adaptador de red 1** y desmarca **Conectar cable**. Para que el cambio sea permanente, apaga la VM y en **Configuración → Red → Adaptador 1 → Avanzado** desmarca **Cable conectado**.

Comprueba en el servidor:

```bash
ip -br addr show enp0s3          # Debe aparecer como DOWN o sin IP
ip route | grep default          # No debe mostrar nada
ping -c 2 -W 2 1.1.1.1           # Debe fallar: "Network is unreachable"
```

> El adaptador 2 (`192.168.1.50`) sigue funcionando para SSH. No tiene puerta de enlace, así que **no** da salida a internet.

---

## 5. Configuración de BIND

En Ubuntu 26.04 la configuración de BIND está repartida en varios archivos:

| Archivo                               | Contenido                                            |
|---------------------------------------|------------------------------------------------------|
| `/etc/bind/named.conf`                | Archivo principal: solo hace `include` de los demás  |
| `/etc/bind/named.conf.options`        | Opciones globales (aquí trabajaremos)                |
| `/etc/bind/named.conf.local`          | Declaración de **tus zonas** (aquí trabajaremos)     |
| `/var/lib/bind/db.*`                  | Archivos de zona con los registros                   |

> Guardamos las zonas en `/var/lib/bind/` porque es la carpeta donde BIND tiene permiso de escritura (por AppArmor). Así funcionará también el extra de DDNS de la sección 10 sin mover nada.

Respalda los archivos originales:

```bash
sudo cp /etc/bind/named.conf.options /etc/bind/named.conf.options.orig
sudo cp /etc/bind/named.conf.local   /etc/bind/named.conf.local.orig
```

### 5.1 Opciones globales

```bash
sudo nano /etc/bind/named.conf.options
```

```
// Red del laboratorio: solo estos equipos pueden consultar
acl "lab" {
    127.0.0.0/8;
    192.168.50.0/24;
};

options {
    directory "/var/cache/bind";

    // Escuchar SOLO en localhost y en la red DHCP (adaptador 3).
    // Nunca en enp0s8 (192.168.1.x), la red de la escuela.
    listen-on port 53 { 127.0.0.1; 192.168.50.1; };
    listen-on-v6 { none; };

    allow-query     { lab; };
    allow-recursion { lab; };
    recursion yes;

    // Nadie puede descargar la zona completa
    allow-transfer { none; };

    // Laboratorio sin internet: sin reenviadores y sin validación DNSSEC
    // (no puede descargar las llaves raíz). En producción usa "auto".
    dnssec-validation no;

    // No revelar la versión de BIND
    version "no disponible";
};
```

| Opción              | Por qué                                                                       |
|---------------------|-------------------------------------------------------------------------------|
| `listen-on`         | Igual que con Kea: el servicio solo vive en la red del laboratorio            |
| `allow-query`       | Solo responde a la red del laboratorio                                        |
| `recursion yes`     | Los clientes usan este servidor como su único DNS                             |
| `allow-transfer`    | Bloquea la descarga completa de la zona (AXFR), una fuga de información común |
| `dnssec-validation no` | Sin internet, BIND no puede actualizar las llaves raíz y llenaría el log de errores |

> Sin internet, cualquier nombre que **no** sea de tu dominio, como `google.com`, responderá **SERVFAIL**. Es el comportamiento esperado y lo usaremos como prueba.

### 5.2 Declarar las zonas

```bash
sudo nano /etc/bind/named.conf.local
```

```
// Zona directa: nombre -> IP
zone "leonel.mx" {
    type primary;
    file "/var/lib/bind/db.leonel.mx";
};

// Zona inversa: IP -> nombre (red 192.168.50.0/24)
zone "50.168.192.in-addr.arpa" {
    type primary;
    file "/var/lib/bind/db.50.168.192.in-addr.arpa";
};
```

> BIND 9.20 usa `type primary`. La forma antigua, `type master`, aún se acepta, pero es obsoleta.

### 5.3 Zona directa

```bash
sudo nano /var/lib/bind/db.leonel.mx
```

```
$TTL 3600
@       IN  SOA ns1.leonel.mx. admin.leonel.mx. (
                2026102601  ; Serial (AAAAMMDDNN): súbelo en cada cambio
                3600        ; Refresh
                900         ; Retry
                604800      ; Expire
                300 )       ; TTL negativo

; Servidor de nombres y de correo del dominio
@               IN  NS      ns1.leonel.mx.
@               IN  MX  10  mail.leonel.mx.

; Registros A
@               IN  A       192.168.50.1
ns1             IN  A       192.168.50.1
srv-dhcp        IN  A       192.168.50.1
mail            IN  A       192.168.50.1
cliente-fijo    IN  A       192.168.50.50

; Alias para las siguientes prácticas
www             IN  CNAME   srv-dhcp
ftp             IN  CNAME   srv-dhcp
```

**Cómo leer el archivo:**

- `@` significa "el dominio mismo" (`leonel.mx.`).
- Los nombres **sin punto final** se completan con el dominio: `www` se vuelve `www.leonel.mx.`.
- Los nombres **con punto final** son absolutos: `ns1.leonel.mx.`. Olvidar ese punto es el error más común, porque convierte el nombre en `ns1.leonel.mx.leonel.mx.`.
- `admin.leonel.mx.` es el correo del responsable (`admin@leonel.mx`), escrito con punto en lugar de `@`.
- El **serial** debe aumentar cada vez que cambies la zona. Así los clientes y los servidores secundarios saben que hay datos nuevos.

### 5.4 Zona inversa

```bash
sudo nano /var/lib/bind/db.50.168.192.in-addr.arpa
```

```
$TTL 3600
@       IN  SOA ns1.leonel.mx. admin.leonel.mx. (
                2026102601  ; Serial
                3600        ; Refresh
                900         ; Retry
                604800      ; Expire
                300 )       ; TTL negativo

@       IN  NS      ns1.leonel.mx.

; Último octeto de la IP -> nombre completo (con punto final)
1       IN  PTR     srv-dhcp.leonel.mx.
50      IN  PTR     cliente-fijo.leonel.mx.
```

> En la zona inversa la IP se escribe **al revés** (`50.168.192`). Cada registro usa solo el último octeto: `1` equivale a `192.168.50.1`.

### 5.5 Adaptar a tu dominio y a tu octeto

Si tu dominio **no** es `leonel.mx` o tu octeto **no** es `50`, este bloque cambia los tres archivos y renombra las zonas de una sola vez. Antes debes haber definido las variables de la sección 3.

```bash
cd /var/lib/bind
sudo sed -i \
  -e "s/leonel\.mx/${DOMINIO}/g" \
  -e "s/192\.168\.50\./192.168.${OCT}./g" \
  -e "s/50\.168\.192/${OCT}.168.192/g" \
  /etc/bind/named.conf.options /etc/bind/named.conf.local \
  db.leonel.mx db.50.168.192.in-addr.arpa
[ "$DOMINIO" != "leonel.mx" ] && sudo mv db.leonel.mx "db.${DOMINIO}"
[ "$OCT" != "50" ] && sudo mv db.50.168.192.in-addr.arpa "db.${OCT}.168.192.in-addr.arpa"
ls /var/lib/bind/
grep -n "zone\|file" /etc/bind/named.conf.local
```

### 5.6 Permisos y validación

```bash
sudo chown bind:bind /var/lib/bind/db.*
sudo chmod 644 /var/lib/bind/db.*

# 1) Sintaxis de named.conf y de todas las zonas
sudo named-checkconf -z

# 2) Cada zona por separado
sudo named-checkzone "${DOMINIO}" "/var/lib/bind/db.${DOMINIO}"
sudo named-checkzone "${OCT}.168.192.in-addr.arpa" "/var/lib/bind/db.${OCT}.168.192.in-addr.arpa"
```

Salida esperada:

```
zone leonel.mx/IN: loaded serial 2026102601
zone 50.168.192.in-addr.arpa/IN: loaded serial 2026102601
OK
```

> `named-checkconf` no imprime nada cuando todo está bien. Si muestra un mensaje, léelo: indica el archivo y la línea del error.

### 5.7 Iniciar el servicio

En Ubuntu 26.04 el servicio se llama **`named`**. `bind9` es solo un alias.

```bash
sudo systemctl enable named
sudo systemctl restart named
sudo systemctl status named --no-pager
sudo rndc status | head -n 8
sudo ss -tulnp | grep ':53 '
```

En la salida de `ss` debe aparecer `named` escuchando en `127.0.0.1:53` y en `192.168.50.1:53`, por **UDP y TCP**, y **no** en `192.168.1.50`.

> También verás `127.0.0.53` y `127.0.0.54`: son de `systemd-resolved` y conviven sin problema con BIND.

### 5.8 Firewall (si UFW está activo)

```bash
sudo ufw allow in on enp0s9 to any port 53 proto udp comment 'DNS'
sudo ufw allow in on enp0s9 to any port 53 proto tcp comment 'DNS'
```

---

## 6. El servidor usa su propio DNS

Hasta ahora, el servidor resolvía nombres con el DNS que le daba la NAT. Ahora debe consultarse a sí mismo. Agrega `nameservers` a la interfaz `enp0s9` en el archivo de Netplan de la práctica anterior:

```bash
sudo nano /etc/netplan/60-lab-dhcp.yaml
```

```yaml
network:
  version: 2
  ethernets:
    enp0s3:              # Adaptador 1 - NAT (desconectado en esta práctica)
      dhcp4: true
    enp0s8:              # Adaptador 2 - Puente: red de prácticas 192.168.1.0/24
      dhcp4: false
      addresses:
        - 192.168.1.50/24
    enp0s9:              # Adaptador 3 - Puente: red DHCP y DNS del laboratorio
      dhcp4: false
      addresses:
        - 192.168.50.1/24
      nameservers:
        addresses: [192.168.50.1]
        search: [leonel.mx]
```

```bash
sudo sed -i -e "s/search: \[leonel\.mx\]/search: [${DOMINIO}]/" \
            -e "s/192\.168\.50\./192.168.${OCT}./g" /etc/netplan/60-lab-dhcp.yaml
grep -nE "addresses|search" -A1 /etc/netplan/60-lab-dhcp.yaml
sudo netplan apply
resolvectl status enp0s9 | grep -E 'DNS Servers|DNS Domain'
resolvectl query ns1           # Nombre corto: se completa con tu dominio
```

---

## 7. Kea entrega el nuevo DNS a los clientes

Este es el punto de unión entre las dos prácticas. Kea dejará de anunciar `1.1.1.1` y `8.8.8.8` y anunciará **tu** servidor DNS y **tu** dominio.

### 7.1 Cambiar las opciones globales de Kea

```bash
sudo cp /etc/kea/kea-dhcp4.conf /etc/kea/kea-dhcp4.conf.antes-dns
sudo nano /etc/kea/kea-dhcp4.conf
```

**Antes** (práctica DHCP):

```
    "option-data": [
      { "name": "domain-name-servers", "data": "1.1.1.1, 8.8.8.8" },
      { "name": "domain-name",         "data": "lab.local" }
    ],
```

**Después** (esta práctica):

```
    "option-data": [
      { "name": "domain-name-servers", "data": "192.168.50.1" },
      { "name": "domain-name",         "data": "leonel.mx" },
      { "name": "domain-search",       "data": "leonel.mx" }
    ],
```

| Opción                | Código | Qué hace en el cliente                                        |
|-----------------------|:------:|---------------------------------------------------------------|
| `domain-name-servers` | 6      | El cliente usará tu BIND como DNS                              |
| `domain-name`         | 15     | Dominio del cliente (Windows lo usa como sufijo DNS)           |
| `domain-search`       | 119    | Lista de búsqueda: permite escribir `ping www` en vez de `ping www.leonel.mx` |

Si tu dominio no es `leonel.mx` o tu octeto no es `50`, ajústalos. Después valida y recarga **sin reiniciar** el servicio:

```bash
sudo sed -i -e "s/\"leonel\.mx\"/\"${DOMINIO}\"/g" \
            -e "s/192\.168\.50\./192.168.${OCT}./g" /etc/kea/kea-dhcp4.conf
grep -nE "domain-" /etc/kea/kea-dhcp4.conf
sudo kea-dhcp4 -t /etc/kea/kea-dhcp4.conf && \
echo '{ "command": "config-reload" }' | sudo socat - UNIX-CONNECT:/run/kea/kea4-ctrl-socket
```

✅ La respuesta debe contener `"result": 0`.

### 7.2 Cliente Linux: aceptar el dominio que envía el DHCP

Por defecto, Netplan con systemd-networkd **acepta el DNS** que envía el DHCP, pero **ignora el dominio de búsqueda**. Habilítalo en el cliente:

```bash
sudo nano /etc/netplan/50-cloud-init.yaml      # o el archivo que uses en el cliente
```

```yaml
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: true
      dhcp4-overrides:
        use-domains: true
```

```bash
sudo chmod 600 /etc/netplan/*.yaml
sudo netplan apply
sudo networkctl renew enp0s3
resolvectl status enp0s3 | grep -E 'DNS Servers|DNS Domain'
```

Salida esperada:

```
       DNS Servers: 192.168.50.1
        DNS Domain: leonel.mx
```

> Si en la práctica de DHCP aplicaste el filtro `AllowList` (opción B), se mantiene igual.

### 7.3 Cliente Windows

Windows aplica el DNS y el sufijo automáticamente al renovar:

```powershell
ipconfig /release
ipconfig /renew
ipconfig /all | findstr /i "DNS Sufijo Suffix"
```

Debes ver `Servidores DNS: 192.168.50.1` y `Sufijo DNS específico para la conexión: leonel.mx`.

---

## 8. Pruebas de funcionamiento

Antes de empezar, activa el **registro de consultas**. Así cada prueba queda anotada en el log y te sirve como evidencia:

```bash
sudo rndc querylog on
```

### Prueba 1 – Resolución directa desde el servidor

```bash
dig @192.168.50.1 www.leonel.mx
dig @192.168.50.1 ns1.leonel.mx +short
dig @192.168.50.1 cliente-fijo.leonel.mx +short
```

✅ **Éxito:**
- `status: NOERROR`.
- La bandera **`aa`** (*authoritative answer*) aparece en `flags`.
- `www` muestra el CNAME hacia `srv-dhcp.leonel.mx.` y luego su A `192.168.50.1`.

### Prueba 2 – Registros SOA, NS y MX

```bash
dig @192.168.50.1 leonel.mx SOA +noall +answer
dig @192.168.50.1 leonel.mx NS  +noall +answer
dig @192.168.50.1 leonel.mx MX  +noall +answer
```

✅ **Éxito:** el SOA muestra tu serial, el NS es `ns1.leonel.mx.` y el MX es `10 mail.leonel.mx.`.

### Prueba 3 – Resolución inversa

```bash
dig @192.168.50.1 -x 192.168.50.1  +short
dig @192.168.50.1 -x 192.168.50.50 +short
```

✅ **Éxito:** responde `srv-dhcp.leonel.mx.` y `cliente-fijo.leonel.mx.`.

### Prueba 4 – Seguridad de la configuración

```bash
# Transferencia de zona: debe ser rechazada
dig @192.168.50.1 leonel.mx AXFR

# Versión oculta
dig @192.168.50.1 version.bind CH TXT +short

# BIND no debe responder en la red de la escuela (adaptador 2)
dig @192.168.1.50 www.leonel.mx +time=2 +tries=1
```

✅ **Éxito:**
- AXFR responde `Transfer failed.`
- La versión muestra `"no disponible"`.
- La consulta a `192.168.1.50` termina en `connection refused` o en *timed out*.

### Prueba 5 – Sin internet: nombres externos fallan

```bash
dig @192.168.50.1 google.com +time=3 +tries=1
```

✅ **Éxito:** `status: SERVFAIL`. Esto demuestra que el servidor está aislado y que **solo** resuelve tu dominio.

### Prueba 6 – Cliente Linux (DNS entregado por Kea)

```bash
resolvectl status enp0s3 | grep -E 'DNS Servers|DNS Domain'
resolvectl query www.leonel.mx
resolvectl query www                      # Nombre corto, gracias a domain-search
resolvectl query 192.168.50.1             # Inversa
getent hosts ftp.leonel.mx
ping -c 2 srv-dhcp
ping -c 2 www.leonel.mx
```

Si instalaste `dig` en el cliente:

```bash
dig www.leonel.mx                         # Sin @: usa el DNS que dio Kea
```

✅ **Éxito:**
- El DNS es `192.168.50.1` y el dominio es `leonel.mx`.
- Los nombres cortos y largos resuelven.
- `ping` responde desde `192.168.50.1`.

### Prueba 7 – Cliente Windows

```powershell
nslookup www.leonel.mx
nslookup -type=mx leonel.mx
nslookup 192.168.50.1
ping srv-dhcp
ping -a 192.168.50.50
```

✅ **Éxito:**
- `nslookup` muestra `Servidor: srv-dhcp.leonel.mx` y `Address: 192.168.50.1`.
- `ping srv-dhcp` resuelve a `srv-dhcp.leonel.mx`.

### Prueba 8 – Registro de consultas en el servidor

```bash
sudo journalctl -u named --since "15 min ago" --no-pager | grep 'query:' | tail -n 20
```

✅ **Éxito:** aparecen líneas como `client @0x... 192.168.50.50#41234 (www.leonel.mx): query: www.leonel.mx IN A +E(0)K (192.168.50.1)`, con la IP del cliente que preguntó.

### Prueba 9 – Captura del tráfico DNS

```bash
sudo tcpdump -i enp0s9 -n 'port 53' -w ~/evidencias/dns.pcap
# En el cliente: resolvectl flush-caches; resolvectl query www.leonel.mx
# Ctrl+C en el servidor
sudo tcpdump -n -r ~/evidencias/dns.pcap | head
```

✅ **Éxito:** se ven pares pregunta/respuesta, por ejemplo `A? www.leonel.mx.` → `CNAME srv-dhcp.leonel.mx., A 192.168.50.1`.

> 💡 En Wireshark, el filtro `dns` muestra cada consulta con su respuesta. También puedes abrir la captura de DHCP de la práctica anterior, buscar el ACK y ver en la **opción 6** la IP de tu nuevo DNS.

### Prueba 10 – Cambiar un registro y subir el serial

1. Edita `/var/lib/bind/db.leonel.mx`, agrega `prueba IN A 192.168.50.99` y sube el serial a `2026102602`.
2. Valida y recarga **solo esa zona**:

```bash
sudo named-checkzone "${DOMINIO}" "/var/lib/bind/db.${DOMINIO}"
sudo rndc reload "${DOMINIO}"
dig @192.168.50.1 prueba.leonel.mx +short
dig @192.168.50.1 leonel.mx SOA +short
```

✅ **Éxito:** `prueba` resuelve y el SOA muestra el serial nuevo.

---

## 9. Creación de evidencias

### 9.1 Script de recolección

```bash
nano ~/evidencias_dns.sh
```

```bash
#!/usr/bin/env bash
# Recolector de evidencias - Servidor DNS BIND 9 (Ubuntu 26.04.1 LTS)
# Uso: sudo ./evidencias_dns.sh <dominio> <octeto> "<Nombre del alumno>"

set -uo pipefail

DOMINIO="${1:-leonel.mx}"
OCT="${2:-50}"
ALUMNO="${3:-Sin nombre}"
IFACE="${IFACE:-enp0s9}"
IP="192.168.${OCT}.1"
INV="${OCT}.168.192.in-addr.arpa"
FECHA="$(date +%Y%m%d_%H%M%S)"
DIR="evidencias_dns_${FECHA}"

if [[ $EUID -ne 0 ]]; then
  echo "Ejecuta con sudo." >&2
  exit 1
fi

mkdir -p "$DIR"

# Ejecuta un comando, guarda la salida con encabezado y la muestra en pantalla.
ev() {
  local archivo="$1"; shift
  {
    echo "=================================================="
    echo " Evidencia : $archivo"
    echo " Alumno    : $ALUMNO"
    echo " Dominio   : $DOMINIO"
    echo " Host      : $(hostname)"
    echo " Fecha     : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo " Comando   : $*"
    echo "=================================================="
    bash -c "$*" 2>&1
    echo
  } | tee "$DIR/$archivo"
}

rndc querylog on >/dev/null 2>&1

ev 01_sistema.txt           "cat /etc/os-release; uname -a; hostnamectl"
ev 02_red.txt               "ip -br addr; ip route; resolvectl status"
ev 03_paquetes.txt          "named -v; dpkg -l | grep -E 'bind9|kea'"
ev 04_validacion.txt        "named-checkconf -z && echo 'RESULTADO: configuracion valida'"
ev 05_configuracion.txt     "cat /etc/bind/named.conf.options /etc/bind/named.conf.local"
ev 06_zonas.txt             "cat /var/lib/bind/db.${DOMINIO} /var/lib/bind/db.${INV}"
ev 07_servicio.txt          "systemctl is-enabled named; systemctl status named --no-pager; rndc status"
ev 08_puerto_53.txt         "ss -tulnp | grep ':53 '"
ev 09_consultas_directas.txt "for r in ns1 srv-dhcp www ftp mail cliente-fijo; do dig @${IP} \${r}.${DOMINIO} +noall +answer; done"
ev 10_soa_ns_mx.txt         "dig @${IP} ${DOMINIO} SOA +noall +answer; dig @${IP} ${DOMINIO} NS +noall +answer; dig @${IP} ${DOMINIO} MX +noall +answer"
ev 11_consultas_inversas.txt "dig @${IP} -x ${IP} +noall +answer; dig @${IP} -x 192.168.${OCT}.50 +noall +answer"
ev 12_seguridad.txt         "dig @${IP} ${DOMINIO} AXFR; dig @${IP} version.bind CH TXT +short; dig @${IP} google.com +time=2 +tries=1 | grep status"
ev 13_kea_opciones_dns.txt  "grep -nE 'domain-name-servers|domain-name|domain-search' /etc/kea/kea-dhcp4.conf"

echo ">>> Capturando tráfico DNS durante 60 s en $IFACE. Haz consultas desde el cliente AHORA..."
timeout 60 tcpdump -i "$IFACE" -n 'port 53' -w "$DIR/14_dns.pcap" 2>/dev/null
ev 14_dns_resumen.txt       "tcpdump -n -r $DIR/14_dns.pcap 2>/dev/null | head -n 60"
ev 15_registro_consultas.txt "journalctl -u named --since '2 hours ago' --no-pager | grep -E 'query:|loaded serial' | tail -n 100"

# Integridad y empaquetado
( cd "$DIR" && sha256sum * > SHA256SUMS.txt )
tar -czf "${DIR}.tar.gz" "$DIR"
sha256sum "${DIR}.tar.gz" | tee "${DIR}.tar.gz.sha256"

echo
echo "✅ Evidencias generadas en: $DIR/"
echo "✅ Paquete: ${DIR}.tar.gz"
```

```bash
chmod +x ~/evidencias_dns.sh
sudo ~/evidencias_dns.sh "$DOMINIO" "$OCT" "Nombre Apellido"
```

Mientras corren los 60 segundos de captura, ve al cliente y ejecuta `resolvectl flush-caches; resolvectl query www.leonel.mx` (Linux) o `nslookup www.leonel.mx` (Windows).

### 9.2 Evidencias del cliente

**Linux:**

```bash
{
  echo "Alumno: Nombre Apellido | Fecha: $(date)"
  hostnamectl
  ip -br addr
  resolvectl status enp0s3
  resolvectl query www.leonel.mx
  resolvectl query www
  resolvectl query 192.168.50.1
  ping -c 2 srv-dhcp
} 2>&1 | tee evidencia_dns_cliente_$(hostname)_$(date +%Y%m%d_%H%M).txt
```

**Windows (PowerShell):**

```powershell
$f = "evidencia_dns_cliente_$env:COMPUTERNAME_$(Get-Date -f yyyyMMdd_HHmm).txt"
"Alumno: Nombre Apellido | Fecha: $(Get-Date)" | Out-File $f
ipconfig /all | Out-File $f -Append
nslookup www.leonel.mx 2>&1 | Out-File $f -Append
nslookup -type=mx leonel.mx 2>&1 | Out-File $f -Append
Resolve-DnsName srv-dhcp | Out-File $f -Append
```

### 9.3 Capturas de pantalla recomendadas

1. `named-checkconf -z` con las dos zonas cargadas.
2. `dig www.leonel.mx` mostrando `NOERROR` y la bandera `aa`.
3. El cliente con `DNS Servers: 192.168.50.1` y `DNS Domain: leonel.mx`.
4. `ping www` desde el cliente, resolviendo con nombre corto.
5. El AXFR rechazado y `google.com` con `SERVFAIL`.

Para verificar la integridad del paquete, igual que en la práctica de DHCP:

```bash
sha256sum -c evidencias_dns_*.tar.gz.sha256
```

---

## 10. Extra: registro automático de clientes (DDNS)

Hasta ahora solo `cliente-fijo` tiene nombre. Los clientes del pool (`.100 – .200`) no aparecen en el DNS. Con **DDNS**, cada vez que Kea entrega una IP, avisa a BIND y este crea automáticamente los registros A y PTR del cliente. Es la integración completa entre DHCP y DNS.

```
 Cliente ──DHCP──▶ kea-dhcp4 ──(127.0.0.1:53001)──▶ kea-dhcp-ddns ──(DNS UPDATE + TSIG)──▶ BIND
                                                                                   crea A y PTR
```

### 10.1 Crear la llave compartida (TSIG)

Kea y BIND se autentican con una llave secreta:

```bash
sudo tsig-keygen -a hmac-sha256 kea-ddns | sudo tee /etc/bind/kea-ddns.key > /dev/null
sudo chown root:bind /etc/bind/kea-ddns.key
sudo chmod 640 /etc/bind/kea-ddns.key
sudo cat /etc/bind/kea-ddns.key
```

### 10.2 Permitir actualizaciones en BIND

Reemplaza `/etc/bind/named.conf.local`:

```
include "/etc/bind/kea-ddns.key";

zone "leonel.mx" {
    type primary;
    file "/var/lib/bind/db.leonel.mx";
    update-policy { grant kea-ddns zonesub ANY; };
};

zone "50.168.192.in-addr.arpa" {
    type primary;
    file "/var/lib/bind/db.50.168.192.in-addr.arpa";
    update-policy { grant kea-ddns zonesub ANY; };
};
```

```bash
sudo sed -i -e "s/leonel\.mx/${DOMINIO}/g" -e "s/50\.168\.192/${OCT}.168.192/g" /etc/bind/named.conf.local
sudo named-checkconf -z && sudo systemctl restart named
```

> ⚠️ **Conflicto con `cliente-fijo`:** Kea también intentará registrar `cliente-fijo`, pero ya existe como registro estático, así que BIND rechazará la actualización. Para evitarlo, borra las líneas de `cliente-fijo` de **ambas** zonas (A y PTR), sube el serial y deja que DDNS las cree.

> ⚠️ **Zonas dinámicas:** desde ahora BIND también escribe en las zonas (archivos `.jnl`). Para editarlas a mano, primero ejecuta `sudo rndc freeze ${DOMINIO}`, luego edita y sube el serial, y al final ejecuta `sudo rndc thaw ${DOMINIO}`.

### 10.3 Configurar `kea-dhcp-ddns`

```bash
sudo cp /etc/kea/kea-dhcp-ddns.conf /etc/kea/kea-dhcp-ddns.conf.orig
sudo nano /etc/kea/kea-dhcp-ddns.conf
```

```json
{
  "DhcpDdns": {
    "ip-address": "127.0.0.1",
    "port": 53001,

    "control-socket": {
      "socket-type": "unix",
      "socket-name": "/run/kea/kea-ddns-ctrl-socket"
    },

    "tsig-keys": [
      {
        "name": "kea-ddns",
        "algorithm": "HMAC-SHA256",
        "secret": "PEGA_AQUI_EL_SECRET"
      }
    ],

    "forward-ddns": {
      "ddns-domains": [
        {
          "name": "leonel.mx.",
          "key-name": "kea-ddns",
          "dns-servers": [ { "ip-address": "127.0.0.1", "port": 53 } ]
        }
      ]
    },

    "reverse-ddns": {
      "ddns-domains": [
        {
          "name": "50.168.192.in-addr.arpa.",
          "key-name": "kea-ddns",
          "dns-servers": [ { "ip-address": "127.0.0.1", "port": 53 } ]
        }
      ]
    },

    "loggers": [
      {
        "name": "kea-dhcp-ddns",
        "output-options": [ { "output": "/var/log/kea/kea-dhcp-ddns.log" } ],
        "severity": "INFO"
      }
    ]
  }
}
```

Copia el secreto de la llave al archivo, ajusta el dominio y el octeto, y protege el archivo:

```bash
SECRET=$(sudo awk -F'"' '/secret/{print $2}' /etc/bind/kea-ddns.key)
sudo sed -i -e "s|PEGA_AQUI_EL_SECRET|${SECRET}|" \
            -e "s/leonel\.mx/${DOMINIO}/g" -e "s/50\.168\.192/${OCT}.168.192/g" \
            /etc/kea/kea-dhcp-ddns.conf
sudo chown root:_kea /etc/kea/kea-dhcp-ddns.conf
sudo chmod 640 /etc/kea/kea-dhcp-ddns.conf
sudo kea-dhcp-ddns -t /etc/kea/kea-dhcp-ddns.conf && echo "DDNS: configuración válida"
sudo systemctl enable --now kea-dhcp-ddns-server
```

### 10.4 Activar DDNS en `kea-dhcp4`

Agrega estas líneas en `/etc/kea/kea-dhcp4.conf`, justo después de `"authoritative": false,`:

```
    "dhcp-ddns": { "enable-updates": true },
    "ddns-send-updates": true,
    "ddns-qualifying-suffix": "leonel.mx.",
    "ddns-override-client-update": true,
    "ddns-replace-client-name": "when-not-present",
    "ddns-generated-prefix": "cliente",
```

| Parámetro                      | Qué hace                                                                 |
|--------------------------------|--------------------------------------------------------------------------|
| `ddns-qualifying-suffix`       | Se agrega al hostname del cliente: `ubuntu-cli` → `ubuntu-cli.leonel.mx.` |
| `ddns-override-client-update`  | El servidor registra el nombre aunque el cliente pida hacerlo él mismo    |
| `ddns-replace-client-name`     | Si el cliente no envía hostname, genera uno: `cliente-192-168-50-101`     |

```bash
sudo sed -i "s/\"leonel\.mx\.\"/\"${DOMINIO}.\"/" /etc/kea/kea-dhcp4.conf
sudo kea-dhcp4 -t /etc/kea/kea-dhcp4.conf && sudo systemctl restart kea-dhcp4-server
```

### 10.5 Probar DDNS

En un cliente del pool, renueva la IP con `sudo networkctl renew enp0s3`. Después, en el servidor:

```bash
sudo tail -n 20 /var/log/kea/kea-dhcp-ddns.log | grep -E 'DHCP_DDNS_ADD_SUCCEEDED|FAILED'
dig @192.168.50.1 NOMBRE_DEL_CLIENTE.${DOMINIO} +short
dig @192.168.50.1 -x 192.168.50.101 +short
```

> Sustituye `NOMBRE_DEL_CLIENTE` por el hostname del cliente (`hostnamectl` en el cliente) y `.101` por la IP que recibió.

✅ **Éxito:**
- El log muestra `DHCP_DDNS_ADD_SUCCEEDED`.
- El nombre del cliente resuelve a su IP, y su IP resuelve a su nombre.

También puedes probar las actualizaciones a mano con la misma llave:

```bash
sudo nsupdate -k /etc/bind/kea-ddns.key <<EOF
server 127.0.0.1
zone ${DOMINIO}
update add manual.${DOMINIO}. 300 A 192.168.${OCT}.98
send
EOF
dig @127.0.0.1 manual.${DOMINIO} +short
```

---

## 11. Solución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| `named` no arranca | Error de sintaxis | `sudo named-checkconf -z` indica el archivo y la línea. Revisa los `;` y las llaves `{ }` |
| `zone ...: not loaded due to errors` | Error en el archivo de zona | `sudo named-checkzone dominio archivo` |
| `www.leonel.mx.leonel.mx` en las respuestas | Falta el **punto final** en un nombre absoluto | Escribe `ns1.leonel.mx.`, con punto final, en SOA, NS, MX y PTR |
| Cambié la zona y no se nota | No subiste el serial o no recargaste | Sube el serial y ejecuta `sudo rndc reload dominio` |
| `permission denied` al cargar la zona | Dueño o permisos incorrectos | `sudo chown bind:bind /var/lib/bind/db.*` |
| El cliente sigue con DNS `1.1.1.1` | Kea no se recargó o el cliente no renovó | `config-reload` en Kea y `networkctl renew` en el cliente |
| `resolvectl query www` falla, pero el nombre completo funciona | El cliente ignora el dominio de búsqueda | Agrega `use-domains: true` en el Netplan del cliente (sección 7.2) |
| `REFUSED` desde el cliente | El cliente no está en `acl "lab"` | Revisa que la red de la ACL sea tu `192.168.OCT.0/24` |
| `connection refused` desde el cliente | BIND no escucha en `192.168.OCT.1` | Revisa `listen-on` y `ss -tulnp | grep :53` |
| `google.com` da SERVFAIL | Es lo esperado: el servidor no tiene internet | — |
| DDNS: `DHCP_DDNS_..._FAILED` / `REFUSED` | La llave TSIG no coincide o falta `update-policy` | Compara el secreto de `/etc/bind/kea-ddns.key` con el de `kea-dhcp-ddns.conf` |
| DDNS: `YXDOMAIN` / conflicto | El nombre ya existe como registro estático | Borra el registro estático (sección 10.2) |
| `journal out of sync with zone` | Se editó una zona dinámica sin `rndc freeze` | `rndc freeze` → corrige y sube el serial → `rndc thaw` |

---

## 12. Rúbrica sugerida

| Criterio                                                         | Puntos |
|------------------------------------------------------------------|:------:|
| BIND instalado; servidor trabajando sin internet                  | 10     |
| `named.conf.options` seguro (listen-on, ACL, sin AXFR)            | 10     |
| Zona directa correcta (SOA, NS, A, CNAME, MX)                     | 15     |
| Zona inversa correcta (PTR)                                       | 10     |
| Validación con `named-checkconf -z` sin errores                   | 5      |
| **Continuidad:** Kea entrega el DNS y el dominio nuevos           | 15     |
| Clientes Linux y Windows resuelven nombres cortos y completos     | 15     |
| Paquete de evidencias con hashes verificables                     | 10     |
| Reporte: diferencia entre zona directa e inversa, y qué es autoritativo | 10 |
| **Extra (DDNS):** clientes del pool registrados automáticamente   | +10    |
| **Total**                                                        | **100 (+10)** |

---

### Referencias

- BIND 9 Administrator Reference Manual: <https://bind9.readthedocs.io/>
- Ubuntu Server docs – *Domain Name Service (DNS)*: <https://documentation.ubuntu.com/server/how-to/networking/install-dns/>
- Kea ARM – *The DHCP-DDNS Server*: <https://kea.readthedocs.io/en/latest/arm/ddns.html>
- RFC 1035 (DNS), RFC 2181 (aclaraciones), RFC 6762 (mDNS y `.local`)