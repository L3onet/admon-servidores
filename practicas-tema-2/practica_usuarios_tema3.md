# Práctica: gestión de usuarios y accesos con Samba, firewall y VNC en Ubuntu Server 26.04.1 LTS

> **Objetivo:** configurar un servidor de laboratorio que comparta archivos con **Samba**, controle el tráfico con un **firewall** y ofrezca **escritorio remoto por VNC**. El acceso a cada servicio se restringe por usuario, grupo y equipo.
>
> **Sistema:** Ubuntu Server 26.04.1 LTS (Resolute Raccoon), sin entorno gráfico.
> **Tiempo estimado:** 2 a 3 horas.
>
> Los recuadros **📸 Evidencia** indican qué capturar para el reporte.

---

## Índice

- [0. Escenario y preparación](#0-escenario-y-preparación)
- [Parte 1. Samba](#parte-1-samba)
- [Parte 2. Firewall](#parte-2-firewall)
- [Parte 3. VNC](#parte-3-vnc)
- [Parte 4. Evidencia de acceso remoto exitoso](#parte-4-evidencia-de-acceso-remoto-exitoso)
- [Anexo A. Lista de evidencias](#anexo-a-lista-de-evidencias)
- [Anexo B. Solución de problemas](#anexo-b-solución-de-problemas)

---

## 0. Escenario y preparación

### 0.1 Datos de la práctica

| Elemento | Valor de ejemplo |
|----------|------------------|
| Servidor | `servidor-lab`, IP fija `192.168.1.50` |
| Red local (LAN) | `192.168.1.0/24` |
| Equipo cliente autorizado (docente) | `192.168.1.60` |
| Equipo cliente no autorizado (prueba) | `192.168.1.70` (u otra IP de la LAN) |
| Administrador | `alumno` (grupo `sudo`) |

> ⚠️ **Las IP de este documento son de ejemplo.** Antes de empezar, obtén los valores reales de tu laboratorio y úsalos en **cada** bloque donde aparezca `192.168.1.x`. Copiar una IP de ejemplo no produce un error claro: Samba rechaza a los clientes (sección 1.4), el firewall bloquea las conexiones nuevas (sección 2.4) y el visor VNC se queda esperando (sección 3.9).

Valores reales del servidor:

```bash
ip -br -4 addr show scope global      # IP del servidor y máscara
ip route | grep default               # puerta de enlace; indica cuál es tu red
```

IP del equipo cliente (ejecútalo **en el cliente**):

| Sistema | Comando |
|---------|---------|
| Windows | `ipconfig \| findstr IPv4` |
| macOS (Wi-Fi) | `ipconfig getifaddr en0` |
| Linux | `hostname -I` |

> Si el cliente recibe su IP por DHCP, puede cambiar de un día a otro. Resérvala en el router, o vuelve a comprobarla si VNC deja de conectar.

### 0.2 Usuarios y grupos

| Usuario | Grupo | Shell | Samba | VNC |
|---------|-------|-------|-------|-----|
| `profe1` | `docentes` | Sí | Sí | **Sí (usuario autorizado)** |
| `alumno1`, `alumno2` | `alumnos` | No (`nologin`) | Sí | No |

### 0.3 Preparar el servidor

```bash
sudo apt update && sudo apt full-upgrade -y
sudo hostnamectl set-hostname servidor-lab
ip -br -4 addr show scope global      # confirma la IP fija
```

> Si la IP no es fija, configúrala con Netplan antes de continuar (tutorial *"Configurar una IP estática en Ubuntu Server"*).

El servidor viene en UTC. Ajusta la zona horaria para que los registros y las evidencias salgan con tu hora local:

```bash
sudo timedatectl set-timezone America/Mexico_City
timedatectl | grep 'Time zone'
```

> Para ver las zonas disponibles: `timedatectl list-timezones`.

Carpeta para guardar las salidas de los comandos como evidencia:

```bash
mkdir -p ~/evidencias
```

### 0.4 Crear grupos y usuarios

```bash
sudo groupadd docentes
sudo groupadd alumnos

# Docente: con shell (necesario para su sesión VNC)
sudo adduser profe1
sudo usermod -aG docentes profe1

# Alumnos: sin acceso a consola
sudo useradd -m -s /usr/sbin/nologin -G alumnos alumno1
sudo useradd -m -s /usr/sbin/nologin -G alumnos alumno2

getent group docentes alumnos | tee ~/evidencias/00-grupos.txt
```

Salida esperada:

```
docentes:x:1001:profe1
alumnos:x:1002:alumno1,alumno2
```

---

# Parte 1. Samba

## 1.1 Instalación del servicio

```bash
sudo apt install -y samba smbclient
smbd --version | tee ~/evidencias/1.1-version-samba.txt
```

Salida esperada (el número depende de la versión instalada):

```
Version 4.x.x-Ubuntu
```

> La versión se consulta con `smbd`, no con `samba`. En Ubuntu 26.04 el comando `samba` pertenece al paquete `samba-ad-dc` (controlador de dominio), que esta práctica no usa: si ves `Command 'samba' not found`, **no** instales lo que sugiere el mensaje.

La instalación activa dos servicios: `smbd` (archivos compartidos) y `nmbd` (NetBIOS). NetBIOS no se usa en esta práctica y se desactiva en la sección 1.7; sin él, Samba solo necesita el puerto **445/tcp**.

> 📸 **Evidencia 1.1:** salida de `smbd --version`.

## 1.2 Identificación del archivo principal de configuración

| Archivo / ruta | Función |
|----------------|---------|
| **`/etc/samba/smb.conf`** | **Archivo principal de configuración** |
| `/var/lib/samba/private/passdb.tdb` | Base de datos de usuarios y contraseñas de Samba |
| `/var/log/samba/` | Registros del servicio |

Localizarlo y verificar cuál usa el servicio:

```bash
smbd -b | grep CONFIGFILE
ls -l /etc/samba/smb.conf
```

Salida esperada:

```
   CONFIGFILE: /etc/samba/smb.conf
```

Respaldar el original antes de modificarlo:

```bash
sudo cp -a /etc/samba/smb.conf /etc/samba/smb.conf.original
```

Estructura del archivo:

```ini
[global]        ; opciones generales del servidor
   ...
[nombre]        ; cada sección adicional es un recurso compartido
   path = ...
```

> 📸 **Evidencia 1.2:** salida de `smbd -b | grep CONFIGFILE`.

## 1.3 Creación o habilitación de usuarios para Samba

Samba usa **su propia base de contraseñas**. Un usuario debe existir en el sistema **y** estar dado de alta en Samba.

```bash
sudo smbpasswd -a profe1
sudo smbpasswd -a alumno1
sudo smbpasswd -a alumno2
```

| Comando | Acción |
|---------|--------|
| `smbpasswd -a usuario` | Crear el usuario en Samba y asignarle contraseña |
| `smbpasswd -e usuario` | Habilitar un usuario deshabilitado |
| `smbpasswd -d usuario` | Deshabilitar sin borrarlo |
| `smbpasswd -x usuario` | Eliminar de Samba |

Verificar:

```bash
sudo pdbedit -L | tee ~/evidencias/1.3-usuarios-samba.txt
```

```
profe1:1001:
alumno1:1002:
alumno2:1003:
```

> 📸 **Evidencia 1.3:** salida de `sudo pdbedit -L`.

## 1.4 Creación de un recurso compartido

Se crean tres recursos:

| Recurso | Ruta | Uso |
|---------|------|-----|
| `publico` | `/srv/samba/publico` | Material del curso |
| `docentes` | `/srv/samba/docentes` | Solo docentes |
| `entregas` | `/srv/samba/entregas` | Tareas de los alumnos |

Crear las carpetas:

```bash
sudo mkdir -p /srv/samba/{publico,docentes,entregas}
```

Vaciar el archivo principal (el original ya está respaldado en 1.2) y abrirlo para pegar la configuración nueva:

```bash
sudo truncate -s 0 /etc/samba/smb.conf
sudo nano /etc/samba/smb.conf
```

> ⚠️ En la línea `hosts allow` escribe **tu red real**, no la del ejemplo. Si tu servidor es `192.168.10.50`, la red es `192.168.10.0/24`. Con la red equivocada Samba rechaza a todos los equipos de la LAN y solo funciona desde el propio servidor.

Pega este contenido:

```ini
[global]
   workgroup = WORKGROUP
   server string = Servidor de laboratorio
   server role = standalone server
   security = user
   passdb backend = tdbsam

   # Seguridad
   map to guest = never
   restrict anonymous = 2
   server min protocol = SMB3
   disable netbios = yes
   smb ports = 445
   hosts allow = 127.0.0.1 192.168.1.0/24
   hosts deny  = 0.0.0.0/0

   # Registros
   logging = file
   log file = /var/log/samba/log.%m
   max log size = 1000

   # Sin impresoras
   load printers = no
   printing = bsd
   printcap name = /dev/null
   disable spoolss = yes

[publico]
   comment = Material del curso
   path = /srv/samba/publico
   valid users = @docentes @alumnos
   read only = yes
   write list = @docentes
   create mask = 0664
   directory mask = 2775

[docentes]
   comment = Solo docentes
   path = /srv/samba/docentes
   valid users = @docentes
   read only = no
   force group = docentes
   create mask = 0660
   directory mask = 2770

[entregas]
   comment = Entrega de tareas
   path = /srv/samba/entregas
   valid users = @alumnos @docentes
   read only = no
   force group = alumnos
   create mask = 0660
   directory mask = 2770
```

Validar la sintaxis:

```bash
testparm -s 2>&1 | tee ~/evidencias/1.4-testparm.txt
```

Debe mostrar `Loaded services file OK.` y listar los tres recursos. Comprueba también que la línea `hosts allow` muestre tu red.

> 📸 **Evidencia 1.4:** los recursos en `smb.conf` y la salida de `testparm -s`.

## 1.5 Asignación de permisos

Samba aplica **dos capas de permisos**, y ambas deben permitir la acción:

1. **Sistema de archivos** (dueño, grupo, modo), que se asigna aquí.
2. **Configuración de Samba** (`valid users`, `write list`, `read only`), que se asigna en la sección 1.6.

```bash
sudo chown root:docentes /srv/samba/publico /srv/samba/docentes
sudo chown root:alumnos  /srv/samba/entregas

sudo chmod 2775 /srv/samba/publico
sudo chmod 2770 /srv/samba/docentes
sudo chmod 2770 /srv/samba/entregas

ls -ld /srv/samba/* | tee ~/evidencias/1.5-permisos.txt
```

Salida esperada:

```
drwxrws--- 2 root docentes 4096 ... /srv/samba/docentes
drwxrws--- 2 root alumnos  4096 ... /srv/samba/entregas
drwxrwsr-x 2 root docentes 4096 ... /srv/samba/publico
```

| Modo | Significado |
|------|-------------|
| `2` (setgid, la `s` en el grupo) | Los archivos nuevos heredan el grupo de la carpeta |
| `775` | Dueño y grupo escriben; los demás leen |
| `770` | Solo dueño y grupo; los demás sin acceso |

> 📸 **Evidencia 1.5:** salida de `ls -ld /srv/samba/*`.

## 1.6 Restricción del acceso según usuario o grupo

Directivas usadas en `smb.conf` y su efecto:

| Recurso | Directiva | Efecto |
|---------|-----------|--------|
| `publico` | `valid users = @docentes @alumnos` | Solo esos grupos pueden conectarse |
| `publico` | `read only = yes` + `write list = @docentes` | Todos leen; **solo docentes escriben** |
| `docentes` | `valid users = @docentes` | **Los alumnos no pueden entrar** |
| `entregas` | `valid users = @alumnos @docentes` + `force group = alumnos` | Ambos grupos leen y escriben |
| `[global]` | `hosts allow = ... 192.168.1.0/24` | Solo equipos de la LAN |
| `[global]` | `map to guest = never`, `restrict anonymous = 2` | Sin acceso anónimo |

El `@` indica **grupo**. Para restringir a **un usuario concreto** se escribe sin `@`:

```ini
   write list = profe1
```

Matriz de acceso resultante:

| Recurso | `profe1` (docentes) | `alumno1` (alumnos) | Anónimo |
|---------|---------------------|---------------------|---------|
| `publico` | Lectura/escritura | Solo lectura | Denegado |
| `docentes` | Lectura/escritura | **Denegado** | Denegado |
| `entregas` | Lectura/escritura | Lectura/escritura | Denegado |

## 1.7 Reinicio o recarga del servicio

| Comando | Cuándo usarlo |
|---------|---------------|
| `sudo systemctl restart smbd` | Tras cambios en `[global]`; **corta las conexiones activas** |
| `sudo systemctl reload smbd` | Tras cambios en los recursos; **no corta** las conexiones |
| `sudo smbcontrol all reload-config` | Equivalente a `reload` |

Como es la primera configuración, reinicia y desactiva NetBIOS (no se usa):

```bash
sudo systemctl restart smbd
sudo systemctl disable --now nmbd 2>/dev/null || true
sudo systemctl enable smbd
```

## 1.8 Verificación del estado del servicio

```bash
systemctl status smbd --no-pager | tee ~/evidencias/1.8-estado-smbd.txt
ss -tlnp | grep ':445' | tee -a ~/evidencias/1.8-estado-smbd.txt
```

Salida esperada:

```
● smbd.service - Samba SMB Daemon
     Loaded: loaded (/usr/lib/systemd/system/smbd.service; enabled; preset: enabled)
     Active: active (running) since ...
...
LISTEN 0  50  0.0.0.0:445  0.0.0.0:*  users:(("smbd",...))
```

Recursos publicados:

```bash
smbclient -L //localhost -U profe1
```

```
	Sharename       Type      Comment
	---------       ----      -------
	publico         Disk      Material del curso
	docentes        Disk      Solo docentes
	entregas        Disk      Entrega de tareas
	IPC$            IPC       IPC Service (Servidor de laboratorio)
SMB1 disabled -- no workgroup available
```

> La última línea (`SMB1 disabled...`) es informativa, no un error: el protocolo antiguo SMB1 está desactivado.

> 📸 **Evidencia 1.8:** `systemctl status smbd` en `active (running)`, el puerto 445 escuchando y la lista de recursos.

## 1.9 Acceso al recurso desde un cliente autorizado

Desde el equipo del docente (`192.168.1.60`):

> ⚠️ Usa la **IP real de tu servidor** en lugar de `192.168.1.50`. Con la IP del ejemplo, Windows responde que no encuentra el recurso.

**Windows 10/11:** en la barra de direcciones del Explorador:

```
\\192.168.1.50\publico
```

Usuario `profe1` y su contraseña de Samba. Para asignar una unidad:

```powershell
net use Z: \\192.168.1.50\docentes /user:profe1
```

> Windows recuerda la sesión. Para probar con otro usuario, cierra antes las conexiones: `net use * /delete /y`.
> Como NetBIOS está desactivado, el servidor no aparece en "Red": entra siempre por `\\IP\recurso`.

**Linux:** en el gestor de archivos `smb://192.168.1.50/publico`, o por terminal:

```bash
smbclient //192.168.1.50/publico -U profe1
```

**macOS:** Finder → Ir → Conectarse al servidor → `smb://192.168.1.50/publico`

En este punto la carpeta aparece **vacía**: es lo esperado, porque los archivos se crean en la sección 1.10. Que se abra sin error ya demuestra el acceso.

> 📸 **Evidencia 1.9:** el recurso abierto en el explorador del cliente, con la barra de direcciones visible.

## 1.10 Prueba de acceso autorizado

Desde un cliente Linux (o desde el servidor, cambiando la IP por `localhost`):

```bash
echo "Tema 1" > /tmp/tema1.txt
echo "Tarea 1" > /tmp/tarea1.txt

# Docente escribe en publico
smbclient //192.168.1.50/publico -U profe1 -c 'put /tmp/tema1.txt tema1.txt; ls'

# Docente entra a su recurso
smbclient //192.168.1.50/docentes -U profe1 -c 'ls'

# Alumno lee publico
smbclient //192.168.1.50/publico -U alumno1 -c 'ls'

# Alumno entrega una tarea
smbclient //192.168.1.50/entregas -U alumno1 -c 'put /tmp/tarea1.txt tarea1.txt; ls'
```

Resultado esperado: `putting file ...` y el listado con el archivo.

En Windows: crea un archivo dentro de `\\192.168.1.50\entregas` conectado como `alumno1`.

> 📸 **Evidencia 1.10:** comandos con resultado exitoso y el archivo creado.

## 1.11 Prueba de acceso denegado

```bash
# Alumno intenta escribir en publico (solo lectura para alumnos)
smbclient //192.168.1.50/publico -U alumno1 -c 'put /tmp/tarea1.txt intento.txt'
# Esperado: NT_STATUS_ACCESS_DENIED

# Alumno intenta entrar al recurso de docentes
smbclient //192.168.1.50/docentes -U alumno1 -c 'ls'
# Esperado: NT_STATUS_ACCESS_DENIED

# Acceso anónimo
smbclient -L //192.168.1.50 -N
# Esperado: "Anonymous login successful" seguido de
#           "tree connect failed: NT_STATUS_ACCESS_DENIED"

# Contraseña incorrecta
smbclient //192.168.1.50/publico -U profe1%claveincorrecta -c 'ls'
# Esperado: NT_STATUS_LOGON_FAILURE
```

> En la prueba anónima, el mensaje `Anonymous login successful` no significa que haya entrado: el servidor acepta la sesión sin usuario, pero le niega el listado de recursos en la línea siguiente. El resultado correcto es el `NT_STATUS_ACCESS_DENIED`.

En Windows, conectado como `alumno1`: abrir `\\192.168.1.50\docentes` muestra **"No tiene permiso de acceso"**.

> 📸 **Evidencia 1.11:** los cuatro errores de acceso denegado.

---

# Parte 2. Firewall

## 2.1 Herramienta de firewall utilizada

**UFW (Uncomplicated Firewall)**, la interfaz estándar de Ubuntu para administrar las reglas de filtrado del kernel (netfilter/nftables).

```bash
ufw version | tee ~/evidencias/2.1-ufw-version.txt
```

Si no estuviera instalado: `sudo apt install -y ufw`.

## 2.2 Estado inicial

UFW viene instalado pero **inactivo**:

```bash
sudo ufw status verbose | tee ~/evidencias/2.2-estado-inicial.txt
```

```
Status: inactive
```

> 📸 **Evidencia 2.2:** estado inicial `inactive`.

## 2.3 Puertos o servicios que será necesario habilitar

| Servicio | Puerto | Protocolo | Origen permitido | Motivo |
|----------|--------|-----------|------------------|--------|
| SSH | 22 | TCP | LAN `192.168.1.0/24` | Administración remota del servidor |
| Samba | 445 | TCP | LAN `192.168.1.0/24` | Carpetas compartidas |
| VNC (pantalla `:1`) | 5901 | TCP | **Solo** `192.168.1.60` | Escritorio remoto del docente autorizado |

Todo lo demás queda **bloqueado** por la política por defecto.

> Samba ya no necesita los puertos 137-139 porque NetBIOS está desactivado.

## 2.4 Creación de reglas

> ⚠️ Si trabajas por SSH, crea la regla de SSH **antes** de activar el firewall, o perderás la conexión.

> ⚠️ Escribe en las reglas **tu red real** y la **IP real del cliente autorizado** (comandos de la sección 0.1), no las del ejemplo. Una regla mal escrita no se nota de inmediato: al activar el firewall, la sesión SSH que ya tienes abierta sigue funcionando, y el fallo aparece al abrir una conexión nueva o al reiniciar el servidor.

```bash
# Políticas por defecto
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH desde la LAN
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp comment 'SSH LAN'

# Samba desde la LAN
sudo ufw allow from 192.168.1.0/24 to any port 445 proto tcp comment 'Samba LAN'

# VNC solo desde el equipo del docente autorizado
sudo ufw allow from 192.168.1.60 to any port 5901 proto tcp comment 'VNC profe1'

# Registro de paquetes bloqueados
sudo ufw logging on
```

## 2.5 Consulta de reglas

Antes de activar el firewall (reglas pendientes):

```bash
sudo ufw show added | tee ~/evidencias/2.5-reglas.txt
```

```
Added user rules (see 'ufw status' for running firewall):
ufw allow from 192.168.1.0/24 to any port 22 proto tcp comment 'SSH LAN'
ufw allow from 192.168.1.0/24 to any port 445 proto tcp comment 'Samba LAN'
ufw allow from 192.168.1.60 to any port 5901 proto tcp comment 'VNC profe1'
```

Con el firewall activo (sección 2.6), consulta las reglas con número:

```bash
sudo ufw status numbered
```

Para borrar una regla: `sudo ufw delete <número>`.

> 📸 **Evidencia 2.5:** listado de reglas.

## 2.6 Activación del firewall

```bash
sudo ufw enable
```

```
Command may disrupt existing ssh connections. Proceed with operation (y|n)? y
Firewall is active and enabled on system startup
```

```bash
sudo ufw status verbose | tee ~/evidencias/2.6-firewall-activo.txt
```

```
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW IN    192.168.1.0/24             # SSH LAN
445/tcp                    ALLOW IN    192.168.1.0/24             # Samba LAN
5901/tcp                   ALLOW IN    192.168.1.60               # VNC profe1
```

**Comprobación obligatoria si trabajas por SSH:** sin cerrar la sesión actual, abre **otra** terminal en el cliente y conéctate de nuevo:

```bash
ssh alumno@192.168.1.50
```

Si la segunda sesión no entra, la regla de SSH está mal. Corrígela desde la sesión que sigue abierta (`sudo ufw status numbered`, `sudo ufw delete <número>` y vuelve a crearla) antes de continuar.

> 📸 **Evidencia 2.6:** firewall `active` con las tres reglas.

## 2.7 Verificación del acceso permitido

Desde el **cliente autorizado** (`192.168.1.60`):

**Linux / macOS:**

```bash
nc -zv 192.168.1.50 22
nc -zv 192.168.1.50 445
nc -zv 192.168.1.50 5901      # tras configurar VNC (Parte 3)
```

Esperado: `Connection to 192.168.1.50 port ... succeeded!`

**Windows (PowerShell):**

```powershell
Test-NetConnection 192.168.1.50 -Port 22
Test-NetConnection 192.168.1.50 -Port 445
Test-NetConnection 192.168.1.50 -Port 5901
```

Esperado: `TcpTestSucceeded : True`

> 📸 **Evidencia 2.7:** pruebas de conexión exitosas.

## 2.8 Verificación de accesos restringidos

**a) VNC desde un equipo NO autorizado** (`192.168.1.70`):

```bash
nc -zv -w 5 192.168.1.50 5901      # Linux
nc -zv -G 5 192.168.1.50 5901      # macOS
```

> En macOS el tiempo de espera de conexión es `-G`, no `-w`. Con `-w 5` la prueba tarda más de un minuto en rendirse.

```powershell
Test-NetConnection 192.168.1.50 -Port 5901
```

Esperado: tiempo agotado (`timed out` / `TcpTestSucceeded : False`).

**b) Un puerto que no se habilitó** (por ejemplo, 139 o 3306), desde cualquier cliente:

```bash
nc -zv -w 5 192.168.1.50 139       # Linux
nc -zv -G 5 192.168.1.50 139       # macOS
```

Esperado: tiempo agotado.

**c) Registro del bloqueo en el servidor:**

```bash
sudo journalctl -k -g 'UFW BLOCK' --since '10 min ago' | tee ~/evidencias/2.8-bloqueos.txt
```

```
... [UFW BLOCK] IN=enp2s0 ... SRC=192.168.1.70 DST=192.168.1.50 ... PROTO=TCP SPT=51544 DPT=5901 ...
```

En cada línea, `SRC=` es la IP del equipo que intentó conectarse y `DPT=` el puerto de destino. Las líneas con `PROTO=2` hacia `224.0.0.1` o `224.0.0.251` son tráfico multidifusión normal de la red y se pueden ignorar.

> 📸 **Evidencia 2.8:** intento fallido desde el equipo no autorizado y la línea `UFW BLOCK` con `SRC=192.168.1.70` y `DPT=5901`.

---

# Parte 3. VNC

## 3.1 Software VNC utilizado

| Componente | Software | Paquete |
|------------|----------|---------|
| Servidor VNC | **TigerVNC** | `tigervnc-standalone-server` |
| Entorno de escritorio | **Xfce** (ligero) | `xfce4`, `xfce4-goodies` |
| Cliente (visor) | TigerVNC Viewer, Remmina o RealVNC Viewer | En el equipo del docente |

> Se usa Xfce porque GNOME en Ubuntu 26.04 funciona solo con Wayland, que no es compatible con VNC.

## 3.2 Instalación

```bash
sudo apt install -y tigervnc-standalone-server xfce4 xfce4-goodies dbus-x11
```

Si aparece una pregunta sobre el gestor de pantalla (*display manager*), acepta la opción por defecto.

Mantén el servidor arrancando en modo texto; el escritorio solo se usará por VNC:

```bash
sudo systemctl set-default multi-user.target
sudo systemctl disable --now lightdm 2>/dev/null || true
```

Verificar:

```bash
dpkg -l tigervnc-standalone-server xfce4 | grep ^ii | tee ~/evidencias/3.2-paquetes-vnc.txt
```

> 📸 **Evidencia 3.2:** paquetes instalados (`ii`).

## 3.3 Usuario autorizado

Solo **`profe1`** (grupo `docentes`) tendrá escritorio remoto. El acceso queda limitado de tres maneras:

| Control | Cómo se aplica |
|---------|----------------|
| **Usuario** | Solo existe un servicio VNC para `profe1`; la sesión corre con sus permisos |
| **Contraseña** | Contraseña VNC propia de `profe1` |
| **Equipo** | El firewall solo permite el puerto 5901 desde `192.168.1.60` |

Comprobar que el usuario existe y pertenece al grupo:

```bash
id profe1 | tee ~/evidencias/3.3-usuario-vnc.txt
```

## 3.4 Configuración inicial

Todo este paso se hace **como `profe1`**:

```bash
sudo -iu profe1
```

**a) Contraseña VNC** (de 6 a 8 caracteres; si pones más, se truncan a 8):

```bash
vncpasswd
```

```
Password:
Verify:
Would you like to enter a view-only password (y/n)? n
```

Se guarda en `~/.config/tigervnc/passwd`.

**b) Script de inicio del escritorio:**

```bash
mkdir -p ~/.vnc
cat > ~/.vnc/xstartup <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
EOF
chmod +x ~/.vnc/xstartup
```

**c) Prueba manual:**

```bash
vncserver :1 -geometry 1280x800 -depth 24 -localhost no -xstartup ~/.vnc/xstartup
vncserver -list
vncserver -kill :1
exit
```

Salida esperada:

```
New Xtigervnc server 'servidor-lab:1 (profe1)' on port 5901 for display :1.
...
TigerVNC server sessions:

X DISPLAY #	RFB PORT #	RFB UNIX PATH	PROCESS ID #	SERVER
1         	5901      	             	29141       	Xtigervnc
```

`vncserver -list` debe mostrar la pantalla `1` en el puerto `5901`.

> La primera vez aparece `/usr/bin/xauth: file /home/profe1/.Xauthority does not exist`. No es un error: el archivo se crea en ese momento.

> No olvides `vncserver -kill :1` y `exit`: el servicio de la sección 3.6 usa la misma pantalla, y los pasos siguientes necesitan tu usuario con `sudo`.

> 📸 **Evidencia 3.4:** salida de `vncserver -list` con la pantalla `:1`.

## 3.5 Puerto utilizado

VNC usa el puerto **5900 + número de pantalla**:

| Pantalla | Puerto | Usuario |
|----------|--------|---------|
| `:1` | **5901/tcp** | `profe1` |
| `:2` | 5902/tcp | (siguiente docente) |

## 3.6 Configuración del servicio

Servicio de systemd para que VNC arranque automáticamente con el sistema:

```bash
sudo nano /etc/systemd/system/vncserver@.service
```

```ini
[Unit]
Description=Escritorio VNC de %i
After=network.target

[Service]
Type=simple
User=%i
Group=%i
WorkingDirectory=/home/%i
EnvironmentFile=/etc/vnc/%i.conf
ExecStartPre=-/usr/bin/vncserver -kill :${PANTALLA}
ExecStart=/usr/bin/vncserver :${PANTALLA} -fg -geometry ${RESOLUCION} -depth 24 -localhost no -xstartup /home/%i/.vnc/xstartup
ExecStop=/usr/bin/vncserver -kill :${PANTALLA}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

| Elemento | Significado |
|----------|-------------|
| `%i` | Nombre de usuario; va en el nombre del servicio: `vncserver@profe1` |
| `EnvironmentFile` | Archivo con la pantalla y la resolución de ese usuario |
| `-localhost no` | Acepta conexiones de red (el firewall decide desde qué equipos) |
| `-fg` + `Type=simple` | Mantiene el proceso en primer plano para que systemd lo controle |

Configuración del usuario autorizado:

```bash
sudo mkdir -p /etc/vnc
sudo tee /etc/vnc/profe1.conf > /dev/null <<'EOF'
PANTALLA=1
RESOLUCION=1280x800
EOF
```

> 📸 **Evidencia 3.6:** contenido de `vncserver@.service` y de `/etc/vnc/profe1.conf`.

## 3.7 Regla correspondiente en el firewall

Creada en la sección 2.4. Comprueba que la IP de la regla sea exactamente la del cliente autorizado; un solo dígito distinto basta para que el visor no conecte. Si aún no existe:

```bash
sudo ufw allow from 192.168.1.60 to any port 5901 proto tcp comment 'VNC profe1'
sudo ufw status numbered | grep 5901 | tee ~/evidencias/3.7-regla-vnc.txt
```

```
[ 3] 5901/tcp                   ALLOW IN    192.168.1.60               # VNC profe1
```

> ⚠️ El protocolo VNC **no cifra** el tráfico. La regla limita el acceso a un solo equipo de la LAN. Para más seguridad, usa el túnel SSH de la sección 3.9 (opción B).

> 📸 **Evidencia 3.7:** la regla del puerto 5901.

## 3.8 Inicio y verificación del servicio

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now vncserver@profe1
```

Verificar:

```bash
systemctl status vncserver@profe1 --no-pager | tee ~/evidencias/3.8-estado-vnc.txt
ss -tlnp | grep 5901 | tee -a ~/evidencias/3.8-estado-vnc.txt
```

Salida esperada:

```
● vncserver@profe1.service - Escritorio VNC de profe1
     Loaded: loaded (/etc/systemd/system/vncserver@.service; enabled; preset: enabled)
     Active: active (running) since ...
...
LISTEN 0  5  0.0.0.0:5901  0.0.0.0:*  users:(("Xtigervnc",...))
LISTEN 0  5     [::]:5901     [::]:*  users:(("Xtigervnc",...))
```

Comprobar que arranca solo tras reiniciar:

```bash
sudo reboot
# tras reiniciar:
systemctl is-active vncserver@profe1
```

Tras el reinicio, espera a que el servidor termine de arrancar y abre una sesión SSH **nueva**. Si SSH o VNC dejan de funcionar justo después de reiniciar, casi siempre es una regla del firewall con la red o la IP equivocada (Anexo B, *Firewall*).

> 📸 **Evidencia 3.8:** servicio `active (running)`, `enabled` y puerto 5901 en escucha.

## 3.9 Conexión desde un equipo cliente

### Opción A: conexión directa (equipo autorizado `192.168.1.60`)

1. Instala un visor:
   - **Windows / macOS:** TigerVNC Viewer (<https://tigervnc.org>) o RealVNC Viewer.
   - **Linux:** `sudo apt install -y tigervnc-viewer` o Remmina.
2. Abre el visor y escribe la dirección:

| Visor | Dirección |
|-------|-----------|
| TigerVNC Viewer | `192.168.1.50:1` |
| Remmina (protocolo VNC) | `192.168.1.50:5901` |
| RealVNC Viewer | `192.168.1.50:5901` |

> ⚠️ Escribe siempre la pantalla (`:1`) o el puerto (`:5901`). Con solo la IP, el visor usa el puerto 5900, que el firewall bloquea, y se queda esperando sin mostrar ningún error.

3. Introduce la contraseña VNC de `profe1`. RealVNC Viewer avisa antes de que la conexión no está cifrada: es lo esperado con TigerVNC; acepta para continuar.
4. Aparece el escritorio Xfce del servidor. El **fondo negro es normal**: la instalación mínima de Xfce no incluye fondos de pantalla. El panel superior, los iconos y la barra inferior confirman que la sesión cargó.

Desde Linux por terminal:

```bash
vncviewer 192.168.1.50:1
```

### Opción B: túnel SSH cifrado (recomendada)

El tráfico viaja cifrado por SSH:

```bash
ssh -N -L 5901:localhost:5901 profe1@192.168.1.50
```

Con el túnel abierto, conecta el visor a `localhost:1` (TigerVNC) o `localhost:5901` (Remmina).

> Para usar solo el túnel, cambia `-localhost no` por `-localhost yes` en el servicio y elimina la regla 5901 del firewall. Así VNC no queda expuesto a la red.

### Prueba de acceso denegado a VNC

| Prueba | Resultado esperado |
|--------|--------------------|
| Conectar desde `192.168.1.70` (no autorizado) | El visor se queda esperando y termina con tiempo agotado (bloqueado por UFW) |
| Conectar desde `192.168.1.60` con contraseña incorrecta | `Authentication failure` |

> 📸 **Evidencia 3.9:** visor conectado mostrando el escritorio, y el intento fallido desde el equipo no autorizado.

---

# Parte 4. Evidencia de acceso remoto exitoso

Reúne las pruebas de que el docente autorizado accedió al servidor por VNC.

### 4.1 Captura del escritorio remoto

Con el visor conectado desde `192.168.1.60`, abre una terminal dentro del escritorio Xfce (icono de terminal en la barra inferior, o *Aplicaciones → Emulador de terminal*) y ejecuta:

```bash
hostname; whoami; date; hostname -I
```

Salida esperada dentro de la sesión remota:

```
servidor-lab
profe1
dom 27 sep 2026 18:45:10 CST
192.168.1.50
```

Verás el nombre y la IP reales de tu servidor en lugar de los del ejemplo.

> 📸 **Evidencia 4.1:** captura de pantalla del **equipo cliente** donde se vean a la vez la ventana del visor (con la dirección `192.168.1.50:1` en el título) y la terminal remota con `servidor-lab` y `profe1`.

### 4.2 Registro de la conexión en el servidor

TigerVNC registra cada conexión aceptada en el log de la sesión:

```bash
sudo grep -i 'connections' /home/profe1/.config/tigervnc/*:1.log | tail -n 5 | tee ~/evidencias/4.2-log-vnc.txt
```

```
 Connections: accepted: 192.168.1.60::52814
```

La IP de origen debe ser la del equipo autorizado.

### 4.3 Conexión activa

Mientras el visor está conectado:

```bash
ss -tnp | grep ':5901' | tee ~/evidencias/4.3-conexion-activa.txt
```

```
ESTAB 0  0  192.168.1.50:5901  192.168.1.60:52814  users:(("Xtigervnc",...))
```

### 4.4 Archivo creado de forma remota

Desde el escritorio remoto, crea un archivo con el gestor de archivos o la terminal:

```bash
echo "Acceso remoto por VNC - $(date)" > ~/Escritorio/evidencia-vnc.txt 2>/dev/null \
  || echo "Acceso remoto por VNC - $(date)" > ~/Desktop/evidencia-vnc.txt
```

Compruébalo desde el servidor (consola o SSH):

```bash
sudo find /home/profe1 -name evidencia-vnc.txt -exec ls -l {} \; -exec cat {} \;
```

> 📸 **Evidencia 4.4:** el archivo visible en el escritorio remoto y su contenido desde el servidor.

### 4.5 Integración con Samba (opcional)

Desde el escritorio remoto, abre en el gestor de archivos de Xfce la dirección `smb://localhost/docentes` como `profe1` y copia un archivo. Así se comprueba que los tres servicios funcionan juntos.

---

## Anexo A. Lista de evidencias

| # | Sección | Evidencia | Archivo en `~/evidencias` |
|---|---------|-----------|---------------------------|
| 1.1 | Samba | Versión instalada | `1.1-version-samba.txt` |
| 1.2 | Samba | Archivo de configuración principal | captura |
| 1.3 | Samba | Usuarios de Samba (`pdbedit -L`) | `1.3-usuarios-samba.txt` |
| 1.4 | Samba | Recursos en `smb.conf` + `testparm` | `1.4-testparm.txt` |
| 1.5 | Samba | Permisos de las carpetas | `1.5-permisos.txt` |
| 1.8 | Samba | Servicio activo y puerto 445 | `1.8-estado-smbd.txt` |
| 1.9 | Samba | Recurso abierto desde el cliente | captura |
| 1.10 | Samba | Acceso autorizado | captura |
| 1.11 | Samba | Acceso denegado | captura |
| 2.2 | Firewall | Estado inicial inactivo | `2.2-estado-inicial.txt` |
| 2.5 | Firewall | Reglas creadas | `2.5-reglas.txt` |
| 2.6 | Firewall | Firewall activo | `2.6-firewall-activo.txt` |
| 2.7 | Firewall | Acceso permitido | captura |
| 2.8 | Firewall | Acceso bloqueado + registro | `2.8-bloqueos.txt` |
| 3.2 | VNC | Paquetes instalados | `3.2-paquetes-vnc.txt` |
| 3.4 | VNC | Prueba manual | captura |
| 3.6 | VNC | Archivos del servicio | captura |
| 3.7 | VNC | Regla del firewall | `3.7-regla-vnc.txt` |
| 3.8 | VNC | Servicio activo | `3.8-estado-vnc.txt` |
| 3.9 | VNC | Conexión y acceso denegado | captura |
| 4.1 | Acceso remoto | Escritorio remoto con `hostname` y `whoami` | captura |
| 4.2 | Acceso remoto | Log de conexión aceptada | `4.2-log-vnc.txt` |
| 4.3 | Acceso remoto | Conexión establecida | `4.3-conexion-activa.txt` |
| 4.4 | Acceso remoto | Archivo creado remotamente | captura |

Empaquetar las evidencias de texto:

```bash
tar czf evidencias-$(hostname)-$(date +%F).tar.gz -C ~ evidencias
```

---

## Anexo B. Solución de problemas

### Samba

| Error / síntoma | Causa probable | Solución |
|-----------------|----------------|----------|
| `Command 'samba' not found` | El comando `samba` es de otro paquete (`samba-ad-dc`) | Usa `smbd --version`; no instales `samba-ad-dc` |
| `Protocol negotiation ... failed: NT_STATUS_INVALID_NETWORK_RESPONSE` | La IP del cliente no está en `hosts allow` (quedó la red del ejemplo) | Corrige `hosts allow` con tu red y `sudo systemctl restart smbd` |
| Windows no encuentra `\\IP\recurso` | IP del servidor mal escrita (la del ejemplo) | `ping` a la IP real y `Test-NetConnection IP -Port 445` |
| `NT_STATUS_LOGON_FAILURE` | Usuario no dado de alta en Samba o contraseña incorrecta | `sudo pdbedit -L`; `sudo smbpasswd -a usuario` |
| `NT_STATUS_ACCESS_DENIED` al conectar | Usuario fuera de `valid users` | `id usuario`; revisa los grupos |
| `NT_STATUS_ACCESS_DENIED` al escribir | `read only`/`write list` o permisos de carpeta | `testparm -s`; `ls -ld /srv/samba/*` |
| `NT_STATUS_BAD_NETWORK_NAME` | Recurso mal escrito o carpeta inexistente | `testparm -s` |
| `protocol negotiation failed` | Cliente sin SMB3 | Actualiza el cliente o usa `server min protocol = SMB2_10` |
| Windows usa otro usuario | Credenciales en caché | `net use * /delete /y` |
| Tiempo agotado | Firewall o `hosts allow` | `sudo ufw status`; revisa la IP del cliente |

```bash
sudo tail -n 50 /var/log/samba/log.smbd
```

### Firewall

| Síntoma | Solución |
|---------|----------|
| Perdí la conexión SSH al activar UFW | Entra por consola: `sudo ufw disable`, añade la regla de SSH y vuelve a activar |
| Un cliente autorizado no conecta | Revisa su IP real (`ipconfig` / `ip a`) y la regla con `sudo ufw status numbered` |
| No aparecen líneas `UFW BLOCK` | `sudo ufw logging on` y repite la prueba |
| SSH o VNC dejan de funcionar tras reiniciar, pero el `ping` responde | Una regla tiene la red o la IP equivocada. Entra por consola, revisa `sudo ufw status numbered` y corrige la regla |
| No sé desde qué IP o a qué puerto llega el intento | Mira `SRC=` y `DPT=` en el registro de bloqueos (comando de abajo) |
| `systemctl is-active ssh` dice `inactive` | Es normal: el puerto 22 lo mantiene abierto `ssh.socket` y el servicio arranca con la primera conexión. Comprueba el puerto con `ss -tln \| grep ':22 '` |

```bash
sudo journalctl -k -g 'UFW BLOCK' --since '10 min ago' --no-pager | tail -n 10
```

Para corregir una regla:

```bash
sudo ufw status numbered
sudo ufw delete <número>
sudo ufw allow from <IP-real-del-cliente> to any port 5901 proto tcp comment 'VNC profe1'
```

### VNC

| Error / síntoma | Causa probable | Solución |
|-----------------|----------------|----------|
| El servicio no arranca | Falta la contraseña VNC o el `.conf` | `sudo -iu profe1 vncpasswd`; revisa `/etc/vnc/profe1.conf` |
| Pantalla negra o gris | `xstartup` falta o no es ejecutable | `ls -l /home/profe1/.vnc/xstartup`; `chmod +x` |
| `Session startup ... exited too early` | Xfce no arranca | Revisa `/home/profe1/.config/tigervnc/*.log`; comprueba `which startxfce4` |
| `Connection refused` | VNC escucha solo en `localhost` | Comprueba `-localhost no` y `ss -tlnp \| grep 5901` |
| El visor se queda esperando, sin pedir contraseña | Falta el puerto en la dirección (el visor usa el 5900), o la regla de UFW tiene otra IP | Escribe `IP:5901` o `IP:1`; revisa `SRC=` y `DPT=` en el registro de bloqueos (Anexo B, *Firewall*) |
| Fondo negro con panel e iconos visibles | Instalación mínima de Xfce, sin fondos de pantalla | No es un error; se cambia con clic derecho → *Configuración del escritorio* |
| `Authentication failure` repetido | Contraseña incorrecta; TigerVNC bloquea temporalmente tras varios fallos | Espera unos minutos o `sudo systemctl restart vncserver@profe1` |

```bash
sudo journalctl -xeu vncserver@profe1 --no-pager | tail -n 30
```