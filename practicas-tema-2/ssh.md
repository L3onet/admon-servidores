# Configurar SSH en Ubuntu Server 26.04.1 LTS

> Guía práctica para **Ubuntu Server 26.04.1 LTS (Resolute Raccoon)**, que incluye **OpenSSH 10.2**.
> Se cubren la instalación, las llaves, el endurecimiento del servidor, el cambio de puerto con *socket activation*, el firewall y la solución de problemas.

---

## Índice

1. [Qué cambia en 26.04](#1-qué-cambia-en-2604)
2. [Instalar y comprobar el servidor SSH](#2-instalar-y-comprobar-el-servidor-ssh)
3. [Primera conexión desde el cliente](#3-primera-conexión-desde-el-cliente)
4. [Autenticación con llaves](#4-autenticación-con-llaves)
5. [Cómo se organiza la configuración](#5-cómo-se-organiza-la-configuración)
6. [Endurecer el servidor](#6-endurecer-el-servidor)
7. [Aplicar cambios sin quedarte fuera](#7-aplicar-cambios-sin-quedarte-fuera)
8. [Cambiar el puerto (socket activation)](#8-cambiar-el-puerto-socket-activation)
9. [Firewall con UFW](#9-firewall-con-ufw)
10. [Protección contra fuerza bruta](#10-protección-contra-fuerza-bruta)
11. [Configuración del cliente (~/.ssh/config)](#11-configuración-del-cliente-sshconfig)
12. [Transferir archivos y túneles](#12-transferir-archivos-y-túneles)
13. [Solución de problemas](#13-solución-de-problemas)
14. [Referencia rápida](#14-referencia-rápida)

---

## 1. Qué cambia en 26.04

Si vienes de 22.04 o 24.04, estos cambios afectan a SSH:

| Cambio | Efecto práctico |
|--------|-----------------|
| **OpenSSH 10.2** (24.04 tenía 9.6) | Nueva versión con mejoras de seguridad |
| **Intercambio de claves post-cuántico por defecto** (`mlkem768x25519-sha256`) | Nada que configurar; los clientes antiguos negocian otro algoritmo y OpenSSH advierte de ello |
| **DSA eliminado** | Las llaves `ssh-dss` ya no funcionan; usa Ed25519 |
| **`PerSourcePenalties`** | El servidor penaliza por sí solo a las IPs que fallan la autenticación (sección 10) |
| **Proceso `sshd-auth` separado** | La autenticación corre en un proceso aislado; reduce el impacto de fallos de seguridad |
| **Alias `sshd.service`** | `systemctl ... ssh` y `systemctl ... sshd` funcionan igual |
| **Socket activation** (desde 22.10) | `ssh.socket` escucha el puerto y arranca `sshd` al llegar una conexión; importa al **cambiar el puerto** |
| **`sudo-rs`** es el `sudo` por defecto | Los comandos `sudo` de esta guía funcionan igual |

---

## 2. Instalar y comprobar el servidor SSH

Si marcaste **"Install OpenSSH server"** durante la instalación, ya está instalado. Si no:

```bash
sudo apt update
sudo apt install -y openssh-server
```

Comprobar que está activo:

```bash
systemctl status ssh.socket    # debe decir: active (listening)
ss -tlnp | grep ':22'          # debe mostrar el puerto 22 escuchando
ssh -V                         # versión de OpenSSH
```

> `ssh.service` puede aparecer como **inactive** hasta la primera conexión: es normal con *socket activation*.

Si no está activo:

```bash
sudo systemctl enable --now ssh.socket
```

IP del servidor (la necesitarás en el cliente):

```bash
ip -br -4 addr show scope global
```

---

## 3. Primera conexión desde el cliente

Desde tu equipo (Linux, macOS o Windows 10/11 con PowerShell):

```bash
ssh usuario@192.168.1.50
```

La primera vez verás la huella (*fingerprint*) del servidor:

```
The authenticity of host '192.168.1.50' can't be established.
ED25519 key fingerprint is SHA256:Xb3k...
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

Para comprobar que es tu servidor y no un impostor, compara esa huella con la que muestra **el propio servidor** (desde su consola):

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Si coinciden, escribe `yes`. La huella queda guardada en `~/.ssh/known_hosts` del cliente.

---

## 4. Autenticación con llaves

Las llaves son más seguras y cómodas que las contraseñas. Todo este paso se hace **en el cliente**.

### 4.1 Generar el par de llaves

```bash
ssh-keygen -t ed25519 -C "leonel@laptop"
```

- Acepta la ruta por defecto (`~/.ssh/id_ed25519`).
- Pon una **frase de paso** (*passphrase*): protege la llave si alguien copia el archivo.

Se crean dos archivos:

| Archivo | Qué es | ¿Se comparte? |
|---------|--------|---------------|
| `~/.ssh/id_ed25519` | Llave **privada** | **Nunca** |
| `~/.ssh/id_ed25519.pub` | Llave **pública** | Sí, se copia al servidor |

### 4.2 Copiar la llave pública al servidor

**Linux / macOS:**

```bash
ssh-copy-id usuario@192.168.1.50
```

**Windows (PowerShell):**

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh usuario@192.168.1.50 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

**Alternativa: importar tus llaves de GitHub** (desde el servidor):

```bash
ssh-import-id gh:tu_usuario_github
```

### 4.3 Probar

```bash
ssh usuario@192.168.1.50
```

Debe pedirte la **frase de paso de la llave** (no la contraseña del usuario), o nada si usas un agente.

### 4.4 No escribir la frase de paso cada vez (ssh-agent)

**Linux / macOS:**

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

**Windows (PowerShell como administrador, una sola vez):**

```powershell
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
ssh-add $env:USERPROFILE\.ssh\id_ed25519
```

> ✅ **No continúes con la sección 6 hasta que el acceso por llave funcione.** Si desactivas las contraseñas antes, te quedarás fuera.

---

## 5. Cómo se organiza la configuración

| Ruta | Contenido |
|------|-----------|
| `/etc/ssh/sshd_config` | Configuración principal del **servidor** (no la edites directamente) |
| `/etc/ssh/sshd_config.d/*.conf` | **Aquí van tus cambios** |
| `/etc/ssh/ssh_config` | Configuración global del **cliente** |
| `~/.ssh/authorized_keys` | Llaves públicas autorizadas para ese usuario |
| `/etc/ssh/ssh_host_*_key` | Llaves de identidad del servidor |

`sshd_config` empieza con la línea:

```
Include /etc/ssh/sshd_config.d/*.conf
```

Dos reglas importantes:

1. **Gana el primer valor que lee `sshd`.** Como el `Include` va al principio, tus archivos tienen prioridad sobre el resto de `sshd_config`.
2. Los archivos se leen **en orden alfabético**. En imágenes de nube suele existir `50-cloud-init.conf` con `PasswordAuthentication yes`; si tu archivo se llama `00-...`, se lee antes y gana.

Ver qué archivos hay:

```bash
ls /etc/ssh/sshd_config.d/
```

Ver la **configuración efectiva** (lo que `sshd` realmente usará):

```bash
sudo sshd -T | less
```

---

## 6. Endurecer el servidor

Crea tu archivo de configuración:

```bash
sudo nano /etc/ssh/sshd_config.d/00-seguridad.conf
```

```
# --- Autenticación ---
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
AuthenticationMethods publickey

# --- Usuarios permitidos (cambia por los tuyos) ---
AllowUsers leonel

# --- Límites ---
MaxAuthTries 3
LoginGraceTime 30
MaxSessions 5

# --- Sesiones inactivas: desconecta tras ~10 min sin respuesta ---
ClientAliveInterval 300
ClientAliveCountMax 2

# --- Funciones que un servidor normalmente no necesita ---
X11Forwarding no
PermitUserEnvironment no
```

| Directiva | Qué hace |
|-----------|----------|
| `PermitRootLogin no` | Prohíbe entrar como `root`; entra con tu usuario y usa `sudo` |
| `PasswordAuthentication no` + `KbdInteractiveAuthentication no` | Desactiva por completo el acceso con contraseña |
| `AuthenticationMethods publickey` | Exige llave |
| `AllowUsers` | Solo esos usuarios pueden entrar. También admite grupos: `AllowGroups ssh-users` |
| `MaxAuthTries 3` | Intentos por conexión |
| `LoginGraceTime 30` | Segundos para autenticarse antes de cortar |
| `ClientAlive*` | Cierra sesiones colgadas |

> 💡 Si varias personas administran el servidor, crea un grupo en lugar de listar usuarios:
>
> ```bash
> sudo groupadd ssh-users
> sudo usermod -aG ssh-users leonel
> ```
>
> y usa `AllowGroups ssh-users` en vez de `AllowUsers`.

### Mensaje de aviso antes del login (opcional)

```bash
echo "Acceso restringido. Toda actividad es registrada." | sudo tee /etc/issue.net
echo "Banner /etc/issue.net" | sudo tee /etc/ssh/sshd_config.d/10-banner.conf
```

---

## 7. Aplicar cambios sin quedarte fuera

Sigue siempre este orden:

**1. Mantén abierta tu sesión SSH actual.** No la cierres hasta el paso 4.

**2. Valida la sintaxis:**

```bash
sudo sshd -t
```

Sin salida = sin errores.

**3. Comprueba los valores efectivos y aplica:**

```bash
sudo sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|allowusers|maxauthtries)'
sudo systemctl restart ssh
```

**4. Prueba en una terminal NUEVA:**

```bash
ssh usuario@192.168.1.50
```

Confirma también que las contraseñas ya no se aceptan:

```bash
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password usuario@192.168.1.50
# Esperado: Permission denied (publickey).
```

Solo cuando la sesión nueva funcione, cierra la antigua. Si algo falla, usa la sesión que dejaste abierta para corregirlo.

---

## 8. Cambiar el puerto (socket activation)

En Ubuntu 26.04, quien abre el puerto es **`ssh.socket`**, no `sshd`. Por eso, cambiar `Port` y reiniciar `ssh` **no basta**: hay que recargar systemd y reiniciar el **socket**.

> Cambiar el puerto reduce el ruido de bots en los registros, pero **no sustituye** a la sección 6.

Ejemplo: pasar al puerto **2222**.

### 8.1 Abrir primero el puerto nuevo en el firewall

```bash
sudo ufw allow 2222/tcp
```

(Si UFW no está activo, puedes omitirlo; ver sección 9.)

### 8.2 Método recomendado: `Port` en la configuración de sshd

```bash
echo "Port 2222" | sudo tee /etc/ssh/sshd_config.d/05-puerto.conf
sudo sshd -t
sudo systemctl daemon-reload
sudo systemctl restart ssh.socket
```

Ubuntu genera la configuración del socket a partir de `sshd_config` al hacer `daemon-reload`.

Comprueba:

```bash
ss -tlnp | grep -E ':(22|2222)\b'
systemctl status ssh.socket | grep Listen
```

Debe aparecer **2222** y ya no **22**.

### 8.3 Método alternativo: override del socket

Si tras el paso anterior sigue escuchando en el 22, define el puerto directamente en el socket:

```bash
sudo systemctl edit ssh.socket
```

Escribe entre las líneas de comentario indicadas:

```ini
[Socket]
ListenStream=
ListenStream=2222
```

> La línea vacía `ListenStream=` borra el puerto 22 heredado; sin ella, escucharía en ambos.

```bash
sudo systemctl daemon-reload
sudo systemctl restart ssh.socket
ss -tlnp | grep ':2222'
```

### 8.4 Probar y cerrar el puerto 22

Desde una terminal **nueva**:

```bash
ssh -p 2222 usuario@192.168.1.50
```

Si funciona, retira la regla antigua del firewall:

```bash
sudo ufw delete allow OpenSSH
sudo ufw delete allow 22/tcp
```

(Borra la que exista; la otra dará error, sin problema.)

### 8.5 (Opcional) Desactivar socket activation

Si prefieres el modelo clásico, donde `sshd` siempre está corriendo y lee `Port` directamente:

```bash
sudo systemctl disable --now ssh.socket
sudo rm -f /etc/systemd/system/ssh.service.d/00-socket.conf
sudo rm -f /etc/systemd/system/ssh.socket.d/addresses.conf
sudo systemctl daemon-reload
sudo systemctl enable --now ssh.service
```

Desde ese momento, los cambios de puerto solo requieren `sudo systemctl restart ssh`.

> ⚠️ Hazlo desde la consola o manteniendo la sesión abierta: durante el cambio, SSH deja de escuchar unos segundos.

---

## 9. Firewall con UFW

UFW viene instalado pero **desactivado**. Actívalo **después** de permitir SSH, o te bloquearás:

```bash
sudo ufw allow OpenSSH        # puerto 22 (o: sudo ufw allow 2222/tcp si lo cambiaste)
sudo ufw enable
sudo ufw status verbose
```

Permitir SSH **solo desde tu red local**:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp
```

Limitar intentos de conexión (bloquea una IP que abra 6 o más conexiones en 30 segundos):

```bash
sudo ufw limit OpenSSH
```

---

## 10. Protección contra fuerza bruta

### 10.1 PerSourcePenalties (integrado, activo por defecto)

OpenSSH 10 penaliza automáticamente a las IPs que fallan la autenticación o provocan errores, rechazando sus conexiones durante un tiempo creciente. No necesitas configurar nada.

Si estás haciendo pruebas y **te bloqueas a ti mismo**, exime tu red:

```bash
echo "PerSourcePenaltyExemptList 192.168.1.0/24" | sudo tee /etc/ssh/sshd_config.d/20-penalizaciones.conf
sudo sshd -t && sudo systemctl restart ssh
```

### 10.2 Fail2ban (opcional, bloqueo en el firewall)

Útil si quieres bloqueos más largos o avisos:

```bash
sudo apt install -y fail2ban
sudo nano /etc/fail2ban/jail.d/sshd.local
```

```ini
[sshd]
enabled  = true
backend  = systemd
port     = ssh
maxretry = 5
findtime = 10m
bantime  = 1h
ignoreip = 127.0.0.1/8 ::1 192.168.1.0/24
```

> Si cambiaste el puerto, pon `port = 2222`.

```bash
sudo systemctl enable --now fail2ban
sudo systemctl restart fail2ban
sudo fail2ban-client status sshd
```

Desbloquear una IP:

```bash
sudo fail2ban-client set sshd unbanip 203.0.113.25
```

---

## 11. Configuración del cliente (~/.ssh/config)

En **el cliente**, crea o edita `~/.ssh/config` para no escribir usuario, IP y puerto cada vez:

```
Host servidor
    HostName 192.168.1.50
    User leonel
    Port 2222
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    ServerAliveInterval 60

Host *
    AddKeysToAgent yes
```

Ahora basta con:

```bash
ssh servidor
```

| Opción | Qué hace |
|--------|----------|
| `IdentitiesOnly yes` | Usa solo la llave indicada; evita el error *Too many authentication failures* |
| `ServerAliveInterval 60` | Mantiene viva la conexión en redes que cortan sesiones inactivas |
| `AddKeysToAgent yes` | Añade la llave al agente la primera vez que la usas |

Saltar a un servidor interno a través de otro (bastión):

```
Host interno
    HostName 10.0.0.20
    User leonel
    ProxyJump servidor
```

```bash
ssh interno
```

---

## 12. Transferir archivos y túneles

### Copiar archivos

```bash
scp archivo.txt servidor:/home/leonel/          # subir
scp servidor:/var/log/syslog ./                 # bajar
scp -r carpeta/ servidor:/home/leonel/          # carpeta completa
```

Sincronizar carpetas (solo transfiere diferencias):

```bash
rsync -avz --progress carpeta/ servidor:/home/leonel/carpeta/
```

Sesión interactiva:

```bash
sftp servidor
```

> Si usas un alias de `~/.ssh/config`, todos estos comandos respetan el puerto y la llave definidos ahí.

### Túnel local (acceder a un servicio que solo escucha en el servidor)

Ejemplo: PostgreSQL escucha solo en `localhost:5432` del servidor.

```bash
ssh -N -L 5433:localhost:5432 servidor
```

Ahora, en tu equipo, conéctate a `localhost:5433`. El tráfico viaja cifrado por SSH.

### Ejecutar un comando remoto sin abrir sesión

```bash
ssh servidor 'uptime && df -h /'
```

---

## 13. Solución de problemas

### Diagnóstico por capas

```bash
# En el servidor
systemctl status ssh.socket ssh.service
ss -tlnp | grep ssh
sudo sshd -t
sudo journalctl -u ssh -n 50 --no-pager
sudo journalctl -fu ssh          # en vivo, mientras intentas conectar

# En el cliente
ssh -vvv usuario@192.168.1.50    # muestra cada paso de la conexión
```

### Errores frecuentes

| Error / síntoma | Causa probable | Solución |
|-----------------|----------------|----------|
| `Connection refused` | sshd no escucha en ese puerto | `ss -tlnp`; revisa `ssh.socket` y el puerto (sección 8) |
| `Connection timed out` | Firewall o IP incorrecta | `sudo ufw status`; comprueba la IP y la red |
| `Permission denied (publickey)` | Llave no autorizada o permisos incorrectos | Revisa permisos (abajo) y `~/.ssh/authorized_keys` |
| `Too many authentication failures` | El cliente prueba demasiadas llaves | `IdentitiesOnly yes` o `ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes ...` |
| `REMOTE HOST IDENTIFICATION HAS CHANGED!` | Servidor reinstalado o cambio de llaves de host (o un ataque) | Si sabes que reinstalaste: `ssh-keygen -R 192.168.1.50` en el cliente |
| El puerto no cambia tras editar `Port` | Socket activation | `daemon-reload` + `restart ssh.socket` (sección 8) |
| Se sigue aceptando contraseña | `50-cloud-init.conf` se lee antes que tu archivo | Nombra tu archivo `00-...conf`; verifica con `sudo sshd -T \| grep passwordauth` |
| Conexiones rechazadas tras varios fallos | `PerSourcePenalties` o Fail2ban | Espera, o exime tu red (sección 10) |
| Warning sobre algoritmo no post-cuántico | Cliente o servidor con OpenSSH antiguo | Actualiza OpenSSH en el lado antiguo |
| Llave `ssh-dss` rechazada | DSA eliminado en OpenSSH 10 | Genera una llave Ed25519 |

### Permisos correctos (en el servidor)

`sshd` ignora las llaves si los permisos son demasiado abiertos:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
chmod go-w ~
```

### Si te quedaste fuera

Entra por la **consola** (física, de la VM o del proveedor de nube) y revierte tu archivo:

```bash
sudo mv /etc/ssh/sshd_config.d/00-seguridad.conf /root/
sudo sshd -t && sudo systemctl restart ssh
```

---

## 14. Referencia rápida

| Tarea | Comando |
|-------|---------|
| Instalar | `sudo apt install openssh-server` |
| Estado | `systemctl status ssh.socket ssh` |
| Puertos en escucha | `ss -tlnp \| grep ssh` |
| Validar configuración | `sudo sshd -t` |
| Configuración efectiva | `sudo sshd -T` |
| Aplicar cambios de autenticación | `sudo systemctl restart ssh` |
| Aplicar cambio de puerto | `sudo systemctl daemon-reload && sudo systemctl restart ssh.socket` |
| Registros | `sudo journalctl -u ssh -n 50` |
| Generar llave (cliente) | `ssh-keygen -t ed25519` |
| Copiar llave (cliente) | `ssh-copy-id usuario@servidor` |
| Huella del servidor | `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` |
| Borrar huella antigua (cliente) | `ssh-keygen -R servidor` |
| Depurar conexión (cliente) | `ssh -vvv usuario@servidor` |

---

**Resumen:** instala `openssh-server`, configura el acceso con llaves Ed25519 y comprueba que funciona. Después, desactiva las contraseñas y el acceso de `root` en `/etc/ssh/sshd_config.d/00-seguridad.conf` y valida siempre con `sshd -t`. Prueba cada cambio en una terminal nueva antes de cerrar la actual. Para cambiar el puerto, recuerda que en 26.04 hay que reiniciar **`ssh.socket`**.