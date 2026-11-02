# Servidor SFTP con OpenSSH 10.2 en Ubuntu Server 26.04.1 LTS

> **Continuación de:** *DHCP (Kea)* → *DNS (BIND 9)* → *Web (Nginx + PHP 8.5 + MySQL)*
> **Sistema:** Ubuntu Server **26.04.1 LTS** · OpenSSH **10.2p1**
> **Plataforma:** máquinas virtuales en Oracle VirtualBox 7.x
> **Modo de trabajo:** servidor **sin conexión a internet**. No se instala nada: OpenSSH ya viene con Ubuntu Server
> **Nivel:** intermedio · **Duración estimada:** 90–120 min

---

## Índice

1. [Objetivo](#1-objetivo)
2. [Continuidad con las prácticas anteriores](#2-continuidad-con-las-prácticas-anteriores)
3. [Conceptos clave](#3-conceptos-clave)
4. [Datos de tu servidor](#4-datos-de-tu-servidor)
5. [Usuario y permisos](#5-usuario-y-permisos)
6. [Configurar OpenSSH](#6-configurar-openssh)
7. [Primera conexión y entrega de la llave pública](#7-primera-conexión-y-entrega-de-la-llave-pública)
8. [Solo con llave: desactivar la contraseña](#8-solo-con-llave-desactivar-la-contraseña)
9. [Publicar en el sitio web por SFTP](#9-publicar-en-el-sitio-web-por-sftp)
10. [Clientes Windows: sftp, WinSCP y FileZilla](#10-clientes-windows-sftp-winscp-y-filezilla)
11. [Pruebas de funcionamiento y seguridad](#11-pruebas-de-funcionamiento-y-seguridad)
12. [Extra: huella del servidor en el DNS (SSHFP)](#12-extra-huella-del-servidor-en-el-dns-sshfp)
13. [Creación de evidencias](#13-creación-de-evidencias)
14. [Solución de problemas](#14-solución-de-problemas)
15. [Rúbrica sugerida](#15-rúbrica-sugerida)

---

## 1. Objetivo

Al terminar esta práctica, el estudiante podrá:

- Configurar **SFTP** con OpenSSH 10.2 para un usuario dedicado a publicar contenido web.
- **Encerrar** al usuario (*chroot*) en la carpeta de su sitio, sin acceso a una terminal ni al resto del sistema.
- Autenticar con **llaves SSH Ed25519** y desactivar las contraseñas para ese usuario.
- Publicar páginas en `https://www.leonel.mx` desde un cliente, **sin tocar el servidor por consola**.
- Verificar la identidad del servidor por su **huella** y, como extra, publicarla en el DNS.
- Generar un paquete de evidencias verificable.

---

## 2. Continuidad con las prácticas anteriores

| Práctica | Qué dejó listo                                          | Cómo lo usa esta práctica                                   |
|:--------:|---------------------------------------------------------|-------------------------------------------------------------|
| 1 · DHCP | IP para los clientes (`192.168.50.100–200`)              | El cliente se conecta desde su IP de Kea                    |
| 2 · DNS  | `ftp.leonel.mx` → CNAME → `srv-dhcp.leonel.mx`           | El cliente se conecta a **`ftp.leonel.mx`**, no a una IP    |
| 3 · Web  | Sitio en `/var/www/leonel.mx/public` y la tabla `servicios` | El usuario SFTP publica en esa carpeta y el resultado se ve en `https://www.leonel.mx` |
| **4 · SFTP** | Usuario `webmaster` encerrado en su sitio           | —                                                           |
| 5 · Correo | (siguiente)                                            | Usará la misma CA y el nombre `mail.leonel.mx`              |

```
 Cliente (IP por Kea)                                srv-dhcp.leonel.mx · 192.168.50.1
 ┌──────────────────────┐  sftp ftp.leonel.mx :22   ┌───────────────────────────────────────┐
 │ llave id_webmaster   │ ────────────────────────▶ │ OpenSSH 10.2 (internal-sftp)          │
 │ (Ed25519)            │      túnel cifrado SSH    │   chroot: /var/www/leonel.mx          │
 │                      │                           │     ├── config.php  (no puede leerlo) │
 │ navegador ───────────┼── https://www ──────────▶ │     └── public/     (aquí escribe) ───┼─▶ Nginx
 └──────────────────────┘                           └───────────────────────────────────────┘
```

> 💡 **¿Por qué SFTP y no FTP?** El FTP clásico envía usuario y contraseña **en texto claro**. SFTP viaja dentro de SSH: todo va cifrado, usa un solo puerto (22) y permite llaves en lugar de contraseñas. Además, OpenSSH ya está instalado y es uno de los proyectos de software mejor mantenidos que existen.

---

## 3. Conceptos clave

| Concepto            | Qué significa en esta práctica                                                                     |
|---------------------|----------------------------------------------------------------------------------------------------|
| **SFTP**            | Protocolo de archivos de SSH. No es "FTP sobre SSH": es otro protocolo, que comparte el túnel cifrado de SSH |
| **`internal-sftp`** | Servidor SFTP integrado en `sshd`. No necesita programas dentro del chroot                         |
| **Chroot**          | El usuario ve `/var/www/leonel.mx` como si fuera `/` y no puede salir de ahí                         |
| **Regla del chroot** | OpenSSH exige que la carpeta del chroot **y todas las anteriores** sean de `root` y que **nadie más pueda escribir en ellas**. Por eso el usuario escribe en `public/`, no en la raíz del chroot |
| **Llave Ed25519**   | Par de llaves: la **privada** se queda en el cliente y la **pública** se copia al servidor           |
| **Huella (fingerprint)** | Resumen SHA-256 de una llave. Sirve para comprobar que hablas con el servidor correcto          |

---

## 4. Datos de tu servidor

```bash
DOMINIO=leonel.mx
OCT=$(ip -4 -o addr show enp0s8 | awk '{split($4,a,"[./]"); print a[4]}')
echo "SFTP: ftp.${DOMINIO} · IP: 192.168.${OCT}.1 · Carpeta: /var/www/${DOMINIO}/public"
```

| Dato                     | Ejemplo                                   |
|--------------------------|-------------------------------------------|
| Servidor SFTP            | `ftp.leonel.mx` (puerto 22)               |
| Usuario                  | `webmaster`, en el grupo `sftpweb`         |
| Raíz del chroot          | `/var/www/leonel.mx` (lo que el usuario ve como `/`) |
| Carpeta de trabajo       | `/var/www/leonel.mx/public` (lo que el usuario ve como `/public`) |
| Llaves autorizadas       | `/etc/ssh/authorized_keys/webmaster`      |

Comprueba la versión y que el nombre resuelve:

```bash
ssh -V                               # OpenSSH_10.2p1 Ubuntu-...
resolvectl query ftp.${DOMINIO}      # → 192.168.50.1 (vía srv-dhcp)
systemctl status ssh.socket --no-pager | head -n 4
```

> En Ubuntu 26.04, SSH usa **activación por socket**: `ssh.socket` escucha en el puerto 22 y arranca `sshd` cuando llega una conexión.

---

## 5. Usuario y permisos

### 5.1 Grupo y usuario

```bash
sudo groupadd --system sftpweb
sudo useradd --no-create-home --home-dir "/var/www/${DOMINIO}" \
  --shell /usr/sbin/nologin --groups sftpweb \
  --comment "Administrador del sitio ${DOMINIO}" webmaster
sudo passwd webmaster
id webmaster
```

| Opción                      | Por qué                                                         |
|-----------------------------|-----------------------------------------------------------------|
| `--shell /usr/sbin/nologin` | El usuario **no** puede abrir una terminal                       |
| `--groups sftpweb`          | La configuración de SSH se aplica por grupo; así agregar más usuarios es fácil |
| `--no-create-home`          | No necesita carpeta personal: su "casa" es el sitio              |

> La contraseña solo se usará una vez, para entregar la llave pública (sección 7). Después se desactiva.

### 5.2 Ajustar los permisos de la práctica Web

En la práctica Web dejaste `/var/www/leonel.mx` con permisos `750 root:www-data`. Para el chroot hacen falta dos cambios:

1. El usuario necesita **entrar** a la raíz del chroot, así que pasa a `755` (sigue siendo de `root`).
2. `public/` pasa a ser de `webmaster`, con el grupo `www-data` para que Nginx y PHP puedan leer.

```bash
# Raíz del chroot: dueño root, nadie más escribe (requisito de OpenSSH)
sudo chown root:www-data "/var/www/${DOMINIO}"
sudo chmod 755 "/var/www/${DOMINIO}"

# config.php se queda igual: root:www-data 640 (webmaster NO puede leerlo)
ls -l "/var/www/${DOMINIO}/config.php"

# public/: webmaster escribe; www-data (Nginx/PHP) lee
sudo chown -R webmaster:www-data "/var/www/${DOMINIO}/public"
sudo find "/var/www/${DOMINIO}/public" -type d -exec chmod 2750 {} \;
sudo find "/var/www/${DOMINIO}/public" -type f -exec chmod 640 {} \;

namei -l "/var/www/${DOMINIO}/public"
```

Salida esperada de `namei`:

```
f: /var/www/leonel.mx/public
drwxr-xr-x root      root     /
drwxr-xr-x root      root     var
drwxr-xr-x root      root     www
drwxr-xr-x root      www-data leonel.mx
drwxr-s--- webmaster www-data public
```

| Permiso   | En         | Significado                                                                 |
|-----------|------------|-----------------------------------------------------------------------------|
| `755`     | `leonel.mx`  | Todos pueden entrar; solo root escribe (cumple la regla del chroot)        |
| `2750`    | `public/`  | El `2` es **setgid**: todo lo que se cree dentro hereda el grupo `www-data` |
| `640`     | archivos   | `webmaster` lee y escribe, `www-data` lee y los demás no pueden hacer nada  |

### 5.3 Sacar el certificado de la CA de la carpeta pública

`webmaster` ahora controla `public/` y podría **reemplazar** el archivo `ca-leonel.mx.crt` que descargan los clientes. Para que eso no pueda pasar, Nginx lo servirá directamente desde `/etc/ssl/lab/`, que solo modifica root:

```bash
sudo sed -i "s#^        root /var/www/${DOMINIO}/public;#        alias /etc/ssl/lab/ca-${DOMINIO}.crt;#" \
  "/etc/nginx/sites-available/${DOMINIO}"
sudo rm -f "/var/www/${DOMINIO}/public/ca-${DOMINIO}.crt"
grep -A3 "location = /ca-" "/etc/nginx/sites-available/${DOMINIO}"
sudo nginx -t && sudo systemctl reload nginx
curl -s -o /dev/null -w '%{http_code}\n' "http://www.${DOMINIO}/ca-${DOMINIO}.crt"     # 200
```

> 💡 **Lección:** cuando delegas una carpeta a otro usuario, saca de ella todo lo que sea infraestructura (certificados, credenciales, configuración).

---

## 6. Configurar OpenSSH

### 6.1 Archivo de configuración del grupo

Ubuntu lee primero los archivos de `/etc/ssh/sshd_config.d/`. Crea uno para esta práctica. **No** modifiques `sshd_config`.

```bash
sudo nano /etc/ssh/sshd_config.d/60-sftp-web.conf
```

```
# Práctica 4 · SFTP para el administrador del sitio web
Match Group sftpweb
    ChrootDirectory /var/www/leonel.mx
    ForceCommand internal-sftp -d /public -u 0027 -l INFO
    AuthorizedKeysFile /etc/ssh/authorized_keys/%u
    PasswordAuthentication yes
    PermitTTY no
    AllowTcpForwarding no
    AllowAgentForwarding no
    AllowStreamLocalForwarding no
    PermitTunnel no
    X11Forwarding no

# Cierra el bloque Match: lo que siga en sshd_config vuelve a aplicar a todos
Match all
```

| Directiva                          | Qué hace                                                                       |
|------------------------------------|--------------------------------------------------------------------------------|
| `Match Group sftpweb`              | Todo lo de abajo aplica **solo** a los miembros del grupo                       |
| `ChrootDirectory`                  | El usuario queda encerrado en su sitio                                          |
| `ForceCommand internal-sftp`       | Pase lo que pase, solo puede usar SFTP. Nada de terminal ni comandos            |
| `-d /public`                       | Al conectarse, empieza en `public/`                                             |
| `-u 0027`                          | *umask*: los archivos subidos quedan `640` y las carpetas `750`                  |
| `-l INFO`                          | Registra en el log cada archivo que se abre, sube, borra o renombra             |
| `AuthorizedKeysFile ...%u`         | Las llaves autorizadas las controla **root**, no el usuario                     |
| `PasswordAuthentication yes`       | **Temporal**: solo para entregar la llave (sección 8)                            |
| `PermitTTY no`, `Allow*Forwarding no`, `PermitTunnel no` | Sin terminal ni túneles: el usuario no puede usar SSH para llegar a MySQL u otros servicios |

### 6.2 Adaptar, validar y aplicar

```bash
sudo sed -i "s/leonel\.mx/${DOMINIO}/g" /etc/ssh/sshd_config.d/60-sftp-web.conf
sudo install -d -m 755 -o root -g root /etc/ssh/authorized_keys
sudo sshd -t && echo "Configuración válida"
```

Revisa la configuración **efectiva** que recibirá `webmaster`:

```bash
sudo sshd -T -C user=webmaster,host=cliente,addr=192.168.50.100 \
  | grep -E '^(chrootdirectory|forcecommand|authorizedkeysfile|passwordauthentication|permittty|allowtcpforwarding)'
```

```
passwordauthentication yes
permittty no
allowtcpforwarding no
chrootdirectory /var/www/leonel.mx
forcecommand internal-sftp -d /public -u 0027 -l INFO
authorizedkeysfile /etc/ssh/authorized_keys/%u
```

Aplica los cambios:

```bash
sudo systemctl restart ssh
```

> Tu sesión SSH de administrador **no** se corta: `restart` solo afecta las conexiones nuevas.

### 6.3 Anota la huella del servidor

El cliente la verá la primera vez que se conecte y deberá compararla:

```bash
for f in /etc/ssh/ssh_host_*_key.pub; do ssh-keygen -lf "$f"; done
```

```
256 SHA256:Xx1...  root@srv-dhcp (ECDSA)
256 SHA256:Yy2...  root@srv-dhcp (ED25519)     ← la que usará el cliente
3072 SHA256:Zz3... root@srv-dhcp (RSA)
```

### 6.4 Firewall (si UFW está activo)

```bash
sudo ufw allow in on enp0s9 to any port 22 proto tcp comment 'SSH/SFTP'
```

### 6.5 Bitácora de transferencias dentro del chroot

Con `-l INFO`, `internal-sftp` registra cada archivo subido, descargado o borrado. Pero lo hace **después** de entrar al chroot, y busca `/dev/log` *dentro* de `/var/www/leonel.mx`. Como ahí no existe, esos mensajes se perderían en silencio. La solución es montar el socket del journal dentro del chroot:

```bash
sudo install -d -m 755 -o root -g root "/var/www/${DOMINIO}/dev"
sudo touch "/var/www/${DOMINIO}/dev/log"
echo "/run/systemd/journal/dev-log /var/www/${DOMINIO}/dev/log none bind,x-systemd.requires=systemd-journald-dev-log.socket 0 0" \
  | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
sudo mount "/var/www/${DOMINIO}/dev/log"
findmnt "/var/www/${DOMINIO}/dev/log"
```

> - La línea en `/etc/fstab` hace que el montaje se repita en cada arranque.
> - `dev/` es de `root` y el usuario no puede escribir en ella, así que la regla del chroot se sigue cumpliendo. `webmaster` la verá al listar `/`, pero no puede hacer nada con ella.
> - Nginx no la expone: la raíz web es `public/`.

---

## 7. Primera conexión y entrega de la llave pública

Todo esto se hace **en el cliente Linux**, que recibe su IP de Kea y resuelve con tu DNS.

### 7.1 Crear el par de llaves

```bash
ssh-keygen -t ed25519 -C "webmaster@leonel.mx" -f ~/.ssh/id_webmaster
ls -l ~/.ssh/id_webmaster*
```

Cuando lo pida, escribe una **frase de contraseña** (*passphrase*): protege la llave privada si alguien roba el archivo.

| Archivo               | Qué es            | ¿Se comparte?                          |
|-----------------------|-------------------|----------------------------------------|
| `id_webmaster`        | Llave **privada** | **Nunca.** Se queda en el cliente con permisos `600` |
| `id_webmaster.pub`    | Llave **pública** | Sí: es lo que se copia al servidor      |

### 7.2 Conectar con contraseña (única vez)

```bash
sftp webmaster@ftp.leonel.mx
```

La primera vez verás:

```
The authenticity of host 'ftp.leonel.mx (192.168.50.1)' can't be established.
ED25519 key fingerprint is SHA256:Yy2...
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

> ⚠️ **Compara la huella** con la que anotaste en la sección 6.3. Si coincide, escribe `yes`. Si no coincide, **no** te conectes: alguien podría estar suplantando al servidor. Es la misma lección que con la huella de la CA en la práctica Web.

Dentro de `sftp>`:

```
sftp> pwd
Remote working directory: /public
sftp> put /home/TU_USUARIO/.ssh/id_webmaster.pub
sftp> ls -l
sftp> bye
```

> Subir la llave **pública** a la carpeta web no es un riesgo: es pública por diseño. Aun así, el administrador la sacará de ahí enseguida.

### 7.3 El administrador instala la llave (en el servidor)

```bash
sudo install -m 644 -o root -g root \
  "/var/www/${DOMINIO}/public/id_webmaster.pub" /etc/ssh/authorized_keys/webmaster
sudo rm "/var/www/${DOMINIO}/public/id_webmaster.pub"
ssh-keygen -lf /etc/ssh/authorized_keys/webmaster
```

Compara esa huella con la del cliente (`ssh-keygen -lf ~/.ssh/id_webmaster.pub`). Deben ser idénticas.

> Para autorizar otra llave (por ejemplo, la de Windows en la sección 10), **agrega una línea** al mismo archivo con `cat nueva.pub | sudo tee -a /etc/ssh/authorized_keys/webmaster`.

---

## 8. Solo con llave: desactivar la contraseña

### 8.1 Cambiar el método de autenticación del grupo

```bash
sudo sed -i 's/^    PasswordAuthentication yes$/    AuthenticationMethods publickey\n    PasswordAuthentication no/' \
  /etc/ssh/sshd_config.d/60-sftp-web.conf
sudo sshd -t && sudo systemctl restart ssh
sudo sshd -T -C user=webmaster,host=cliente,addr=192.168.50.100 \
  | grep -E '^(authenticationmethods|passwordauthentication)'
```

```
passwordauthentication no
authenticationmethods publickey
```

Como ya no se usa, bloquea también la contraseña en el sistema:

```bash
sudo passwd -l webmaster
```

### 8.2 Configurar el cliente

En el cliente, crea un alias para no escribir todo cada vez:

```bash
cat >> ~/.ssh/config <<'EOF'
Host ftp.leonel.mx
    User webmaster
    IdentityFile ~/.ssh/id_webmaster
    IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config
sftp ftp.leonel.mx
```

✅ Entra **sin pedir contraseña del usuario**. Si pusiste frase a la llave, pedirá **esa** frase, que es local.

> 💡 Para no escribir la frase en cada conexión, cárgala una vez por sesión en el agente: `eval "$(ssh-agent)"; ssh-add ~/.ssh/id_webmaster`.

---

## 9. Publicar en el sitio web por SFTP

Este es el punto de unión con la práctica Web: el contenido se publica **desde el cliente**.

### 9.1 Crear los archivos en el cliente

```bash
mkdir -p ~/sitio && cd ~/sitio

cat > practica4.html <<'EOF'
<!doctype html>
<html lang="es">
<head><meta charset="utf-8"><title>Práctica 4 · SFTP</title></head>
<body>
  <h1>Publicado por SFTP</h1>
  <p>Esta página se subió con OpenSSH 10.2 desde un cliente del laboratorio.</p>
  <p><a href="/">Volver al inicio</a></p>
</body>
</html>
EOF

cat > hora.php <<'EOF'
<?php
declare(strict_types=1);
date_default_timezone_set('America/Mexico_City');
header('Content-Type: text/plain; charset=utf-8');
echo 'Publicado por SFTP · PHP ', PHP_VERSION, ' · ', date('Y-m-d H:i:s'), PHP_EOL;
EOF
```

### 9.2 Subir con un lote de comandos

```bash
sftp -b - ftp.leonel.mx <<'EOF'
put practica4.html
put hora.php
mkdir img
ls -l
EOF
```

### 9.3 Ver el resultado

```bash
curl -s https://www.leonel.mx/practica4.html | grep '<h1>'
curl -s https://www.leonel.mx/hora.php
```

✅ **Éxito:** se muestra `<h1>Publicado por SFTP</h1>` y la hora generada por PHP 8.5. También puedes abrir `https://www.leonel.mx/practica4.html` en el navegador.

### 9.4 Actualizar la tabla de servicios (en el servidor)

```bash
sudo mysql -e "UPDATE laboratorio.servicios
  SET software='OpenSSH 10.2 (SFTP)', estado='Instalado' WHERE practica=4;"
```

Recarga `https://www.leonel.mx`: la práctica 4 aparece como **Instalado**.

> ⚠️ **Lección de seguridad:** quien puede subir archivos `.php` puede ejecutar código con los permisos de `www-data`, incluido leer `config.php`, aunque por SFTP no tenga acceso a ese archivo. Por eso solo se da acceso SFTP a personas de confianza. En sitios donde el editor solo sube HTML e imágenes, se desactiva PHP en las carpetas de subida.

---

## 10. Clientes Windows: sftp, WinSCP y FileZilla

### 10.1 sftp de Windows (PowerShell)

Windows 10 y 11 incluyen el cliente OpenSSH:

```powershell
ssh-keygen -t ed25519 -C "webmaster-windows" -f "$env:USERPROFILE\.ssh\id_webmaster"
Get-Content "$env:USERPROFILE\.ssh\id_webmaster.pub"
```

Copia esa línea y agrégala en el servidor (sección 7.3):

```bash
echo 'ssh-ed25519 AAAA... webmaster-windows' | sudo tee -a /etc/ssh/authorized_keys/webmaster
```

Conéctate:

```powershell
sftp -i "$env:USERPROFILE\.ssh\id_webmaster" webmaster@ftp.leonel.mx
```

### 10.2 WinSCP

| Campo                                                | Valor                                         |
|------------------------------------------------------|-----------------------------------------------|
| Protocolo                                            | **SFTP**                                      |
| Servidor / Puerto                                    | `ftp.leonel.mx` / `22`                        |
| Usuario                                              | `webmaster`                                   |
| Avanzado → SSH → Autenticación → Archivo de clave privada | `id_webmaster` (WinSCP ofrece convertirlo a `.ppk`) |

### 10.3 FileZilla

1. **Edición → Opciones → SFTP → Añadir archivo de clave…** y elige `id_webmaster`.
2. **Gestor de sitios → Nuevo sitio**: protocolo **SFTP**, servidor `ftp.leonel.mx`, puerto `22`, modo de acceso **Interactiva** y usuario `webmaster`.

En los tres casos, la primera conexión muestra la **huella del servidor**: compárala con la de la sección 6.3.

---

## 11. Pruebas de funcionamiento y seguridad

### Prueba 1 – Configuración efectiva (servidor)

```bash
sudo sshd -t && echo OK
sudo sshd -T -C user=webmaster,host=cliente,addr=192.168.50.100 \
  | grep -E '^(chrootdirectory|forcecommand|authenticationmethods|passwordauthentication|permittty|allowtcpforwarding)'
```

✅ **Éxito:** `OK`, `chrootdirectory /var/www/leonel.mx`, `authenticationmethods publickey`, `passwordauthentication no`, `permittty no` y `allowtcpforwarding no`.

### Prueba 2 – Sin terminal (cliente)

```bash
ssh ftp.leonel.mx
```

✅ **Éxito:** responde `This service allows sftp connections only.` y cierra la conexión.

### Prueba 3 – Encerrado en el chroot (cliente)

```bash
sftp -b - ftp.leonel.mx <<'EOF'
pwd
cd ..
pwd
ls /
-ls /etc
-get /config.php /tmp/robado.php
EOF
```

✅ **Éxito:**
- `cd ..` lleva a `/`, que es `/var/www/leonel.mx`.
- `ls /` muestra solo `config.php`, `dev` y `public`.
- `/etc` **no existe** para el usuario.
- `get /config.php` falla con `Permission denied`.

> El `-` al inicio de una línea le indica a `sftp -b` que continúe aunque ese comando falle.

### Prueba 4 – La contraseña ya no sirve (cliente)

```bash
sftp -o PubkeyAuthentication=no -o PreferredAuthentications=password webmaster@ftp.leonel.mx
```

✅ **Éxito:** `webmaster@ftp.leonel.mx: Permission denied (publickey).`

### Prueba 5 – Sin túneles hacia otros servicios (cliente)

Un intento de llegar al MySQL del servidor a través de SSH:

```bash
ssh -N -L 13306:127.0.0.1:3306 ftp.leonel.mx &
sleep 2; curl -s --max-time 3 telnet://127.0.0.1:13306; kill %1
```

✅ **Éxito:** SSH muestra `channel ...: open failed: administratively prohibited: open failed`.

### Prueba 6 – Permisos de lo publicado (servidor)

```bash
ls -l "/var/www/${DOMINIO}/public"
```

✅ **Éxito:** los archivos subidos aparecen como `-rw-r----- webmaster www-data` y la carpeta `img` como `drwxr-s--- webmaster www-data`. El *umask* y el *setgid* funcionaron.

### Prueba 7 – Publicación visible en la web (cliente)

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://www.leonel.mx/practica4.html
curl -s https://www.leonel.mx/hora.php
```

✅ **Éxito:** responde `200` y el texto `Publicado por SFTP · PHP 8.5.x · ...`.

### Prueba 8 – Bitácora de transferencias (servidor)

```bash
sudo journalctl -u ssh --since "30 min ago" --no-pager \
  | grep -E 'Accepted publickey|session opened|open "|close "|remove|mkdir' | tail -n 20
```

✅ **Éxito:** aparecen líneas como estas, con la IP del cliente entregada por Kea:

```
Accepted publickey for webmaster from 192.168.50.101 port 51234 ssh2: ED25519 SHA256:...
open "/public/practica4.html" flags WRITE,CREATE,TRUNCATE mode 0644
close "/public/practica4.html" bytes read 0 written 289
mkdir name "/public/img" mode 0777
```

### Prueba 9 – Todo viaja cifrado (servidor)

```bash
sudo tcpdump -i enp0s9 -n 'tcp port 22' -A -c 40 | grep -iE 'practica4|webmaster|SSH-2.0'
```

Mientras corre, sube un archivo desde el cliente.

✅ **Éxito:** solo se lee el saludo `SSH-2.0-OpenSSH_10.2p1...`, que va en claro. Ni el usuario, ni el nombre del archivo, ni su contenido aparecen. Compáralo con la captura de DNS de la práctica 2, donde todo se veía.

### Prueba 10 – Intercambio de llaves post-cuántico (cliente)

```bash
ssh -v ftp.leonel.mx 2>&1 | grep -iE 'kex: algorithm|host key algorithm'
```

✅ **Éxito:** `kex: algorithm: mlkem768x25519-sha256`. OpenSSH 10 usa por defecto un intercambio **híbrido post-cuántico** (ML-KEM + X25519), que protege la sesión incluso contra un futuro computador cuántico que grabe el tráfico hoy.

---

## 12. Extra: huella del servidor en el DNS (SSHFP)

En lugar de comparar la huella "a ojo", el cliente puede consultarla en **tu DNS**. Así se integran las prácticas 2 y 4.

### 12.1 Publicar los registros SSHFP (servidor)

```bash
ssh-keygen -r srv-dhcp -f /etc/ssh/ssh_host_ed25519_key.pub
```

```
srv-dhcp IN SSHFP 4 1 3f2a...        ← 4 = Ed25519, 1 = SHA-1
srv-dhcp IN SSHFP 4 2 9b1c...        ← 4 = Ed25519, 2 = SHA-256
```

Agrégalos a tu zona:

```bash
sudo rndc freeze "${DOMINIO}" 2>/dev/null        # Solo tiene efecto si activaste DDNS
ssh-keygen -r srv-dhcp -f /etc/ssh/ssh_host_ed25519_key.pub | sudo tee -a "/var/lib/bind/db.${DOMINIO}"
sudo nano "/var/lib/bind/db.${DOMINIO}"          # Sube el SERIAL (por ejemplo, de ...01 a ...03)
sudo named-checkzone "${DOMINIO}" "/var/lib/bind/db.${DOMINIO}"
sudo rndc thaw "${DOMINIO}" 2>/dev/null || sudo rndc reload "${DOMINIO}"
dig @192.168.50.1 srv-dhcp.${DOMINIO} SSHFP +short
```

### 12.2 Verificar desde el cliente

```bash
ssh-keygen -R ftp.leonel.mx                       # Olvida la huella guardada
sftp -o VerifyHostKeyDNS=ask ftp.leonel.mx
```

✅ **Éxito:** antes de la pregunta de confianza aparece `Matching host key fingerprint found in DNS.`

> Como tu zona no está firmada con **DNSSEC**, OpenSSH igual pide confirmación: un DNS sin firma podría estar falsificado. Con DNSSEC, `VerifyHostKeyDNS=yes` aceptaría la llave automáticamente.

---

## 13. Creación de evidencias

### 13.1 Script de recolección

```bash
nano ~/evidencias_sftp.sh
```

```bash
#!/usr/bin/env bash
# Recolector de evidencias - Servidor SFTP OpenSSH 10.2 (Ubuntu 26.04.1 LTS)
# Uso: sudo ./evidencias_sftp.sh <dominio> <octeto> "<Nombre del alumno>"

set -uo pipefail

DOMINIO="${1:-leonel.mx}"
OCT="${2:-50}"
ALUMNO="${3:-Sin nombre}"
IFACE="${IFACE:-enp0s9}"
USUARIO="${USUARIO:-webmaster}"
IP="192.168.${OCT}.1"
CA="/etc/ssl/lab/ca-${DOMINIO}.crt"
SITIO="/var/www/${DOMINIO}"
FECHA="$(date +%Y%m%d_%H%M%S)"
DIR="evidencias_sftp_${FECHA}"

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

ev 01_sistema.txt         "cat /etc/os-release; uname -a; hostnamectl"
ev 02_version.txt         "ssh -V; dpkg -l | grep -E 'openssh-(server|client|sftp)'"
ev 03_servicio.txt        "systemctl status ssh.socket ssh --no-pager | grep -E 'Loaded|Active|Listen'"
ev 04_puerto_22.txt       "ss -tlnp | grep ':22 '"
ev 05_validacion.txt      "sshd -t && echo 'RESULTADO: configuracion valida'"
ev 06_config_grupo.txt    "cat /etc/ssh/sshd_config.d/60-sftp-web.conf"
ev 07_config_efectiva.txt "sshd -T -C user=${USUARIO},host=cliente,addr=192.168.${OCT}.100 | grep -E '^(chrootdirectory|forcecommand|authorizedkeysfile|authenticationmethods|passwordauthentication|permittty|allowtcpforwarding|allowagentforwarding|permittunnel|x11forwarding)'"
ev 08_usuario.txt         "id ${USUARIO}; getent passwd ${USUARIO}; passwd -S ${USUARIO}"
ev 09_permisos_chroot.txt "namei -l ${SITIO}/public; ls -la ${SITIO} ${SITIO}/public; findmnt ${SITIO}/dev/log"
ev 10_llaves.txt          "echo '--- Llaves autorizadas'; ssh-keygen -lf /etc/ssh/authorized_keys/${USUARIO}; echo '--- Huellas del servidor'; for f in /etc/ssh/ssh_host_*_key.pub; do ssh-keygen -lf \$f; done"
ev 11_publicacion_web.txt "for u in /practica4.html /hora.php; do printf '%-16s ' \$u; curl -s -o /dev/null -w '%{http_code}\n' --cacert ${CA} --resolve www.${DOMINIO}:443:${IP} https://www.${DOMINIO}\$u; done; curl -s --cacert ${CA} --resolve www.${DOMINIO}:443:${IP} https://www.${DOMINIO}/hora.php"
ev 12_base_datos.txt      "mysql -e 'SELECT practica, servicio, software, estado FROM laboratorio.servicios;'"
ev 13_bitacora_sftp.txt   "journalctl -u ssh --since '3 hours ago' --no-pager | grep -E 'Accepted|Failed|session opened|open \"|close \"|remove|rename|mkdir|sftp' | tail -n 100"
ev 14_sshfp.txt           "dig @${IP} srv-dhcp.${DOMINIO} SSHFP +short || echo 'Extra SSHFP no realizado'"

echo ">>> Capturando tráfico SSH durante 60 s en $IFACE. Sube un archivo desde el cliente AHORA..."
timeout 60 tcpdump -i "$IFACE" -n 'tcp port 22' -w "$DIR/15_ssh.pcap" 2>/dev/null
ev 15_ssh_resumen.txt     "tcpdump -n -r $DIR/15_ssh.pcap 2>/dev/null | head -n 30; echo '--- Texto legible en la captura:'; tcpdump -n -A -r $DIR/15_ssh.pcap 2>/dev/null | grep -oE 'SSH-2.0-[[:print:]]+' | sort -u"

# Integridad y empaquetado
( cd "$DIR" && sha256sum * > SHA256SUMS.txt )
tar -czf "${DIR}.tar.gz" "$DIR"
sha256sum "${DIR}.tar.gz" | tee "${DIR}.tar.gz.sha256"

echo
echo "✅ Evidencias generadas en: $DIR/"
echo "✅ Paquete: ${DIR}.tar.gz"
```

```bash
chmod +x ~/evidencias_sftp.sh
sudo ~/evidencias_sftp.sh "$DOMINIO" "$OCT" "Nombre Apellido"
```

### 13.2 Evidencias del cliente

**Linux:**

```bash
{
  echo "Alumno: Nombre Apellido | Fecha: $(date)"
  ip -br addr
  resolvectl query ftp.leonel.mx
  ssh -V
  ssh-keygen -lf ~/.ssh/id_webmaster.pub
  ssh-keygen -F ftp.leonel.mx -l
  ssh ftp.leonel.mx 2>&1 | head -n 2
  sftp -b - ftp.leonel.mx <<'EOF'
pwd
ls -l
-get /config.php /tmp/x
EOF
  curl -s https://www.leonel.mx/hora.php
} 2>&1 | tee evidencia_sftp_cliente_$(hostname)_$(date +%Y%m%d_%H%M).txt
```

### 13.3 Capturas de pantalla recomendadas

1. La primera conexión mostrando la **huella** del servidor, junto a la huella anotada en el servidor.
2. `ssh ftp.leonel.mx` respondiendo `This service allows sftp connections only.`
3. El `Permission denied` al intentar descargar `config.php`.
4. WinSCP o FileZilla conectado y mostrando `/public`.
5. El navegador mostrando `https://www.leonel.mx/practica4.html` con candado, y la tabla con la práctica 4 **Instalado**.

---

## 14. Solución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| El cliente se desconecta justo después de autenticar | **Regla del chroot**: alguna carpeta de la ruta no es de root o tiene permiso de escritura para el grupo u otros | `namei -l /var/www/<dominio>/public`. `/`, `var`, `www` y `<dominio>` deben ser de `root` y sin `w` para grupo y otros. El log muestra `bad ownership or modes for chroot directory` |
| `Permission denied (publickey)` con la llave correcta | La llave no está en `/etc/ssh/authorized_keys/webmaster`, o el archivo no es de root | `ssh-keygen -lf` del archivo; `sudo chown root:root` y `chmod 644` |
| `Permission denied` al subir archivos | `public/` no es de `webmaster` | `sudo chown -R webmaster:www-data /var/www/<dominio>/public` |
| Lo subido da `403` o `File not found` en la web | El archivo no quedó en el grupo `www-data` o sin permiso de lectura | Revisa el setgid (`2750`) de `public/` y el `-u 0027` en `ForceCommand` |
| `Directive '...' is not allowed within a Match block` | Falta `Match all` al final del archivo `60-sftp-web.conf` | Agrégalo y ejecuta `sudo sshd -t` |
| `sshd -t` no marca error, pero no aplica la configuración | No reiniciaste el servicio | `sudo systemctl restart ssh` |
| `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` | Cambió la llave del servidor (por ejemplo, reinstalaste la VM) o hay un ataque | Verifica la huella en el servidor. Si es legítima, ejecuta `ssh-keygen -R ftp.leonel.mx` |
| La bitácora no muestra `open`/`close` | Falta `-l INFO` en `ForceCommand` o no está montado `/dev/log` dentro del chroot | Revisa `ForceCommand` y `findmnt /var/www/<dominio>/dev/log` (sección 6.5) |
| La descarga de la CA da `404` | El `sed` de la sección 5.3 no coincidió | Edita la configuración de Nginx y deja `alias /etc/ssl/lab/ca-<dominio>.crt;` en ese `location` |

---

## 15. Rúbrica sugerida

| Criterio                                                              | Puntos |
|-----------------------------------------------------------------------|:------:|
| Usuario `webmaster` sin terminal, en el grupo `sftpweb`                | 10     |
| Permisos del chroot correctos (`namei -l`), CA fuera de `public/` y bitácora en el chroot | 15 |
| `60-sftp-web.conf` válido y configuración efectiva correcta (`sshd -T`) | 15     |
| Autenticación solo con llave Ed25519 y contraseña desactivada          | 15     |
| Pruebas de seguridad: sin terminal, sin túneles y sin acceso a `config.php` | 15  |
| **Continuidad:** publicación desde el cliente visible en `https://www.<dominio>` | 15 |
| Paquete de evidencias con hashes verificables                          | 10     |
| Reporte: diferencias entre SFTP, FTPS y FTP, y qué protege la huella del servidor | 5 |
| **Extra (SSHFP en DNS):**                                              | +5     |
| **Total**                                                             | **100 (+5)** |

---

### Referencias

- OpenSSH – `sshd_config(5)`: `ChrootDirectory`, `ForceCommand`, `Match`: <https://man.openbsd.org/sshd_config>
- OpenSSH – `sftp-server(8)`, opciones `-d`, `-u` y `-l`: <https://man.openbsd.org/sftp-server>
- OpenSSH 10.0 release notes (intercambio de llaves post-cuántico por defecto): <https://www.openssh.com/releasenotes.html>
- RFC 4253 (protocolo de transporte SSH), RFC 4255 (SSHFP en DNS)