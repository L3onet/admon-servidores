# Prácticas de Ubuntu Server

Guías prácticas de administración de **Ubuntu Server** (principalmente 26.04.1 LTS) y scripts para evaluar automáticamente la configuración del servidor.

## Contenido

- [Estructura del repositorio](#estructura-del-repositorio)
- [Prácticas del tema 2](#prácticas-del-tema-2)
- [Prácticas del tema 3](#prácticas-del-tema-3)
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

## Scripts de evaluación del tema 2

El directorio [scripts-tema-2/](scripts-tema-2/) contiene ocho scripts Bash, uno por apartado (A–H), que revisan la configuración del servidor del escenario de la práctica de [usuarios, Samba, UFW y VNC](practicas-tema-2/practica_usuarios_tema3.md), de [SSH](practicas-tema-2/ssh.md) y de [impresoras](practicas-tema-2/impresora.md), y asignan una puntuación.

Los scripts **solo consultan** el estado del sistema; las únicas acciones que realizan son trabajos de impresión de prueba (apartado H, que cancela uno) y, en un caso concreto, crear el archivo de evidencia del apartado G.

### Requisitos

- Ubuntu Server con Bash 4 o superior.
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

Es el script con más requisitos, porque C6 y C7 prueban el acceso **desde el cliente** (Linux con `smbclient`) conectándose a él por SSH.

| Indicador | Puntos | Qué comprueba |
|-----------|-------:|---------------|
| C1 | 2 | `smbd` instalado y `/etc/samba/smb.conf` presente y legible. |
| C2 | 3 | `profe1`, `alumno1` y `alumno2` registrados en Samba (`pdbedit`). |
| C3 | 4 | `testparm` sin errores; recursos `[publico]`, `[docentes]` y `[entregas]` definidos y visibles con `smbclient`. |
| C4 | 4 | Existen `/srv/samba/{publico,docentes,entregas}` con propietario y grupo válidos y bit **setgid**. |
| C5 | 3 | Servicio `smbd` activo y puerto TCP 445 escuchando. |
| C6 | 3 | Desde el cliente: `profe1` lista `publico` y `alumno1` sube un archivo a `entregas`. |
| C7 | 3 | Desde el cliente: `alumno1` se autentica en `publico` pero **no** puede acceder a `docentes`. |

Preparación necesaria:

1. **Archivos de credenciales** en el servidor **y** en el cliente, en `/root/.samba-profe1` y `/root/.samba-alumno1`, con permisos `600`:

   ```text
   username = profe1
   password = CONTRASENA
   ```

2. **SSH por llave desde el `root` del servidor al cliente**, sin contraseña. El script se ejecuta con `sudo`, por lo que usa las llaves y el `known_hosts` de `root` (`StrictHostKeyChecking=yes`: la huella del cliente debe estar aceptada de antemano):

   ```bash
   sudo ssh-keygen -t ed25519
   sudo ssh-copy-id usuario@192.168.1.60
   sudo ssh usuario@192.168.1.60 true   # acepta la huella una vez
   ```

3. En el cliente, el usuario remoto debe poder ejecutar `sudo` **sin contraseña** (para leer las credenciales de `/root`) y tener `smbclient` instalado.

Por defecto el usuario SSH del cliente es el que invocó `sudo` en el servidor. Para usar otro:

```bash
sudo SSH_CLIENT_USER=usuario bash evaluar-apartado-c.sh 192.168.1.50 192.168.1.60
```

#### D. Firewall UFW (14 puntos)

`IP_CLIENTE` es el equipo Windows autorizado.

| Indicador | Puntos | Qué comprueba |
|-----------|-------:|---------------|
| D1 | 3 | UFW activo, con reglas numeradas y política predeterminada consultable. |
| D2 | 4 | Política de entrada `deny`; existe `ALLOW IN` para 22/tcp y 445/tcp **solo** desde `IP_CLIENTE`, sin reglas amplias; ambos servicios escuchando. |
| D3 | 3 | La política permite al cliente en 22 y 445 y los servicios SSH y Samba están activos. |
| D4 | 4 | La entrada se bloquea por defecto y no hay `ALLOW IN` desde orígenes no autorizados. |

D3 y D4 evalúan las **políticas**, no conexiones reales. Si no hay registros `UFW BLOCK` en el kernel, el script muestra un aviso: el bloqueo debe comprobarse desde otro equipo Windows con las pruebas de PowerShell de la práctica.

#### E. Administración remota SSH (15 puntos)

| Indicador | Puntos | Qué comprueba |
|-----------|-------:|---------------|
| E1 | 3 | `openssh-server` instalado, servicio `ssh` activo y puerto 22 escuchando. |
| E2 | 3 | `IP_SERVIDOR` asignada; `profe1` tiene shell interactivo y está permitido por `AllowUsers`/`AllowGroups` sin `DenyUsers`/`DenyGroups`. |
| E3 | 3 | Autenticación por llave habilitada; `~profe1/.ssh/authorized_keys` existe, contiene una llave válida y tiene permisos seguros. |
| E4 | 3 | `PermitRootLogin no`, `PasswordAuthentication no`, `PubkeyAuthentication yes` y `MaxAuthTries` ≤ 3. |
| E5 | 3 | `sshd -t` sin errores y registros SSH consultables. |

La configuración efectiva se obtiene con `sshd -T`. Si `sshd` está en otra ruta, se puede indicar con `SSHD=/ruta/sshd`.

#### F. Acceso remoto gráfico VNC (12 puntos)

| Indicador | Puntos | Qué comprueba |
|-----------|-------:|---------------|
| F1 | 2 | TigerVNC o TightVNC instalado y existe `~profe1/.vnc`. |
| F2 | 3 | `vncserver -list` de `profe1` muestra una sesión activa en `:1`. |
| F3 | 3 | **Manual**: conexión desde el visor VNC en Windows. |
| F4 | 4 | UFW activo, entrada `deny` por defecto, 5901/tcp permitido **solo** desde `IP_CLIENTE` y sin reglas generales de entrada. |

Antes de ejecutarlo, la sesión VNC de `profe1` debe estar iniciada.

#### G. Verificación integral del acceso remoto (8 puntos)

| Indicador | Puntos | Qué comprueba |
|-----------|-------:|---------------|
| G1 | 2 | Se pueden consultar nombre del equipo, usuario, fecha e IPs; `IP_SERVIDOR` asignada y `profe1` existe. |
| G2 | 3 | En los registros de **los últimos 15 minutos** hay un inicio de sesión SSH aceptado de `profe1` desde `IP_CLIENTE`. |
| G3 | 3 | Existe `~profe1/evidencia_remota.txt`, propiedad de `profe1`, con el texto `Archivo creado remotamente`. |

Pasos previos desde el cliente (como máximo 15 minutos antes de evaluar):

```bash
ssh profe1@192.168.1.50
echo "Archivo creado remotamente" > ~/evidencia_remota.txt
exit
```

Si `profe1` ejecuta el script con `sudo` dentro de esa sesión SSH, el propio script crea el archivo como `profe1`.

#### H. Administración de impresoras (14 puntos)

| Indicador | Puntos | Qué comprueba |
|-----------|-------:|---------------|
| H1 | 3 | `cups` instalado y activo, planificador en marcha y puerto 631 escuchando. |
| H2 | 3 | Existe la cola USB con URI `usb://`, acepta trabajos y recibe una impresión de prueba. |
| H3 | 3 | Existe la cola de red con URI TCP/IP, acepta trabajos, la impresora responde al `ping` y en el puerto 631 o 9100, y recibe una impresión de prueba. |
| H4 | 3 | Se consultan colas y trabajos, y se crea y cancela un trabajo de prueba. |
| H5 | 2 | **Manual**: impresión desde Windows. |

> ⚠️ **Nombres de las colas e IP de la impresora.** El script espera las colas `Impresora_USB` e `Impresora_Red` (líneas 36–37) y usa por defecto la IP `192.168.1.50`, que en el escenario es la del servidor. La [práctica de impresoras](practicas-tema-2/impresora.md) usa las colas `USB_Lab` y `Red_Lab` y la impresora en `192.168.1.80`. Antes de evaluar:
>
> - Indica la IP real con la variable `IP_IMPRESORA`:
>
>   ```bash
>   sudo IP_IMPRESORA=192.168.1.80 bash evaluar-apartado-h.sh 192.168.1.50 192.168.1.60
>   ```
>
> - Cambia `IMPRESORA_USB` e `IMPRESORA_RED` en el script por los nombres de tus colas, o crea las colas con los nombres que espera el script.

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
