# Servidor de correo con Postfix 3.10, Dovecot 2.4 y Roundcube 1.6 en Ubuntu Server 26.04.1 LTS

> **Continuación de:** *DHCP (Kea)* → *DNS (BIND 9)* → *Web (Nginx + PHP 8.5 + MySQL)* → *SFTP (OpenSSH 10.2)*
> **Sistema:** Ubuntu Server **26.04.1 LTS** · Postfix **3.10** · Dovecot **2.4** · Roundcube **1.6.20** (versión oficial) · PHP **8.5** · MySQL **8.4**
> **Plataforma:** máquinas virtuales en Oracle VirtualBox 7.x
> **Modo de trabajo:** servidor **sin conexión a internet**. El correo circula **dentro de tu dominio**
> **Nivel:** avanzado · **Duración estimada:** 150–180 min

---

## Índice

1. [Objetivo](#1-objetivo)
2. [Continuidad con las prácticas anteriores](#2-continuidad-con-las-prácticas-anteriores)
3. [Cómo viaja un correo](#3-cómo-viaja-un-correo)
4. [Datos de tu servidor](#4-datos-de-tu-servidor)
5. [Instalación (conexión temporal a internet)](#5-instalación-conexión-temporal-a-internet)
6. [Cuentas de correo](#6-cuentas-de-correo)
7. [Postfix: enviar y recibir (SMTP)](#7-postfix-enviar-y-recibir-smtp)
8. [Dovecot 2.4: buzones y lectura (IMAP)](#8-dovecot-24-buzones-y-lectura-imap)
9. [Ajustes al DNS](#9-ajustes-al-dns)
10. [Roundcube: webmail en `https://mail.leonel.mx`](#10-roundcube-webmail-en-httpsmailleonelmx)
11. [Pruebas de funcionamiento y seguridad](#11-pruebas-de-funcionamiento-y-seguridad)
12. [Clientes de escritorio (Thunderbird / Outlook)](#12-clientes-de-escritorio-thunderbird--outlook)
13. [Creación de evidencias](#13-creación-de-evidencias)
14. [Solución de problemas](#14-solución-de-problemas)
15. [Rúbrica sugerida](#15-rúbrica-sugerida)

---

## 1. Objetivo

Al terminar esta práctica, el estudiante podrá:

- Instalar un servidor de correo completo: **Postfix** (SMTP), **Dovecot** (IMAP) y **Roundcube** (webmail).
- Configurar Dovecot 2.4, cuya sintaxis **cambió por completo** respecto a la 2.3.
- Integrar Postfix y Dovecot: entrega por **LMTP** y autenticación por **SASL**.
- Cifrar SMTP, IMAP y el webmail con el **certificado de la CA del laboratorio**.
- Comprobar que el servidor **no es un relay abierto** y que un usuario no puede enviar correos a nombre de otro.
- Enviar y leer correo desde la terminal, el navegador y un cliente de escritorio.
- Generar un paquete de evidencias verificable.

---

## 2. Continuidad con las prácticas anteriores

Esta es la última práctica de la serie. Usa **todo** lo construido antes:

| Práctica   | Qué dejó listo                                        | Cómo lo usa el correo                                        |
|:----------:|-------------------------------------------------------|--------------------------------------------------------------|
| 1 · DHCP   | IP para los clientes                                    | Los clientes leen su correo desde su IP de Kea                |
| 2 · DNS    | Registros `MX 10 mail.leonel.mx` y `mail.leonel.mx` → `192.168.50.1` | Indican **a qué servidor** se entrega el correo de `@leonel.mx` |
| 3 · Web    | CA propia, certificado con `mail.leonel.mx` en el SAN, Nginx, PHP 8.5 y MySQL | TLS en SMTP/IMAP, y Roundcube corre en Nginx + PHP + MySQL |
| 4 · SFTP   | Usuarios encerrados y sin terminal                       | Las cuentas de correo tampoco tienen terminal                 |
| **5 · Correo** | Correo `@leonel.mx` y webmail                        | La tabla de servicios queda **completa**                      |

```
                        srv-dhcp.leonel.mx · 192.168.50.1
                 ┌──────────────────────────────────────────────────────┐
  Cliente        │                                                      │
  (Thunderbird,  │  :587 ──▶ Postfix ──LMTP──▶ Dovecot ──▶ /home/luis/  │
   curl)  ───────┼──────────── (SMTP)  ◀─SASL──  (IMAP)      Maildir/   │
                 │                                 ▲                    │
  Navegador ─────┼─ :443 ─▶ Nginx ─▶ PHP-FPM ─▶ Roundcube ─┤ :143/:587   │
  mail.leonel.mx │                                  │ MySQL (roundcube) │
                 │     BIND: MX leonel.mx → mail.leonel.mx               │
                 └──────────────────────────────────────────────────────┘
```

---

## 3. Cómo viaja un correo

Un servidor de correo no es un solo programa, sino varios que cooperan:

| Pieza         | Protocolo / puerto    | Función                                                                  |
|---------------|-----------------------|--------------------------------------------------------------------------|
| **Postfix**   | SMTP `25`             | **MTA**: recibe correo de otros servidores y lo entrega a sus buzones     |
| **Postfix**   | Submission `587`      | Recibe correo de **tus usuarios**, siempre autenticados y con TLS         |
| **Dovecot**   | LMTP (socket local)   | **MDA**: Postfix le pasa el correo y Dovecot lo guarda en el buzón       |
| **Dovecot**   | SASL (socket local)   | Postfix le pregunta a Dovecot si la contraseña es correcta               |
| **Dovecot**   | IMAP `143` / IMAPS `993` | Los clientes **leen** su correo                                      |
| **Roundcube** | HTTPS `443`           | **Webmail**: un cliente IMAP/SMTP que vive en el navegador               |
| **DNS**       | Registro `MX`         | Dice qué servidor recibe el correo de un dominio                         |

**Recorrido de un correo de Ana para Luis:**

1. Ana se autentica en el puerto **587** y envía el mensaje. Postfix verifica su contraseña con Dovecot (**SASL**).
2. Postfix ve que `leonel.mx` es **su** dominio (`mydestination`). Si no lo fuera, consultaría el **MX** en el DNS.
3. Postfix entrega el mensaje a Dovecot por **LMTP**, y Dovecot lo guarda en `/home/luis/Maildir/new/`.
4. Luis abre Thunderbird o Roundcube, que se conecta por **IMAP** y le muestra el correo.

---

## 4. Datos de tu servidor

```bash
DOMINIO=leonel.mx
OCT=$(ip -4 -o addr show enp0s8 | awk '{split($4,a,"[./]"); print a[4]}')
echo "Correo: @${DOMINIO} · Servidor: mail.${DOMINIO} (192.168.${OCT}.1)"
```

| Dato                      | Ejemplo                                               |
|---------------------------|-------------------------------------------------------|
| Dominio de correo         | `@leonel.mx`                                          |
| Nombre del servidor       | `mail.leonel.mx` (MX del dominio)                     |
| Cuentas de prueba         | `ana@leonel.mx`, `luis@leonel.mx`                     |
| Buzones                   | `/home/<usuario>/Maildir`                             |
| Certificado               | `/etc/ssl/lab/www.leonel.mx.crt` (incluye `mail.leonel.mx` en el SAN) |
| Webmail                   | `https://mail.leonel.mx`                              |

Comprueba lo que viene de la práctica de DNS:

```bash
dig @192.168.${OCT}.1 ${DOMINIO} MX +short       # 10 mail.leonel.mx.
dig @192.168.${OCT}.1 mail.${DOMINIO} +short     # 192.168.50.1
openssl x509 -in /etc/ssl/lab/www.${DOMINIO}.crt -noout -ext subjectAltName | grep -o "DNS:mail.${DOMINIO}"
```

---

## 5. Instalación (conexión temporal a internet)

### 5.1 Conectar la NAT solo para instalar

Igual que en la práctica Web: en VirtualBox, **Dispositivos → Red → Adaptador de red 1 → Conectar cable**.

```bash
sudo networkctl renew enp0s3
ip route | grep default        # default via 10.0.2.2 dev enp0s3
```

### 5.2 Postfix y Dovecot desde los repositorios de Ubuntu

Postfix hace dos preguntas al instalarse. Con `debconf-set-selections` las respondemos antes:

```bash
sudo debconf-set-selections <<EOF
postfix postfix/main_mailer_type select Internet Site
postfix postfix/mailname string ${DOMINIO}
EOF

sudo apt update
sudo apt install -y postfix dovecot-imapd dovecot-lmtpd \
  php8.5-intl php8.5-xml php8.5-zip php8.5-curl php8.5-gd
```

| Respuesta / paquete             | Para qué                                                                 |
|---------------------------------|--------------------------------------------------------------------------|
| `Internet Site`                 | Postfix envía y recibe directamente (sin servidor intermedio)            |
| `mailname = leonel.mx`          | Dominio que se agrega a los correos que salen del servidor               |
| `dovecot-imapd`, `dovecot-lmtpd` | IMAP para los clientes y LMTP para recibir de Postfix                   |
| `php8.5-intl`, `-xml`, `-zip`, `-curl`, `-gd` | Extensiones que Roundcube necesita, además de `mbstring` y `mysql`, que ya tienes de la práctica Web |

```bash
postconf -h mail_version              # 3.10.x
dovecot --version                     # 2.4.x
php -m | grep -E '^(intl|xml|zip|curl|gd|mbstring|pdo_mysql)$'
```

### 5.3 Roundcube 1.6.20 desde el sitio oficial

> ⚠️ **¿Por qué no `apt install roundcube`?** Ubuntu 26.04 ofrece Roundcube **1.6.11** en el repositorio *universe*, y esa versión tiene dos problemas:
> 1. **No funciona con PHP 8.5.** PHP 8.5 agregó la función `array_first()`, y Roundcube 1.6.11 intenta declararla otra vez. El resultado es una página en blanco y el error `PHP Fatal error: Cannot redeclare function array_first()`. Se corrigió en Roundcube **1.6.12**.
> 2. **Está desactualizada:** de la 1.6.12 a la 1.6.20 se publicaron decenas de correcciones de seguridad, incluidas fallas que se explotan **sin iniciar sesión**. *Universe* no tiene garantía de actualizaciones de seguridad.
>
> **Lección:** "está en los repositorios" no siempre significa "está al día". Antes de instalar, revisa la versión y su compatibilidad.

Descarga la última versión de la rama 1.6 (LTS) **y su firma**. Al momento de escribir este tutorial es la **1.6.20** (octubre de 2026); revisa en <https://roundcube.net/download> si hay una más nueva.

```bash
RC=1.6.20
cd /tmp
curl -fLO "https://github.com/roundcube/roundcubemail/releases/download/${RC}/roundcubemail-${RC}-complete.tar.gz"
curl -fLO "https://github.com/roundcube/roundcubemail/releases/download/${RC}/roundcubemail-${RC}-complete.tar.gz.asc"
```

Verifica la firma GPG. Roundcube firma cada paquete que publica:

```bash
curl -fsSL https://roundcube.net/download/pubkey.asc | gpg --import
gpg --verify "roundcubemail-${RC}-complete.tar.gz.asc" "roundcubemail-${RC}-complete.tar.gz"
```

✅ Debe decir **`Good signature`**. Compara la huella de la llave que muestra `gpg` con la que publica <https://roundcube.net/download>. Si dice `BAD signature`, **borra el archivo y no lo instales**.

> El paquete **complete** ya incluye todas las dependencias (PHP y JavaScript): no hace falta Composer ni internet en el servidor.

### 5.4 Desconectar internet otra vez

Desmarca **Conectar cable** en el adaptador 1 y comprueba:

```bash
ping -c 2 -W 2 1.1.1.1      # Debe fallar
```

---

## 6. Cuentas de correo

Usaremos **usuarios del sistema**: cada cuenta de correo es un usuario de Linux **sin terminal**, igual que `webmaster` en la práctica de SFTP.

```bash
sudo useradd -m -s /usr/sbin/nologin -c "Ana López"  ana
sudo useradd -m -s /usr/sbin/nologin -c "Luis Pérez" luis
sudo passwd ana
sudo passwd luis
```

El correo del sistema para `root` (avisos de cron, de apt, etc.) llegará a Ana:

```bash
echo "root: ana" | sudo tee -a /etc/aliases
sudo newaliases
```

> **Alternativa avanzada:** en servidores grandes se usan **usuarios virtuales**, que existen en MySQL o en un archivo y no en Linux. Aquí usamos usuarios del sistema para concentrarnos en el flujo del correo.

---

## 7. Postfix: enviar y recibir (SMTP)

### 7.1 Configuración principal (`main.cf`)

`postconf -e` modifica `/etc/postfix/main.cf` de forma segura, sin abrir el editor:

```bash
sudo cp /etc/postfix/main.cf /etc/postfix/main.cf.orig
sudo cp /etc/postfix/master.cf /etc/postfix/master.cf.orig

sudo postconf -e \
  "myhostname = mail.${DOMINIO}" \
  "mydomain = ${DOMINIO}" \
  'myorigin = $mydomain' \
  'mydestination = $myhostname, $mydomain, localhost.$mydomain, localhost' \
  "inet_interfaces = 127.0.0.1, 192.168.${OCT}.1" \
  'inet_protocols = ipv4' \
  'mynetworks = 127.0.0.0/8' \
  'smtpd_banner = $myhostname ESMTP' \
  'mailbox_transport = lmtp:unix:private/dovecot-lmtp' \
  "smtpd_tls_cert_file = /etc/ssl/lab/www.${DOMINIO}.crt" \
  "smtpd_tls_key_file = /etc/ssl/lab/www.${DOMINIO}.key" \
  'smtpd_tls_security_level = may' \
  'smtpd_tls_auth_only = yes' \
  'smtpd_tls_protocols = >=TLSv1.2' \
  'smtpd_sasl_type = dovecot' \
  'smtpd_sasl_path = private/auth' \
  'smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination' \
  'smtpd_helo_required = yes' \
  'disable_vrfy_command = yes' \
  'smtp_tls_security_level = may'
```

> Las líneas con **comillas simples** contienen `$mydomain` o `$myhostname`: son variables **de Postfix** y deben llegar tal cual. Las de **comillas dobles** usan `${DOMINIO}` y `${OCT}`, que son variables **de tu terminal**.

| Parámetro                    | Qué hace                                                                    |
|------------------------------|-----------------------------------------------------------------------------|
| `myhostname`                 | Nombre con el que el servidor se presenta: coincide con el MX y con el certificado |
| `mydestination`              | Dominios que se entregan **aquí**. Todo lo demás se considera "externo"      |
| `inet_interfaces`            | Igual que Kea, BIND y Nginx: solo la red del laboratorio y localhost         |
| `mynetworks = 127.0.0.0/8`   | Solo el propio servidor puede enviar sin contraseña. Los clientes de la red **deben autenticarse** |
| `smtpd_banner`               | No revela que es Postfix ni que corre en Ubuntu                              |
| `mailbox_transport`          | Entrega los correos locales a **Dovecot por LMTP**, que los guarda en Maildir |
| `smtpd_tls_*`                | TLS con el certificado de tu CA (el SAN ya incluye `mail.leonel.mx`)          |
| `smtpd_tls_auth_only`        | Prohíbe enviar la contraseña sin cifrar                                      |
| `smtpd_sasl_*`               | Postfix le pregunta las contraseñas a Dovecot                                |
| `reject_unauth_destination`  | **Anti relay abierto**: no reenvía correo a dominios ajenos sin autenticación |
| `disable_vrfy_command`       | Impide preguntar "¿existe el usuario X?" para descubrir cuentas              |

### 7.2 Puerto 587 (submission) para los usuarios (`master.cf`)

El puerto **25** es para que otros **servidores** te entreguen correo. Tus **usuarios** envían por el **587**, siempre con TLS y contraseña:

```bash
# Mapa: la dirección ana@leonel.mx solo puede usarla el usuario "ana"
echo "/^([^@]+)@${DOMINIO//./\\.}\$/   \${1}" | sudo tee /etc/postfix/login_maps.regexp
cat /etc/postfix/login_maps.regexp

sudo postconf -M submission/inet="submission inet n - n - - smtpd"
sudo postconf -P \
  "submission/inet/syslog_name=postfix/submission" \
  "submission/inet/smtpd_tls_security_level=encrypt" \
  "submission/inet/smtpd_sasl_auth_enable=yes" \
  "submission/inet/smtpd_tls_auth_only=yes" \
  "submission/inet/smtpd_sender_login_maps=regexp:/etc/postfix/login_maps.regexp" \
  "submission/inet/smtpd_client_restrictions=permit_sasl_authenticated,reject" \
  "submission/inet/smtpd_sender_restrictions=reject_sender_login_mismatch" \
  "submission/inet/smtpd_relay_restrictions=permit_sasl_authenticated,reject"
```

El mapa debe quedar así:

```
/^([^@]+)@leonel\.mx$/   ${1}
```

| Opción del puerto 587                         | Efecto                                                                 |
|-----------------------------------------------|------------------------------------------------------------------------|
| `smtpd_tls_security_level=encrypt`            | Sin STARTTLS no se acepta **nada**                                      |
| `smtpd_sasl_auth_enable=yes`                  | Pide usuario y contraseña                                               |
| `smtpd_client_restrictions=permit_sasl_authenticated,reject` | Sin autenticación no se puede enviar                    |
| `reject_sender_login_mismatch`                | **Anti suplantación**: Ana no puede enviar como `luis@leonel.mx`         |

### 7.3 Validar

```bash
sudo postfix check && echo "Postfix: configuración válida"
postconf -n | grep -E '^(myhostname|mydomain|mydestination|inet_interfaces|mynetworks|mailbox_transport|smtpd_tls_cert_file)'
postconf -M submission/inet
postconf -P submission/inet | head -n 8
```

> Todavía **no** reinicies Postfix: el socket `private/dovecot-lmtp` lo crea Dovecot en la sección siguiente.

---

## 8. Dovecot 2.4: buzones y lectura (IMAP)

> ⚠️ **Dovecot 2.4 no es compatible con la configuración de la 2.3.** Muchos parámetros cambiaron de nombre: `mail_location` ahora es `mail_driver` + `mail_path`, `disable_plaintext_auth` es `auth_allow_cleartext`, `ssl_cert = </ruta` es `ssl_server_cert_file = /ruta`, y las variables `%u`/`%n` ahora se escriben `%{user}` y `%{user | username}`. **Los tutoriales para la 2.3 que encuentres en internet no te van a funcionar.**

### 8.1 Un solo archivo para toda la práctica

El `dovecot.conf` de Ubuntu termina con `!include_try local.conf`. Pondremos **toda** nuestra configuración en ese archivo, sin tocar los de `conf.d/`:

```bash
sudo nano /etc/dovecot/local.conf
```

```
# /etc/dovecot/local.conf · Práctica 5 · Correo del laboratorio leonel.mx
# Sintaxis de Dovecot 2.4

# Escuchar solo en localhost y en la red del laboratorio
listen = 127.0.0.1, 192.168.50.1

# Buzones en formato Maildir dentro de la carpeta personal
mail_driver = maildir
mail_path = ~/Maildir
mail_inbox_path = ~/Maildir

# Autenticación: usuarios del sistema (PAM), nunca contraseñas sin cifrar
auth_allow_cleartext = no
auth_mechanisms = plain login

# TLS con el certificado firmado por la CA del laboratorio
ssl = required
ssl_server_cert_file = /etc/ssl/lab/www.leonel.mx.crt
ssl_server_key_file = /etc/ssl/lab/www.leonel.mx.key
ssl_min_protocol = TLSv1.2

# Carpetas especiales: se crean y suscriben automáticamente
namespace inbox {
  mailbox Drafts {
    auto = subscribe
  }
  mailbox Sent {
    auto = subscribe
  }
  mailbox Junk {
    auto = subscribe
  }
  mailbox Trash {
    auto = subscribe
  }
}

# Postfix entrega el correo a Dovecot por LMTP
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}

# Postfix valida las contraseñas con Dovecot (SASL)
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
```

| Parámetro (2.4)                 | Equivalente en 2.3                        | Qué hace                                         |
|---------------------------------|-------------------------------------------|--------------------------------------------------|
| `mail_driver` + `mail_path`     | `mail_location = maildir:~/Maildir`       | Formato y ubicación del buzón                    |
| `mail_inbox_path = ~/Maildir`   | (implícito en 2.3)                        | La bandeja de entrada va en la **raíz** del Maildir (`Maildir/new`). Reemplaza el `/var/mail/%{user}` de mbox que trae Ubuntu. Si se deja vacío, Dovecot 2.4 la crea aparte, en `Maildir/.INBOX` |
| `auth_allow_cleartext = no`     | `disable_plaintext_auth = yes`            | Sin TLS no se acepta la contraseña. Ya es el valor por defecto en 2.4; lo dejamos explícito |
| `ssl_server_cert_file`          | `ssl_cert = </ruta`                       | Certificado del servidor                         |
| `ssl = required`                | `ssl = required`                          | IMAP en el 143 exige STARTTLS                    |
| `auto = subscribe`              | `auto = subscribe`                        | Crea Enviados, Borradores, Papelera y Spam       |

> **Usuarios y contraseñas:** Ubuntu ya trae `passdb pam` y `userdb passwd` en `conf.d/auth-system.conf.ext`, es decir, los usuarios de Linux. No hace falta cambiarlo. Para iniciar sesión se usa el **nombre de usuario** (`ana`), no la dirección completa. Al entregar correo, el archivo `conf.d/20-lmtp.conf` de Ubuntu ya convierte `ana@leonel.mx` en `ana` con la nueva sintaxis de variables: `auth_username_format = %{user | username | lower}`.

### 8.2 Adaptar, validar e iniciar

```bash
sudo sed -i -e "s/leonel\.mx/${DOMINIO}/g" -e "s/192\.168\.50\./192.168.${OCT}./g" /etc/dovecot/local.conf
sudo doveconf -n > /dev/null && echo "Dovecot: configuración válida"
sudo doveconf -n | grep -E '^(listen|mail_driver|mail_path|mail_inbox_path|ssl )|_file = '
sudo systemctl restart dovecot
sudo systemctl restart postfix
ls -l /var/spool/postfix/private/ | grep -E 'auth|dovecot-lmtp'
```

✅ Deben existir los dos sockets: `auth` (`srw-rw---- postfix postfix`) y `dovecot-lmtp` (`srw------- postfix postfix`).

### 8.3 Firewall (si UFW está activo)

```bash
sudo ufw allow in on enp0s9 to any port 25,587,143,993 proto tcp comment 'Correo'
```

---

## 9. Ajustes al DNS

El registro `MX` ya existe desde la práctica de DNS. Agrega un registro **SPF**, que declara qué servidor puede enviar correo de tu dominio. Sin internet no tiene efecto práctico, pero es parte de cualquier dominio de correo bien configurado.

```bash
sudo rndc freeze "${DOMINIO}" 2>/dev/null           # Solo tiene efecto si activaste DDNS
echo '@               IN  TXT     "v=spf1 mx -all"' | sudo tee -a "/var/lib/bind/db.${DOMINIO}"
sudo nano "/var/lib/bind/db.${DOMINIO}"             # Sube el SERIAL
sudo named-checkzone "${DOMINIO}" "/var/lib/bind/db.${DOMINIO}"
sudo rndc thaw "${DOMINIO}" 2>/dev/null || sudo rndc reload "${DOMINIO}"
dig @192.168.${OCT}.1 ${DOMINIO} TXT +short          # "v=spf1 mx -all"
```

> `v=spf1 mx -all` significa: "solo los servidores del MX pueden enviar correo de `@leonel.mx`; rechaza todo lo demás".

---

## 10. Roundcube: webmail en `https://mail.leonel.mx`

### 10.1 El servidor confía en su propia CA

Roundcube se conecta a `mail.leonel.mx` por IMAP y SMTP con TLS, y PHP **verifica el certificado**. Para eso, el propio servidor debe confiar en tu CA, igual que los clientes en la práctica Web:

```bash
sudo cp "/etc/ssl/lab/ca-${DOMINIO}.crt" /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

### 10.2 Instalar los archivos

```bash
RC=1.6.20
sudo tar -xzf "/tmp/roundcubemail-${RC}-complete.tar.gz" -C /var/www
sudo mv "/var/www/roundcubemail-${RC}" /var/www/roundcube

# El código es de root y PHP (www-data) solo lo lee
sudo chown -R root:www-data /var/www/roundcube
sudo find /var/www/roundcube -type d -exec chmod 750 {} \;
sudo find /var/www/roundcube -type f -exec chmod 640 {} \;

# Solo logs/ y temp/ son escribibles por PHP
sudo chown -R www-data:www-data /var/www/roundcube/logs /var/www/roundcube/temp

# El instalador web no se necesita y es un riesgo dejarlo
sudo rm -rf /var/www/roundcube/installer
grep -m1 "RCMAIL_VERSION" /var/www/roundcube/program/include/iniset.php
```

| Carpeta                      | Contenido                                                 |
|------------------------------|-----------------------------------------------------------|
| `public_html/`               | **Única** carpeta visible desde la web (raíz de Nginx)     |
| `config/`                    | `config.inc.php`, con la contraseña de MySQL. **No** es visible desde la web |
| `logs/`, `temp/`             | Bitácoras y archivos temporales (escribibles por `www-data`) |
| `program/`, `vendor/`, `SQL/` | Código, dependencias y esquema de la base de datos        |

### 10.3 Base de datos

```bash
RC_DB_PASS=$(openssl rand -base64 18 | tr -d '/+=')
sudo mysql <<SQL
CREATE DATABASE IF NOT EXISTS roundcube CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'roundcube'@'localhost' IDENTIFIED BY '${RC_DB_PASS}';
GRANT ALL PRIVILEGES ON roundcube.* TO 'roundcube'@'localhost';
SQL
sudo mysql roundcube < /var/www/roundcube/SQL/mysql.initial.sql
sudo mysql -e "SHOW TABLES FROM roundcube;" | head
```

> El usuario `roundcube` tiene todos los permisos, pero **solo** sobre su propia base. Los necesita para que las actualizaciones de Roundcube puedan modificar sus tablas.

### 10.4 Configurar Roundcube

```bash
sudo tee /var/www/roundcube/config/config.inc.php > /dev/null <<'EOF'
<?php
// Roundcube · Práctica 5 · Laboratorio leonel.mx
$config = [];

// Base de datos (MySQL de la práctica Web)
$config['db_dsnw'] = 'mysql://roundcube:CLAVE_BD@localhost/roundcube';

// Servidores de correo: el nombre coincide con el certificado de la CA
$config['imap_host'] = 'tls://mail.leonel.mx:143';
$config['smtp_host'] = 'tls://mail.leonel.mx:587';
$config['smtp_user'] = '%u';
$config['smtp_pass'] = '%p';
$config['mail_domain'] = 'leonel.mx';

// Interfaz
$config['product_name'] = 'Webmail leonel.mx';
$config['skin'] = 'elastic';
$config['language'] = 'es_ES';
$config['plugins'] = ['archive', 'zipdownload'];

// Seguridad
$config['des_key'] = 'LLAVE_DES';
$config['enable_installer'] = false;
$config['log_logins'] = true;
$config['session_lifetime'] = 30;
$config['ip_check'] = true;
$config['support_url'] = '';
EOF

DES_KEY=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-24)
sudo sed -i -e "s/CLAVE_BD/${RC_DB_PASS}/" -e "s/LLAVE_DES/${DES_KEY}/" \
            -e "s/leonel\.mx/${DOMINIO}/g" /var/www/roundcube/config/config.inc.php
sudo chown root:www-data /var/www/roundcube/config/config.inc.php
sudo chmod 640 /var/www/roundcube/config/config.inc.php
sudo php -l /var/www/roundcube/config/config.inc.php
```

| Opción                      | Qué hace                                                                 |
|-----------------------------|--------------------------------------------------------------------------|
| `imap_host = tls://...:143` | IMAP con STARTTLS hacia `mail.leonel.mx`: el nombre coincide con el certificado |
| `smtp_host = tls://...:587` | Envía por submission con la **misma** contraseña del usuario (`%u`/`%p`) |
| `mail_domain`               | El usuario `ana` envía como `ana@leonel.mx`                               |
| `des_key`                   | Llave aleatoria de 24 caracteres que cifra la contraseña dentro de la sesión |
| `log_logins`                | Registra cada inicio de sesión en `logs/userlogins.log`                    |
| `ip_check`                  | La sesión se invalida si cambia la IP del cliente (dificulta el robo de sesión) |

> Usamos `mail.leonel.mx` y no `localhost` porque el certificado **no** incluye `localhost`. Con `localhost`, PHP rechazaría la conexión TLS.

### 10.5 Sitio en Nginx

```bash
sudo nano /etc/nginx/sites-available/mail.leonel.mx
```

```nginx
# ---------- HTTP: redirige a HTTPS ----------
server {
    listen 127.0.0.1:80;
    listen 192.168.50.1:80;
    server_name mail.leonel.mx;
    return 301 https://mail.leonel.mx$request_uri;
}

# ---------- HTTPS: Roundcube ----------
server {
    listen 127.0.0.1:443 ssl;
    listen 192.168.50.1:443 ssl;
    http2 on;
    server_name mail.leonel.mx;

    root  /var/www/roundcube/public_html;
    index index.php;

    ssl_certificate     /etc/ssl/lab/www.leonel.mx.crt;
    ssl_certificate_key /etc/ssl/lab/www.leonel.mx.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    server_tokens off;
    client_max_body_size 12m;
    add_header Strict-Transport-Security "max-age=86400" always;
    add_header X-Content-Type-Options    "nosniff" always;
    add_header Referrer-Policy           "same-origin" always;

    access_log /var/log/nginx/mail.leonel.mx.access.log;
    error_log  /var/log/nginx/mail.leonel.mx.error.log;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.5-fpm.sock;
    }

    location ~ /\. {
        deny all;
    }
}
```

> Roundcube trae su propio encabezado `X-Frame-Options`, así que no lo repetimos aquí.

Adapta, activa y ajusta el tamaño máximo de los adjuntos en PHP:

```bash
cd /etc/nginx/sites-available
[ "$DOMINIO" != "leonel.mx" ] && sudo mv mail.leonel.mx "mail.${DOMINIO}"
sudo sed -i -e "s/leonel\.mx/${DOMINIO}/g" -e "s/192\.168\.50\./192.168.${OCT}./g" "mail.${DOMINIO}"
sudo ln -sf "/etc/nginx/sites-available/mail.${DOMINIO}" /etc/nginx/sites-enabled/

sudo sed -i -e 's/^upload_max_filesize = .*/upload_max_filesize = 10M/' \
            -e 's/^post_max_size = .*/post_max_size = 12M/' /etc/php/8.5/fpm/php.ini
sudo nginx -t && sudo systemctl reload nginx
sudo systemctl restart php8.5-fpm
curl -s https://mail.${DOMINIO}/ | grep -oE '<title>[^<]*'
```

✅ Debe responder `<title>Webmail leonel.mx :: Bienvenido a Webmail leonel.mx`.

### 10.6 Actualizar la tabla de servicios

```bash
sudo mysql -e "UPDATE laboratorio.servicios
  SET software='Postfix 3.10 + Dovecot 2.4 + Roundcube 1.6', estado='Instalado' WHERE practica=5;"
```

Abre `https://www.leonel.mx`: las **cinco** prácticas aparecen como **Instalado**.

> **Actualizar Roundcube más adelante:** descarga y verifica la nueva versión 1.6.x como en la sección 5.3, descomprímela en `/tmp` y ejecuta `sudo /tmp/roundcubemail-X.Y.Z/bin/installto.sh /var/www/roundcube`. El script conserva tu configuración y actualiza la base de datos.

---

## 11. Pruebas de funcionamiento y seguridad

> En los clientes Linux usaremos `curl`, que habla SMTP e IMAP y ya confía en tu CA desde la práctica Web. Con `--user ana`, sin `:clave`, curl **pide la contraseña** y así no queda en el historial.

### Prueba 1 – Servicios y puertos (servidor)

```bash
systemctl is-active postfix dovecot nginx php8.5-fpm mysql
sudo ss -tlnp | grep -E ':(25|587|143|993) '
```

✅ **Éxito:**
- Todos los servicios aparecen como `active`.
- Los puertos `25` y `587` son de `master` (Postfix), y el `143` y el `993` de `dovecot`.
- Todos escuchan **solo** en `127.0.0.1` y `192.168.50.1`.

### Prueba 2 – TLS con el certificado de la CA (servidor o cliente)

```bash
openssl s_client -starttls smtp -connect mail.leonel.mx:587 -servername mail.leonel.mx </dev/null 2>/dev/null \
  | grep -E 'subject=|issuer=|Verify return code'
openssl s_client -connect mail.leonel.mx:993 -servername mail.leonel.mx </dev/null 2>/dev/null \
  | grep -E 'subject=|Verify return code'
```

✅ **Éxito:** `issuer=...CN=CA Laboratorio leonel.mx` y `Verify return code: 0 (ok)` en ambos puertos.

### Prueba 3 – Ana envía un correo a Luis (cliente Linux)

```bash
cat > correo.txt <<EOF
From: Ana López <ana@leonel.mx>
To: Luis Pérez <luis@leonel.mx>
Subject: Prueba de la practica 5
Date: $(date -R)

Hola Luis:
Este correo viajo por Postfix (587, TLS) y Dovecot (LMTP).
EOF

curl --ssl-reqd --url smtp://mail.leonel.mx:587 --user ana \
  --mail-from ana@leonel.mx --mail-rcpt luis@leonel.mx --upload-file correo.txt -v 2>&1 \
  | grep -E '^< 250|^< 235|STARTTLS'
```

✅ **Éxito:** aparecen `< 235 2.7.0 Authentication successful` y, al final, `< 250 2.0.0 Ok: queued as ...`.

### Prueba 4 – Luis lee su correo por IMAPS (cliente Linux)

```bash
curl --url "imaps://mail.leonel.mx/INBOX" --user luis -X 'SEARCH ALL'
curl --url "imaps://mail.leonel.mx/INBOX;MAILINDEX=1" --user luis
```

✅ **Éxito:** `SEARCH` responde `* SEARCH 1` y la segunda orden muestra el correo completo, con encabezados `Received:` que prueban el paso por Postfix y Dovecot.

### Prueba 5 – No es un relay abierto (cliente Linux)

Un desconocido, **sin autenticarse**, intenta usar tu servidor para enviar spam a otro dominio:

```bash
printf 'Subject: spam\n\nspam\n' > spam.txt
curl --url smtp://mail.leonel.mx:25 --mail-from spammer@ejemplo.com \
  --mail-rcpt victima@gmail.com --upload-file spam.txt
```

✅ **Éxito:** `curl: (55) RCPT failed: 554`. En el log aparece `554 5.7.1 <victima@gmail.com>: Relay access denied`. Un relay abierto termina en listas negras en cuestión de horas.

### Prueba 6 – Sin TLS no hay contraseña (cliente Linux)

> Hazla **desde un cliente**, no desde el servidor. Dovecot considera "local y segura" una conexión que sale de la misma IP del servidor, y ahí sí permitiría el login IMAP sin TLS.

```bash
curl --url smtp://mail.leonel.mx:587 --user ana --mail-from ana@leonel.mx \
  --mail-rcpt luis@leonel.mx --upload-file correo.txt
curl --url imap://mail.leonel.mx/ --user luis
```

✅ **Éxito:**
- SMTP responde `530 5.7.0 Must issue a STARTTLS command first`.
- IMAP rechaza el inicio de sesión: Dovecot anuncia `LOGINDISABLED` y curl termina con `curl: (67) Login denied`.

### Prueba 7 – Ana no puede hacerse pasar por Luis (cliente Linux)

```bash
sed 's/^From: .*/From: Luis Pérez <luis@leonel.mx>/' correo.txt > falso.txt
curl --ssl-reqd --url smtp://mail.leonel.mx:587 --user ana \
  --mail-from luis@leonel.mx --mail-rcpt luis@leonel.mx --upload-file falso.txt
```

✅ **Éxito:** falla con `553 5.7.1 <luis@leonel.mx>: Sender address rejected: not owned by user ana`.

### Prueba 8 – El buzón en disco y el recorrido en el log (servidor)

```bash
sudo ls -l /home/luis/Maildir/new/ /home/luis/Maildir/cur/
sudo journalctl --since "30 min ago" --no-pager | grep -E 'postfix/(submission|lmtp|qmgr)|dovecot: lmtp' | tail -n 8
```

✅ **Éxito:**
- El correo está en `Maildir/new/`, o en `Maildir/cur/` si Luis ya lo abrió.
- Las carpetas especiales (`.Sent`, `.Drafts`, etc.) se crean en disco la primera vez que se usan; por ejemplo, `.Sent` al enviar desde Roundcube.
- El log muestra el recorrido completo: `sasl_username=ana` → `relay=mail.leonel.mx[private/dovecot-lmtp]` → `status=sent (250 2.0.0 <luis@leonel.mx> ... Saved)`.

### Prueba 9 – Webmail (navegador del cliente)

1. Abre `http://mail.leonel.mx`. Debe redirigir a `https://mail.leonel.mx` con candado 🔒.
2. Inicia sesión como `luis`: verás el correo de Ana.
3. Responde el correo. Luego inicia sesión como `ana` y comprueba que llegó la respuesta.
4. En el servidor:

```bash
sudo tail -n 5 /var/www/roundcube/logs/userlogins.log
```

✅ **Éxito:** aparecen líneas `Successful login for luis (ID: ...) from 192.168.50.1xx`, con la IP que Kea le dio al cliente.

### Prueba 10 – Correo del sistema (servidor)

```bash
sudo sendmail -t <<EOF
To: root
Subject: Aviso de srv-dhcp

Este aviso de root llega a Ana gracias a /etc/aliases.
EOF
sleep 2; sudo ls /home/ana/Maildir/new/ | wc -l
```

✅ **Éxito:** Ana tiene un correo nuevo. Los avisos del servidor (cron, actualizaciones) ya tienen a dónde llegar.

---

## 12. Clientes de escritorio (Thunderbird / Outlook)

Para que el cliente no muestre advertencias, primero debe confiar en tu CA (práctica Web, sección 9).

| Parámetro               | Correo entrante (IMAP)          | Correo saliente (SMTP)          |
|-------------------------|---------------------------------|---------------------------------|
| Servidor                | `mail.leonel.mx`                | `mail.leonel.mx`                |
| Puerto                  | `993`                           | `587`                           |
| Seguridad               | **SSL/TLS**                     | **STARTTLS**                    |
| Autenticación           | Contraseña normal               | Contraseña normal               |
| Usuario                 | `luis`                          | `luis`                          |

> **Thunderbird en Linux** usa su propio almacén de certificados. Ve a **Ajustes → Privacidad y seguridad → Certificados → Gestionar certificados → Autoridades → Importar** y elige `ca-leonel.mx.crt`.

---

## 13. Creación de evidencias

### 13.1 Script de recolección

```bash
nano ~/evidencias_correo.sh
```

```bash
#!/usr/bin/env bash
# Recolector de evidencias - Correo: Postfix 3.10 + Dovecot 2.4 + Roundcube 1.6 (Ubuntu 26.04.1 LTS)
# Uso: sudo ./evidencias_correo.sh <dominio> <octeto> "<Nombre del alumno>"

set -uo pipefail

DOMINIO="${1:-leonel.mx}"
OCT="${2:-50}"
ALUMNO="${3:-Sin nombre}"
IFACE="${IFACE:-enp0s9}"
IP="192.168.${OCT}.1"
CA="/etc/ssl/lab/ca-${DOMINIO}.crt"
FECHA="$(date +%Y%m%d_%H%M%S)"
DIR="evidencias_correo_${FECHA}"

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

ev 01_sistema.txt          "cat /etc/os-release; uname -a; hostnamectl"
ev 02_versiones.txt        "postconf -h mail_version; dovecot --version; grep -m1 RCMAIL_VERSION /var/www/roundcube/program/include/iniset.php; dpkg -l postfix dovecot-core dovecot-imapd dovecot-lmtpd | grep '^ii'; dpkg -l 'roundcube*' 2>/dev/null | grep '^ii' || echo 'Paquete roundcube de Ubuntu: no instalado (correcto)'"
ev 03_servicios.txt        "systemctl is-active postfix dovecot nginx php8.5-fpm mysql"
ev 04_puertos.txt          "ss -tlnp | grep -E ':(25|587|143|993|443) '"
ev 05_postfix_main.txt     "postfix check && echo 'postfix check: OK'; postconf -n"
ev 06_postfix_submission.txt "postconf -M submission/inet; postconf -P submission/inet; cat /etc/postfix/login_maps.regexp"
ev 07_dovecot.txt          "doveconf -n"
ev 08_sockets.txt          "ls -l /var/spool/postfix/private/ | grep -E 'auth|dovecot-lmtp'"
ev 09_dns.txt              "dig @${IP} ${DOMINIO} MX +short; dig @${IP} mail.${DOMINIO} +short; dig @${IP} ${DOMINIO} TXT +short"
ev 10_tls.txt              "for p in 587 143; do echo \"--- STARTTLS \$p\"; openssl s_client -starttls \$( [ \$p = 587 ] && echo smtp || echo imap ) -connect ${IP}:\$p -servername mail.${DOMINIO} -CAfile ${CA} </dev/null 2>/dev/null | grep -E 'subject=|issuer=|Protocol|Verify return code'; done; echo '--- IMAPS 993'; openssl s_client -connect ${IP}:993 -servername mail.${DOMINIO} -CAfile ${CA} </dev/null 2>/dev/null | grep -E 'subject=|Protocol|Verify return code'"
ev 11_relay_abierto.txt    "printf 'Subject: spam\n\nspam\n' | curl -s --url smtp://${IP}:25 --mail-from spammer@ejemplo.com --mail-rcpt victima@gmail.com --upload-file - -v 2>&1 | grep -E '^< (220|250|454|554)|RCPT failed'"
ev 12_buzones.txt          "for u in ana luis; do echo \"--- \$u\"; ls -la /home/\$u/Maildir/ /home/\$u/Maildir/new/ 2>/dev/null; done"
ev 13_bitacora_correo.txt  "journalctl --since '3 hours ago' --no-pager | grep -E 'postfix/|dovecot' | grep -E 'sasl_username|status=sent|Saved|Relay access denied|not owned by user|imap-login|lmtp' | tail -n 80"
ev 14_roundcube.txt        "grep -E \"imap_host|smtp_host|mail_domain|product_name|enable_installer\" /var/www/roundcube/config/config.inc.php; ls -ld /var/www/roundcube/installer 2>&1; tail -n 20 /var/www/roundcube/logs/userlogins.log; curl -s --cacert ${CA} --resolve mail.${DOMINIO}:443:${IP} https://mail.${DOMINIO}/ | grep -oE '<title>[^<]*'"
ev 15_tabla_servicios.txt  "mysql -e 'SELECT practica, servicio, software, estado FROM laboratorio.servicios;'"

echo ">>> Capturando tráfico de correo durante 60 s en $IFACE. Envía y lee un correo desde el cliente AHORA..."
timeout 60 tcpdump -i "$IFACE" -n 'tcp port 25 or tcp port 587 or tcp port 143 or tcp port 993' -w "$DIR/16_correo.pcap" 2>/dev/null
ev 16_correo_resumen.txt   "tcpdump -n -r $DIR/16_correo.pcap 2>/dev/null | head -n 30; echo '--- Texto legible:'; tcpdump -n -A -r $DIR/16_correo.pcap 2>/dev/null | grep -aoE '(220 [[:print:]]+|EHLO [[:print:]]+|STARTTLS|\\* OK [[:print:]]+)' | sort -u"

# Integridad y empaquetado
( cd "$DIR" && sha256sum * > SHA256SUMS.txt )
tar -czf "${DIR}.tar.gz" "$DIR"
sha256sum "${DIR}.tar.gz" | tee "${DIR}.tar.gz.sha256"

echo
echo "✅ Evidencias generadas en: $DIR/"
echo "✅ Paquete: ${DIR}.tar.gz"
```

```bash
chmod +x ~/evidencias_correo.sh
sudo ~/evidencias_correo.sh "$DOMINIO" "$OCT" "Nombre Apellido"
```

En la captura verás en claro solo el saludo (`220 mail.leonel.mx ESMTP`), el `EHLO` y el `STARTTLS`. **Todo lo que sigue**, incluidos la contraseña y el contenido del correo, va cifrado.

### 13.2 Evidencias del cliente

```bash
{
  echo "Alumno: Nombre Apellido | Fecha: $(date)"
  ip -br addr
  resolvectl query mail.leonel.mx
  dig leonel.mx MX +short 2>/dev/null || resolvectl query -t MX leonel.mx
  curl --url "imaps://mail.leonel.mx/INBOX" --user luis -X 'SEARCH ALL'
  curl --url "imaps://mail.leonel.mx/INBOX;MAILINDEX=1;SECTION=HEADER.FIELDS%20(FROM%20TO%20SUBJECT%20DATE)" --user luis
} 2>&1 | tee evidencia_correo_cliente_$(hostname)_$(date +%Y%m%d_%H%M).txt
```

### 13.3 Capturas de pantalla recomendadas

1. Roundcube en `https://mail.leonel.mx` con el candado y la bandeja de entrada de Luis.
2. La respuesta de Luis en la bandeja de Ana.
3. `Relay access denied` (prueba 5) y `not owned by user ana` (prueba 7).
4. `https://www.leonel.mx` con las **cinco** prácticas como **Instalado**.
5. Thunderbird u Outlook configurado (opcional).

---

## 14. Solución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| `doveconf: Fatal: Unknown setting: mail_location` (u otro parámetro) | Usaste sintaxis de Dovecot 2.3 | Revisa la tabla de equivalencias de la sección 8.1 |
| `status=deferred (connect to ...private/dovecot-lmtp: No such file)` | Dovecot no creó el socket LMTP | `sudo doveconf -n \| grep -A4 'service lmtp'` y `sudo systemctl restart dovecot` |
| `SASL authentication failure: cannot connect to Dovecot auth socket` | Falta el socket `private/auth` | Revisa el bloque `service auth` en `local.conf` |
| `535 5.7.8 Authentication failed` | Usuario o contraseña incorrectos | `sudo doveadm auth test ana` prueba la contraseña directamente con Dovecot |
| `554 5.7.1 ... Relay access denied` al enviar desde Roundcube o Thunderbird | El cliente envía por el 25 sin autenticación | Usa el puerto **587** con STARTTLS y usuario/contraseña |
| `553 ... not owned by user` | El remitente no coincide con el usuario | Es la protección anti suplantación: envía con tu propia dirección |
| Roundcube: `Connection to IMAP server failed` | El certificado no es confiable para PHP o el nombre no resuelve | Sección 10.1 (`update-ca-certificates`) y `resolvectl query mail.<dominio>` en el servidor |
| Roundcube: `SMTP Error (250): Authentication failed` | `smtp_user`/`smtp_pass` mal escritos | Deben ser `'%u'` y `'%p'` |
| Roundcube: `DATABASE ERROR: CONNECTION FAILED!` | La contraseña de `db_dsnw` no coincide con la de MySQL | Cámbiala con `sudo mysql -e "ALTER USER 'roundcube'@'localhost' IDENTIFIED BY '...';"` y escríbela igual en `config.inc.php` |
| Página en blanco; log: `Cannot redeclare function array_first()` | Instalaste el paquete `roundcube` 1.6.11 de Ubuntu, que no es compatible con PHP 8.5 | `sudo apt purge 'roundcube*'` e instala la versión oficial (secciones 5.3 y 10.2) |
| `Permission denied` en `logs/` o `temp/` de Roundcube | Esas carpetas no son de `www-data` | `sudo chown -R www-data:www-data /var/www/roundcube/{logs,temp}` |
| `postfix/smtpd: warning: cannot get RSA private key` | Ruta de la llave incorrecta | `ls -l /etc/ssl/lab/` y revisa `smtpd_tls_key_file` |
| El correo no aparece en Maildir, pero Postfix dice `sent` | Revisa el log de Dovecot | `sudo journalctl -u dovecot --since "10 min ago"` |
| `mailq` muestra correos atascados | Entrega pendiente o fallida | `sudo postqueue -p`; tras corregir, `sudo postqueue -f` |

---

## 15. Rúbrica sugerida

| Criterio                                                                      | Puntos |
|-------------------------------------------------------------------------------|:------:|
| Paquetes instalados; Roundcube oficial con firma verificada; servidor sin internet | 5   |
| Postfix: `main.cf` correcto y `postfix check` sin errores                      | 10     |
| Puerto 587: TLS obligatorio, SASL y anti suplantación (`not owned by user`)    | 15     |
| Dovecot 2.4: `local.conf` válido, Maildir, TLS obligatorio, LMTP y SASL        | 15     |
| **No es relay abierto** (`Relay access denied`)                                | 10     |
| Correo de Ana a Luis entregado y leído por IMAPS                               | 10     |
| Roundcube funcionando en `https://mail.<dominio>` con login registrado          | 15     |
| **Continuidad:** MX/SPF en DNS, certificado de la CA y tabla con las 5 prácticas | 10   |
| Paquete de evidencias con hashes verificables                                  | 5      |
| Reporte: recorrido de un correo (SMTP → LMTP → IMAP) y diferencia entre 25 y 587 | 5    |
| **Total**                                                                     | **100** |

---

## Cierre de la serie

Con esta práctica, tu servidor `srv-dhcp.leonel.mx` ofrece **cinco servicios integrados**, todos sin internet y todos cifrados donde importa:

| # | Servicio | Software | Nombre | Puerto(s) |
|:-:|----------|----------|--------|-----------|
| 1 | DHCP | Kea 3.0 | — | 67/udp |
| 2 | DNS | BIND 9.20 | `ns1.leonel.mx` | 53 |
| 3 | Web | Nginx 1.28 + PHP 8.5 + MySQL 8.4 | `www.leonel.mx` | 80 → 443 |
| 4 | SFTP | OpenSSH 10.2 | `ftp.leonel.mx` | 22 |
| 5 | Correo | Postfix 3.10 + Dovecot 2.4 + Roundcube 1.6 | `mail.leonel.mx` | 25, 587, 143, 993, 443 |

### Referencias

- Postfix – `postconf(5)`, *SASL_README*, *TLS_README*: <https://www.postfix.org/documentation.html>
- Dovecot 2.4 – *Upgrading from 2.3 to 2.4* y referencia de configuración: <https://doc.dovecot.org/2.4.2/>
- Roundcube – Descargas y firmas: <https://roundcube.net/download> · `config/defaults.inc.php`: <https://github.com/roundcube/roundcubemail/wiki/Configuration>
- PHP 8.5 – nuevas funciones `array_first()` / `array_last()`: <https://php.watch/versions/8.5/array_first-array_last>
- RFC 5321 (SMTP), RFC 6409 (Submission), RFC 9051 (IMAP4rev2), RFC 7208 (SPF), RFC 2033 (LMTP)