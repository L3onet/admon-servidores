# Prácticas de Ubuntu Server

Guías prácticas de administración de **Ubuntu Server** (principalmente 26.04.1 LTS) y scripts para evaluar automáticamente la configuración del servidor.

## Contenido

- [Estructura del repositorio](#estructura-del-repositorio)
- [Prácticas del tema 2](#prácticas-del-tema-2)
- [Prácticas del tema 3](#prácticas-del-tema-3)
- [Archivos de configuración](#archivos-de-configuración)
  - [Convenciones](#convenciones)
  - [Variantes de un mismo archivo](#variantes-de-un-mismo-archivo)
  - [Archivos por práctica](#archivos-por-práctica)
  - [Cómo usarlos](#cómo-usarlos)
- [Scripts de evaluación del tema 2](#scripts-de-evaluación-del-tema-2)
  - [Requisitos](#requisitos)
  - [Copiar los scripts al servidor](#copiar-los-scripts-al-servidor)
  - [Uso general](#uso-general)
  - [Apartados y puntuación](#apartados-y-puntuación)
  - [Detalle de cada script](#detalle-de-cada-script)
  - [Interpretar el resultado](#interpretar-el-resultado)

---

## Estructura del repositorio

```text
.
├── practicas-tema-2/   # Red, paquetes, SSH, impresoras, usuarios/Samba/UFW/VNC
├── practicas-tema-3/   # Servicios de red: DHCP, DNS, Web, SFTP y correo
├── configuracion/      # Archivos de configuración extraídos de las prácticas, en su ruta real
└── scripts-tema-2/     # Scripts de evaluación automática (apartados A–H)
```

---

## Prácticas del tema 2

Configuración base del servidor: red, software, acceso remoto y servicios para el laboratorio.

| Guía | Contenido |
|------|-----------|
| [red_estatica.md](practicas-tema-2/red_estatica.md) | IP estática con Netplan: identificar la interfaz, respaldo, desactivar la red de cloud-init, validar con `netplan try`, variantes (varias IPs, IPv6, por MAC) y restauración. |
| [red_dinamica.md](practicas-tema-2/red_dinamica.md) | IP dinámica (DHCP) con Netplan: renovación de la IP, reserva DHCP, DNS propios, envío del nombre del equipo y solución de problemas. |
| [red_estatica_dinamica.md](practicas-tema-2/red_estatica_dinamica.md) | Ambos modos y cómo alternar entre ellos con perfiles de Netplan y un script de un solo comando. |
| [red_dinamica_virtual_host-only.md](practicas-tema-2/red_dinamica_virtual_host-only.md) | DHCP en VirtualBox 7.x con adaptador **Solo-Anfitrión**, pruebas desde el anfitrión, SSH y la configuración recomendada **NAT + Solo-Anfitrión**. |
| [gestor_paquetes.md](practicas-tema-2/gestor_paquetes.md) | APT, dpkg y Snap: actualizar, buscar, instalar y desinstalar, dependencias, historial, respaldar la lista de paquetes, congelar versiones (*hold*, *pinning*) y uso no interactivo en scripts. |
| [ssh.md](practicas-tema-2/ssh.md) | OpenSSH 10.2 en 26.04.1: instalación, llaves y `ssh-agent`, endurecimiento de `sshd`, aplicar cambios sin quedarse fuera, cambio de puerto con *socket activation* y firewall. |
| [impresora.md](practicas-tema-2/impresora.md) | CUPS: impresora USB y TCP/IP, administración de colas y trabajos, compartición con Samba y paquete de evidencias. |
| [practica_usuarios_tema3.md](practicas-tema-2/practica_usuarios_tema3.md) | Usuarios y grupos (`profe1`, `alumno1`, `alumno2`), recursos Samba con permisos por grupo, firewall UFW por equipo y escritorio remoto VNC para el docente. |

Las dos últimas prácticas, junto con la de SSH, son las que verifican los [scripts de evaluación](#scripts-de-evaluación-del-tema-2).

**Escenario de ejemplo** (prácticas de usuarios e impresoras):

| Elemento | Valor |
|----------|-------|
| Servidor | `servidor-lab`, IP fija `192.168.1.50` |
| Red local | `192.168.1.0/24` |
| Cliente autorizado (docente) | `192.168.1.60` |
| Cliente no autorizado (prueba) | `192.168.1.70` |
| Impresora TCP/IP | `192.168.1.80`, cola `Red_Lab` |
| Impresora USB | cola `USB_Lab` |

---

## Prácticas del tema 3

Servicios de red sobre Ubuntu Server 26.04.1 LTS. Las prácticas son **continuas**: cada una se apoya en la anterior y se realizan en el mismo servidor, con el dominio de ejemplo `leonel.mx`. Se recomienda seguir este orden:

| # | Guía | Servicio | Contenido |
|---|------|----------|-----------|
| 1 | [servidor-dhcp.md](practicas-tema-3/servidor-dhcp.md) | **Kea DHCPv4** | Tres adaptadores en VirtualBox (NAT + dos puentes), cálculo de una red DHCP propia a partir del último octeto, rango dinámico, reservación por MAC y captura del proceso **DORA** con `tcpdump`. |
| 2 | [servidor-dns.md](practicas-tema-3/servidor-dns.md) | **BIND 9** | Zona directa e inversa para el dominio propio, Kea entrega el DNS y el dominio a los clientes, funcionamiento sin internet y nombres `www`, `ftp` y `mail` para las siguientes prácticas. |
| 3 | [servidor-web.md](practicas-tema-3/servidor-web.md) | **Nginx + PHP 8.5 + MySQL 8.4** | Stack LEMP, CA propia con OpenSSL, sitio en `https://www.leonel.mx` con HTTP/2 y redirección a HTTPS, PHP–MySQL con mínimo privilegio y confianza de los clientes en la CA. |
| 4 | [servidor-sftp.md](practicas-tema-3/servidor-sftp.md) | **SFTP (OpenSSH 10.2)** | Usuario `webmaster` encerrado en *chroot* en la carpeta del sitio, llaves Ed25519 sin contraseña, publicación de páginas desde el cliente y verificación de la huella del servidor. |
| 5 | [servidor-correo.md](practicas-tema-3/servidor-correo.md) | **Postfix 3.10 + Dovecot 2.4 + Roundcube 1.6** | SMTP, IMAP y webmail; entrega por LMTP y autenticación SASL; cifrado con el certificado de la CA; comprobación de que no es relay abierto ni permite suplantar remitentes. |

Notas comunes:

- La conexión a internet (adaptador NAT) se activa **solo para instalar paquetes** y se desconecta después.
- Cada práctica termina con un **paquete de evidencias** verificable (hashes SHA-256).

---

## Archivos de configuración

El directorio [configuracion/](configuracion/) reúne los archivos que las prácticas de los temas 2 y 3 hacen crear en el servidor (56 archivos). Cada uno se guarda **en la misma ruta** que indica la práctica, tomando `configuracion/` como la raíz `/` del sistema. Por ejemplo, `/etc/netplan/60-lab-dhcp.yaml` de la [práctica DHCP](practicas-tema-3/servidor-dhcp.md) está en [configuracion/etc/netplan/60-lab-dhcp.yaml](configuracion/etc/netplan/60-lab-dhcp.yaml).

### Convenciones

- **Valores de ejemplo.** Los archivos conservan los datos de la práctica: dominio `leonel.mx`, red `192.168.50.0/24`, IP `192.168.1.50`, usuario `leonel`, etc. Los que los contienen empiezan con un comentario `AVISO` que indica qué cambiar. Los marcadores `CLAVE_BD`, `LLAVE_DES`, `PEGA_AQUI_EL_SECRET` y `${DB_PASS}` hay que sustituirlos por valores reales.
- **Usuario de los scripts.** Lo que en la práctica vive en `~` está en `home/usuario/` (cámbialo por tu usuario). El `xstartup` de VNC está en `home/profe1/.vnc/`.
- **Líneas añadidas.** [etc/aliases](configuracion/etc/aliases) y [etc/fstab](configuracion/etc/fstab) contienen solo la línea que la práctica **agrega** a un archivo existente; no sustituyas el archivo completo.
- **Scripts.** Los de `home/usuario/` y `usr/local/sbin/` tienen permiso de ejecución.
- **Fuera de la carpeta:** los comandos `sed`, `postconf` y `ufw`, la llave `authorized_keys` de ejemplo, `kea-ddns.key` (se genera con `tsig-keygen`) y las páginas de prueba `practica4.html` y `hora.php`.

### Variantes de un mismo archivo

Varias prácticas modifican la misma ruta. En la ruta exacta está la **versión final** (la que resulta de aplicar todas las prácticas) y las demás quedan al lado con un sufijo:

| Ruta | Contenido de la versión sin sufijo | Variantes |
|------|-----------------------------------|-----------|
| `etc/netplan/01-netcfg.yaml` | NAT + Solo-Anfitrión (`enp0s3` y `enp0s8`) | `.red_estatica`, `.red_dinamica`, `.red_dinamica_host-only_solo-nat`, `.red_dinamica_host-only`, `.red_estatica_dinamica-dhcp`, `.red_estatica_dinamica-estatica` |
| `etc/netplan/60-lab-dhcp.yaml` | Con `nameservers` (DNS) y `optional: true` en `enp0s3` (web) | `.servidor-dhcp` (original) |
| `etc/netplan/50-cloud-init.yaml` | Cliente con `use-domains: true` (DNS) | `.servidor-dhcp` |
| `etc/kea/kea-dhcp4.conf` | DNS propio `leonel.mx` + DDNS | `.servidor-dhcp` (con `lab.local` y sin DDNS) |
| `etc/bind/named.conf.local` | Zonas con `update-policy` para DDNS | `.sin-ddns` |
| `etc/samba/smb.conf` | Con impresión por CUPS y el recurso `[USB_Lab]` | `.practica_usuarios` (original) |
| `var/lib/bind/db.leonel.mx` | Zona base + registro SPF de la práctica de correo | — |

### Archivos por práctica

**Tema 2: red y paquetes**

| Archivo | Para qué sirve |
|---------|----------------|
| [etc/netplan/01-netcfg.yaml](configuracion/etc/netplan/01-netcfg.yaml) y variantes | IP estática o DHCP con Netplan, según la práctica. |
| [etc/netplan/perfiles/dhcp.yaml](configuracion/etc/netplan/perfiles/dhcp.yaml), [estatica.yaml](configuracion/etc/netplan/perfiles/estatica.yaml) | Perfiles de red entre los que alterna `red-perfil`. |
| [usr/local/sbin/red-perfil](configuracion/usr/local/sbin/red-perfil) | Script que cambia de perfil (`estatica`, `dhcp`, `estado`). |
| [etc/cloud/cloud.cfg.d/99-disable-network-config.cfg](configuracion/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg) | Impide que cloud-init regenere la red. |
| [etc/apt/preferences.d/nginx](configuracion/etc/apt/preferences.d/nginx) | *Pinning* de APT para `nginx`. |

**Tema 2: SSH**

| Archivo | Para qué sirve |
|---------|----------------|
| [etc/ssh/sshd_config.d/00-seguridad.conf](configuracion/etc/ssh/sshd_config.d/00-seguridad.conf) | Endurecimiento de `sshd`: sin root, solo llave, `MaxAuthTries 3`. |
| [etc/ssh/sshd_config.d/05-puerto.conf](configuracion/etc/ssh/sshd_config.d/05-puerto.conf) | Cambio de puerto a 2222. |
| [etc/ssh/sshd_config.d/10-banner.conf](configuracion/etc/ssh/sshd_config.d/10-banner.conf), [etc/issue.net](configuracion/etc/issue.net) | Aviso previo al login. |
| [etc/ssh/sshd_config.d/20-penalizaciones.conf](configuracion/etc/ssh/sshd_config.d/20-penalizaciones.conf) | Exime a la red local de las penalizaciones de OpenSSH 10. |
| [etc/fail2ban/jail.d/sshd.local](configuracion/etc/fail2ban/jail.d/sshd.local) | Fail2ban para SSH. |

**Tema 2: usuarios, Samba, VNC e impresoras**

| Archivo | Para qué sirve |
|---------|----------------|
| [etc/samba/smb.conf](configuracion/etc/samba/smb.conf) y `.practica_usuarios` | Recursos `publico`, `docentes`, `entregas` y la impresora `USB_Lab`. |
| [etc/systemd/system/vncserver@.service](configuracion/etc/systemd/system/vncserver@.service) | Servicio systemd de TigerVNC por usuario. |
| [etc/vnc/profe1.conf](configuracion/etc/vnc/profe1.conf) | Pantalla `:1` y resolución de `profe1`. |
| [home/profe1/.vnc/xstartup](configuracion/home/profe1/.vnc/xstartup) | Arranca el escritorio XFCE. |

**Tema 3: DHCP (Kea)**

| Archivo | Para qué sirve |
|---------|----------------|
| [etc/netplan/60-lab-dhcp.yaml](configuracion/etc/netplan/60-lab-dhcp.yaml) | Las tres interfaces del servidor (NAT y dos puentes). |
| [etc/kea/kea-dhcp4.conf](configuracion/etc/kea/kea-dhcp4.conf) | Servidor DHCPv4: pool, reservaciones y DDNS. |
| [etc/netplan/50-cloud-init.yaml](configuracion/etc/netplan/50-cloud-init.yaml) | Cliente Linux con DHCP. |
| [etc/systemd/network/10-netplan-enp0s3.network.d/solo-kea.conf](configuracion/etc/systemd/network/10-netplan-enp0s3.network.d/solo-kea.conf) | El cliente solo acepta ofertas de su servidor Kea. |
| [etc/default/isc-dhcp-server](configuracion/etc/default/isc-dhcp-server), [etc/dhcp/dhcpd.conf](configuracion/etc/dhcp/dhcpd.conf) | Anexo heredado con `isc-dhcp-server`. |
| [home/usuario/recolectar_evidencias.sh](configuracion/home/usuario/recolectar_evidencias.sh) | Paquete de evidencias. |

**Tema 3: DNS (BIND 9)**

| Archivo | Para qué sirve |
|---------|----------------|
| [etc/bind/named.conf.options](configuracion/etc/bind/named.conf.options) | ACL, escucha solo en la red del laboratorio y recursión. |
| [etc/bind/named.conf.local](configuracion/etc/bind/named.conf.local) | Declaración de las zonas directa e inversa. |
| [var/lib/bind/db.leonel.mx](configuracion/var/lib/bind/db.leonel.mx), [db.50.168.192.in-addr.arpa](configuracion/var/lib/bind/db.50.168.192.in-addr.arpa) | Zonas directa e inversa. |
| [etc/kea/kea-dhcp-ddns.conf](configuracion/etc/kea/kea-dhcp-ddns.conf) | Actualizaciones dinámicas de DNS desde Kea (TSIG). |
| [home/usuario/evidencias_dns.sh](configuracion/home/usuario/evidencias_dns.sh) | Paquete de evidencias. |

**Tema 3: Web (Nginx + PHP + MySQL)**

| Archivo | Para qué sirve |
|---------|----------------|
| [etc/ssl/lab/www.leonel.mx.ext](configuracion/etc/ssl/lab/www.leonel.mx.ext) | Extensiones X.509 (SAN) del certificado firmado por la CA propia. |
| [etc/nginx/sites-available/leonel.mx](configuracion/etc/nginx/sites-available/leonel.mx) | Sitio HTTPS con HTTP/2, PHP-FPM y cabeceras de seguridad. |
| [var/www/leonel.mx/config.php](configuracion/var/www/leonel.mx/config.php) | Credenciales de MySQL, fuera de la raíz web. |
| [var/www/leonel.mx/public/index.php](configuracion/var/www/leonel.mx/public/index.php) | Página principal PHP + MySQL. |
| [etc/sysctl.d/60-nonlocal-bind.conf](configuracion/etc/sysctl.d/60-nonlocal-bind.conf) | Respaldo si Nginx arranca antes que `enp0s9`. |
| [home/usuario/evidencias_web.sh](configuracion/home/usuario/evidencias_web.sh) | Paquete de evidencias. |

**Tema 3: SFTP**

| Archivo | Para qué sirve |
|---------|----------------|
| [etc/ssh/sshd_config.d/60-sftp-web.conf](configuracion/etc/ssh/sshd_config.d/60-sftp-web.conf) | *Chroot* y solo SFTP para el grupo `sftpweb`. |
| [etc/fstab](configuracion/etc/fstab) | Línea que monta `/dev/log` dentro del chroot (registro de transferencias). |
| [home/usuario/.ssh/config](configuracion/home/usuario/.ssh/config) | Alias `ftp.leonel.mx` en el cliente. |
| [home/usuario/evidencias_sftp.sh](configuracion/home/usuario/evidencias_sftp.sh) | Paquete de evidencias. |

**Tema 3: correo (Postfix + Dovecot + Roundcube)**

| Archivo | Para qué sirve |
|---------|----------------|
| [etc/aliases](configuracion/etc/aliases) | Línea que envía el correo de `root` a `ana`. |
| [etc/postfix/login_maps.regexp](configuracion/etc/postfix/login_maps.regexp) | Cada usuario solo envía como su propia dirección. |
| [etc/dovecot/local.conf](configuracion/etc/dovecot/local.conf) | Dovecot 2.4: Maildir, TLS, LMTP y SASL. |
| [var/www/roundcube/config/config.inc.php](configuracion/var/www/roundcube/config/config.inc.php) | Webmail Roundcube. |
| [etc/nginx/sites-available/mail.leonel.mx](configuracion/etc/nginx/sites-available/mail.leonel.mx) | Sitio HTTPS de Roundcube. |
| [home/usuario/evidencias_correo.sh](configuracion/home/usuario/evidencias_correo.sh) | Paquete de evidencias. |

### Cómo usarlos

Copia un archivo a su ruta real y ajusta los valores de ejemplo. Con `sudo` y `install` se fijan los permisos en un paso:

```bash
sudo install -m 600 -o root -g root configuracion/etc/netplan/60-lab-dhcp.yaml /etc/netplan/60-lab-dhcp.yaml
```

Para ver qué cambia respecto a lo que ya tienes en el servidor:

```bash
diff -u /etc/kea/kea-dhcp4.conf configuracion/etc/kea/kea-dhcp4.conf
```

Los archivos de `/etc/netplan/` deben tener permisos `600`, y conviene validar antes de aplicar (`netplan try`, `sshd -t`, `nginx -t`, `kea-dhcp4 -t`, etc.).

---

## Scripts de evaluación del tema 2

El directorio [scripts-tema-2/](scripts-tema-2/) contiene ocho scripts Bash, uno por apartado (A–H), que revisan la configuración del servidor del escenario de la práctica de [usuarios, Samba, UFW y VNC](practicas-tema-2/practica_usuarios_tema3.md), de [SSH](practicas-tema-2/ssh.md) y de [impresoras](practicas-tema-2/impresora.md), y asignan una puntuación.

Los scripts **solo consultan** el estado del sistema; las únicas acciones que realizan son trabajos de impresión de prueba (apartado H, que cancela uno) y un archivo de prueba que el apartado C sube a `entregas` y borra.

### Requisitos

- Ubuntu Server con Bash 4 o superior (el apartado C usa `${var^^}`).
- Ejecutarse **en el servidor** que se evalúa.
- `sudo` para todos los apartados excepto A (B funciona sin él, pero no puede verificar privilegios).
- Nombres que los scripts esperan (fijos en el código):

| Elemento | Valor esperado |
|----------|----------------|
| Grupos | `docentes`, `alumnos` |
| Usuarios | `profe1` (grupo `docentes`), `alumno1` y `alumno2` (grupo `alumnos`) |
| Recursos Samba | `publico`, `docentes`, `entregas`, en `/srv/samba/<recurso>` |
| Sesión VNC | pantalla `:1` de `profe1` (puerto 5901) |

### Copiar los scripts al servidor

Desde el equipo donde está este repositorio:

```bash
scp -r scripts-tema-2 alumno@192.168.1.50:~/
```

En el servidor:

```bash
cd ~/scripts-tema-2
chmod +x evaluar-apartado-*.sh
```

### Uso general

Todos los scripts reciben los mismos dos parámetros, la IP del servidor y la IP del cliente autorizado:

```bash
sudo bash evaluar-apartado-X.sh IP_SERVIDOR IP_CLIENTE
```

La excepción es el apartado B, que no recibe parámetros. Ejemplo con el escenario de la práctica:

```bash
bash      evaluar-apartado-a.sh 192.168.1.50 192.168.1.60
sudo bash evaluar-apartado-b.sh
sudo bash evaluar-apartado-c.sh 192.168.1.50 192.168.1.60
sudo bash evaluar-apartado-d.sh 192.168.1.50 192.168.1.60
sudo bash evaluar-apartado-e.sh 192.168.1.50 192.168.1.60
sudo bash evaluar-apartado-f.sh 192.168.1.50 192.168.1.60
sudo bash evaluar-apartado-g.sh 192.168.1.50 192.168.1.60
sudo IP_IMPRESORA=192.168.1.80 bash evaluar-apartado-h.sh 192.168.1.50 192.168.1.60
```

Para ejecutar todos y guardar el resultado en un archivo:

```bash
SRV=192.168.1.50; CLI=192.168.1.60
{
  bash evaluar-apartado-a.sh "$SRV" "$CLI"
  sudo bash evaluar-apartado-b.sh
  for x in c d e f g; do sudo bash "evaluar-apartado-$x.sh" "$SRV" "$CLI"; done
  sudo IP_IMPRESORA=192.168.1.80 bash evaluar-apartado-h.sh "$SRV" "$CLI"
} 2>&1 | tee ~/resultado-evaluacion.txt
```

### Apartados y puntuación

| Apartado | Script | Tema | Puntos |
|----------|--------|------|-------:|
| A | [evaluar-apartado-a.sh](scripts-tema-2/evaluar-apartado-a.sh) | Preparación y conectividad | 5 |
| B | [evaluar-apartado-b.sh](scripts-tema-2/evaluar-apartado-b.sh) | Usuarios y grupos | 10 |
| C | [evaluar-apartado-c.sh](scripts-tema-2/evaluar-apartado-c.sh) | Seguridad de archivos y Samba | 22 |
| D | [evaluar-apartado-d.sh](scripts-tema-2/evaluar-apartado-d.sh) | Firewall UFW | 14 |
| E | [evaluar-apartado-e.sh](scripts-tema-2/evaluar-apartado-e.sh) | Administración remota SSH | 15 |
| F | [evaluar-apartado-f.sh](scripts-tema-2/evaluar-apartado-f.sh) | Acceso remoto gráfico VNC | 12 (9 automáticos + 3 manuales) |
| G | [evaluar-apartado-g.sh](scripts-tema-2/evaluar-apartado-g.sh) | Verificación integral del acceso remoto | 8 |
| H | [evaluar-apartado-h.sh](scripts-tema-2/evaluar-apartado-h.sh) | Administración de impresoras | 14 (12 automáticos + 2 manuales) |
| | | **Total** | **100** |

### Detalle de cada script

#### A. Preparación y conectividad (5 puntos)

No requiere `sudo`.

| Indicador | Puntos | Qué comprueba |
|-----------|-------:|---------------|
| A1 | 3 | `hostnamectl` responde, existe una IPv4 global, `IP_SERVIDOR` está asignada a una interfaz y hay rutas IPv4. |
| A2 | 2 | Hay puerta de enlace predeterminada y responden al `ping` el gateway, el cliente y `1.1.1.1` (requiere internet). |

#### B. Usuarios y grupos (10 puntos)

Sin parámetros: `sudo bash evaluar-apartado-b.sh`.

| Indicador | Puntos | Qué comprueba |
|-----------|-------:|---------------|
| B1 | 4 | Existen los grupos `docentes` y `alumnos` y los usuarios `profe1`, `alumno1` y `alumno2`. |
| B2 | 3 | `profe1` pertenece a `docentes`; `alumno1` y `alumno2` a `alumnos`. |
| B3 | 3 | `alumno1` y `alumno2` tienen shell `/usr/sbin/nologin` y no tienen permisos `sudo`. |

#### C. Seguridad de archivos y Samba (22 puntos)

Todas las pruebas se hacen **en el servidor** con `smbclient` contra `IP_SERVIDOR`; no hace falta SSH ni un cliente Linux (`IP_CLIENTE` solo se valida).

| Indicador | Puntos | Qué comprueba |
|-----------|-------:|---------------|
| C1 | 2 | `smbd` instalado y `/etc/samba/smb.conf` presente y legible. |
| C2 | 3 | `profe1`, `alumno1` y `alumno2` registrados en Samba (`pdbedit`). |
| C3 | 4 | `testparm` sin errores; recursos `[publico]`, `[docentes]` y `[entregas]` definidos y visibles con `smbclient`. |
| C4 | 4 | Existen `/srv/samba/{publico,docentes,entregas}` con propietario y grupo válidos y bit **setgid**. |
| C5 | 3 | Servicio `smbd` activo y puerto TCP 445 escuchando. |
| C6 | 3 | `profe1` lista `publico` y `alumno1` sube un archivo a `entregas` (se borra al terminar). |
| C7 | 3 | `alumno1` se autentica en `publico` pero **no** puede acceder a `docentes`. |

**Contraseñas Samba** de `profe1` y `alumno1`. El script las busca en este orden:

1. Archivos `/root/.samba-profe1` y `/root/.samba-alumno1` (permisos `600`):

   ```text
   username = profe1
   password = CONTRASENA
   ```

2. Variables de entorno `SMB_PASS_PROFE1` y `SMB_PASS_ALUMNO1`.
3. Las pide por teclado, sin mostrarlas.

Si no hay ninguna, C3, C6 y C7 fallan con un mensaje claro. Las credenciales temporales se borran al terminar.

#### D. Firewall UFW (14 puntos)

`IP_CLIENTE` es el equipo Windows autorizado.

| Indicador | Puntos | Qué comprueba |
|-----------|-------:|---------------|
| D1 | 3 | UFW activo, con reglas numeradas y política predeterminada consultable. |
| D2 | 4 | Política de entrada `deny`; existe `ALLOW IN` para 22/tcp y 445/tcp desde `IP_CLIENTE` o desde una red (entre `/16` y `/32`) que lo contenga, sin reglas amplias; ambos servicios escuchando. |
| D3 | 3 | La política permite al cliente en 22 y 445 y los servicios SSH y Samba están activos. |
| D4 | 4 | La entrada se bloquea por defecto y no hay `ALLOW IN` desde orígenes no autorizados. |

El comentario de la regla (`# SSH LAN`) se ignora al comparar el origen. `Anywhere` y `0.0.0.0/0` no cuentan como autorizados.

D3 y D4 evalúan las **políticas**, no conexiones reales. Si no hay registros `UFW BLOCK` en el kernel, el script muestra un aviso: el bloqueo debe comprobarse desde otro equipo Windows con las pruebas de PowerShell de la práctica.

#### E. Administración remota SSH (15 puntos)

| Indicador | Puntos | Qué comprueba |
|-----------|-------:|---------------|
| E1 | 3 | `openssh-server` instalado, servicio `ssh` activo y puerto 22 escuchando. |
| E2 | 3 | `IP_SERVIDOR` asignada; el usuario evaluado tiene shell interactivo y está permitido por `AllowUsers`/`AllowGroups` sin `DenyUsers`/`DenyGroups`. |
| E3 | 3 | Autenticación por llave habilitada; `~usuario/.ssh/authorized_keys` existe, contiene una llave válida y tiene permisos seguros. |
| E4 | 3 | `PermitRootLogin no`, `PasswordAuthentication no`, `PubkeyAuthentication yes` y `MaxAuthTries` ≤ 3. |
| E5 | 3 | `sshd -t` sin errores y un inicio de sesión aceptado del usuario evaluado en los últimos 10 minutos. |

El **usuario evaluado** es, por orden, `USUARIO_SSH`, el que lanzó `sudo` o `profe1`. Así `AllowUsers leonel` de la práctica no resta puntos:

```bash
sudo USUARIO_SSH=profe1 bash evaluar-apartado-e.sh 192.168.1.50 192.168.1.60
```

La configuración efectiva se obtiene con `sshd -T`.

#### F. Acceso remoto gráfico VNC (12 puntos)

| Indicador | Puntos | Qué comprueba |
|-----------|-------:|---------------|
| F1 | 2 | TigerVNC o TightVNC instalado y existe `~profe1/.vnc`. |
| F2 | 3 | `vncserver -list` de `profe1` (sesión de login) muestra la pantalla 1 en el puerto 5901. |
| F3 | 3 | **Manual**: conexión desde el visor VNC en Windows. |
| F4 | 4 | UFW activo, entrada `deny` por defecto, 5901/tcp permitido solo desde `IP_CLIENTE` (o una red que lo contenga) y sin reglas generales de entrada. |

Antes de ejecutarlo, la sesión VNC de `profe1` debe estar iniciada.

#### G. Verificación integral del acceso remoto (8 puntos)

| Indicador | Puntos | Qué comprueba |
|-----------|-------:|---------------|
| G1 | 2 | Se pueden consultar nombre del equipo, usuario, fecha e IPs; `IP_SERVIDOR` asignada y `profe1` existe. |
| G2 | 3 | En los registros de **los últimos 15 minutos** hay un inicio de sesión SSH aceptado de `profe1` desde `IP_CLIENTE`. |
| G3 | 3 | Existe `evidencia-vnc.txt` en el Escritorio de `profe1`, propiedad de `profe1`, con el texto `Acceso remoto por VNC`. |

Pasos previos (sección 4.4 de la [práctica de usuarios](practicas-tema-2/practica_usuarios_tema3.md)): conectarse por SSH como `profe1` desde el cliente (como máximo 15 minutos antes de evaluar) y, desde el escritorio remoto VNC, crear:

```bash
echo "Acceso remoto por VNC - $(date)" > ~/Escritorio/evidencia-vnc.txt
```

También se acepta `~/Desktop/evidencia-vnc.txt` o, como alternativa, `~/evidencia_remota.txt` con la línea `Archivo creado remotamente`.

#### H. Administración de impresoras (14 puntos)

| Indicador | Puntos | Qué comprueba |
|-----------|-------:|---------------|
| H1 | 3 | `cups` instalado y activo, planificador en marcha y puerto 631 escuchando. |
| H2 | 3 | Existe la cola USB con URI `usb://`, acepta trabajos y recibe una impresión de prueba. |
| H3 | 3 | Existe la cola de red con URI TCP/IP, acepta trabajos, la impresora responde al `ping` y en el puerto 631 o 9100, y recibe una impresión de prueba. |
| H4 | 3 | Se consultan colas y trabajos, y se crea y cancela un trabajo de prueba. |
| H5 | 2 | **Manual**: impresión desde Windows. |

Por defecto usa los nombres de la [práctica de impresoras](practicas-tema-2/impresora.md): colas `USB_Lab` y `Red_Lab`, impresora de red en `192.168.1.80`. Se pueden cambiar sin editar el script:

```bash
sudo IMPRESORA_USB=Otra_USB IMPRESORA_RED=Otra_Red IP_IMPRESORA=192.168.1.90 \
  bash evaluar-apartado-h.sh 192.168.1.50 192.168.1.60
```

El script envía **trabajos de impresión reales** a ambas impresoras.

### Interpretar el resultado

Cada script muestra el estado de cada indicador (`Si` / `No`), el motivo de cada fallo y la puntuación del apartado:

```text
=========================================
RESULTADOS - APARTADO A
=========================================
A1 -> Si
A2 -> No
  - No existe respuesta ICMP desde Internet (1.1.1.1).
-----------------------------------------
PUNTUACIÓN: 3 / 5
=========================================
```

- Un indicador solo suma puntos si **todas** sus comprobaciones pasan.
- En F y H se muestran por separado la puntuación automática y los puntos pendientes de evaluación manual.
- Si una IP no tiene formato IPv4 válido o falta `sudo`, el script termina con un mensaje de error sin evaluar.
