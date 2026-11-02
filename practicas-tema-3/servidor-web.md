# Servidor Web con Nginx, PHP 8.5 y MySQL en Ubuntu Server 26.04.1 LTS

> **Continuación de:** *Servidor DHCP (Kea)* → *Servidor DNS (BIND 9)*
> **Sistema:** Ubuntu Server **26.04.1 LTS** · Nginx **1.28** · PHP **8.5** · MySQL **8.4 LTS** · OpenSSL **3.5**
> **Plataforma:** máquinas virtuales en Oracle VirtualBox 7.x
> **Modo de trabajo:** servidor **sin conexión a internet**, con HTTPS mediante una **CA propia** creada con OpenSSL
> **Nivel:** intermedio · **Duración estimada:** 120–150 min

---

## Índice

1. [Objetivo](#1-objetivo)
2. [Continuidad con las prácticas anteriores](#2-continuidad-con-las-prácticas-anteriores)
3. [Datos de tu servidor](#3-datos-de-tu-servidor)
4. [Instalación (conexión temporal a internet)](#4-instalación-conexión-temporal-a-internet)
5. [MySQL: base de datos del sitio](#5-mysql-base-de-datos-del-sitio)
6. [Certificados con OpenSSL: tu propia CA](#6-certificados-con-openssl-tu-propia-ca)
7. [El sitio: archivos y PHP](#7-el-sitio-archivos-y-php)
8. [Nginx: HTTP, HTTPS y PHP-FPM](#8-nginx-http-https-y-php-fpm)
9. [Los clientes confían en tu CA](#9-los-clientes-confían-en-tu-ca)
10. [Pruebas de funcionamiento](#10-pruebas-de-funcionamiento)
11. [Creación de evidencias](#11-creación-de-evidencias)
12. [Solución de problemas](#12-solución-de-problemas)
13. [Rúbrica sugerida](#13-rúbrica-sugerida)

---

## 1. Objetivo

Al terminar esta práctica, el estudiante podrá:

- Instalar un stack **LEMP** (Linux, Nginx, MySQL, PHP) en Ubuntu Server 26.04.1.
- Crear su propia **autoridad certificadora (CA)** con OpenSSL y emitir un certificado para su dominio.
- Publicar un sitio en **`https://www.leonel.mx`**, el nombre creado en la práctica de DNS, con HTTP/2 y redirección automática de HTTP a HTTPS.
- Conectar PHP 8.5 con MySQL 8.4 aplicando el principio de **mínimo privilegio**.
- Hacer que los clientes, que reciben su IP del DHCP y resuelven con tu DNS, confíen en tu CA y vean el candado 🔒.
- Generar un paquete de evidencias verificable.

---

## 2. Continuidad con las prácticas anteriores

| Práctica | Qué dejó listo                                              | Cómo lo usa esta práctica                                   |
|:--------:|-------------------------------------------------------------|-------------------------------------------------------------|
| 1 · DHCP | Los clientes reciben IP `192.168.50.100–200` y el DNS `192.168.50.1` | El cliente abre el sitio sin configurar nada a mano  |
| 2 · DNS  | `www.leonel.mx` → CNAME → `srv-dhcp.leonel.mx` → `192.168.50.1` | Nginx responde a ese nombre, y el certificado se emite para él |
| **3 · Web** | Sitio HTTPS + PHP + MySQL                                | —                                                           |
| 4 · FTP  | (siguiente)                                                  | Subirá archivos a `/var/www/leonel.mx/public`, la carpeta que creas aquí |
| 5 · Correo | (siguiente)                                                | Reutilizará el certificado: ya incluye `mail.leonel.mx`      |

```
 Cliente (IP por Kea)                         srv-dhcp.leonel.mx · 192.168.50.1
 ┌──────────────────┐   1. ¿www.leonel.mx?    ┌──────────────────────────────────┐
 │ navegador / curl │ ──────────────────────▶ │ BIND  → 192.168.50.1             │
 │                  │   2. HTTPS :443         │                                  │
 │ confía en la CA  │ ──────────────────────▶ │ Nginx ──▶ PHP-FPM 8.5 ──▶ MySQL  │
 │ "CA Laboratorio" │ ◀── página + 🔒 ─────── │ certificado firmado por tu CA    │
 └──────────────────┘                         └──────────────────────────────────┘
```

> 💡 **¿Por qué la Web va después del DNS?** Un certificado HTTPS se emite para un **nombre**, no para una IP suelta, y el navegador compara ese nombre con el que escribiste. Sin DNS no hay `www.leonel.mx`, y sin ese nombre el certificado no tiene contra qué validarse.

---

## 3. Datos de tu servidor

Define las mismas variables de la práctica de DNS. Las usarás en muchos comandos:

```bash
DOMINIO=leonel.mx
OCT=$(ip -4 -o addr show enp0s8 | awk '{split($4,a,"[./]"); print a[4]}')
echo "Sitio: https://www.${DOMINIO} · IP: 192.168.${OCT}.1"
```

| Dato                        | Ejemplo                               |
|-----------------------------|---------------------------------------|
| Sitio                       | `https://www.leonel.mx`               |
| IP del servidor web         | `192.168.50.1` (adaptador 3, `enp0s9`) |
| Carpeta del sitio           | `/var/www/leonel.mx/public`           |
| Base de datos / usuario     | `laboratorio` / `webapp`              |
| Certificados                | `/etc/ssl/lab/`                       |

Comprueba que el DNS de la práctica anterior responde:

```bash
resolvectl query www.${DOMINIO}
```

Debe responder `192.168.50.1` (vía `srv-dhcp.leonel.mx`). Si falla, vuelve a la práctica de DNS antes de seguir.

---

## 4. Instalación (conexión temporal a internet)

### 4.1 Conectar la NAT solo para instalar

En la práctica de DNS desconectaste el adaptador 1. Conéctalo de nuevo un momento. En VirtualBox, con la VM encendida, ve a **Dispositivos → Red → Adaptador de red 1** y marca **Conectar cable**.

```bash
sudo networkctl renew enp0s3
ip route | grep default          # Debe aparecer: default via 10.0.2.2 dev enp0s3
```

> El servidor ahora resuelve nombres con **tu** BIND, que no tiene internet (`dnssec-validation no` y sin reenviadores). Para que `apt` encuentre los repositorios, BIND necesita salir a internet mientras la NAT está conectada, y lo hace solo: consulta directamente a los servidores raíz. Si `apt update` falla con *Temporary failure resolving*, ejecuta `sudo resolvectl dns enp0s3 10.0.2.3`. Ese cambio es temporal y se pierde al reiniciar o al desconectar la NAT.

### 4.2 Instalar los paquetes

```bash
sudo apt update
sudo apt install -y nginx php8.5-fpm php8.5-mysql php8.5-mbstring mysql-server
```

| Paquete           | Contiene                                                        |
|-------------------|-----------------------------------------------------------------|
| `nginx`           | Servidor web                                                    |
| `php8.5-fpm`      | PHP 8.5 como servicio FastCGI. Nginx **no** ejecuta PHP: se lo pasa a FPM |
| `php8.5-mysql`    | Extensión PDO para MySQL                                        |
| `php8.5-mbstring` | Manejo correcto de texto UTF-8 (acentos y ñ)                    |
| `mysql-server`    | MySQL 8.4 LTS                                                   |

Verifica las versiones instaladas:

```bash
nginx -v                 # nginx/1.28.x (Ubuntu)
php -v | head -n 1       # PHP 8.5.x
mysqld --version         # Ver 8.4.x
openssl version          # OpenSSL 3.5.x
```

> 💡 **Clientes Linux:** si quieres probar con `curl` desde un cliente que no lo tenga, instálalo ahora en él con `sudo apt install -y curl`, mientras tenga una conexión temporal.

### 4.3 Desconectar internet otra vez

Desmarca **Conectar cable** en el adaptador 1. Después marca `enp0s3` como **opcional**: así el arranque del servidor no espera a una interfaz que ya no usa.

```bash
sudo sed -i '/^    enp0s3:/a\      optional: true' /etc/netplan/60-lab-dhcp.yaml
sudo sed -n '/enp0s3:/,/enp0s8:/p' /etc/netplan/60-lab-dhcp.yaml
sudo netplan apply
ping -c 2 -W 2 1.1.1.1          # Debe fallar: sin internet
```

Salida esperada del `sed -n`:

```yaml
    enp0s3:              # Adaptador 1 - NAT (desconectado en esta práctica)
      optional: true
      dhcp4: true
    enp0s8:              # Adaptador 2 - Puente: red de prácticas 192.168.1.0/24
```

---

## 5. MySQL: base de datos del sitio

En Ubuntu, el usuario `root` de MySQL se autentica con el usuario `root` del sistema (`auth_socket`): `sudo mysql` entra sin contraseña. Además, MySQL escucha **solo en `127.0.0.1`**. Mantenlo así, porque la aplicación está en el mismo servidor.

### 5.1 Contraseña de la aplicación

Genera una contraseña aleatoria y anótala:

```bash
DB_PASS=$(openssl rand -base64 18 | tr -d '/+=')
echo "Contraseña de webapp: ${DB_PASS}"
```

### 5.2 Endurecer MySQL y crear la base

```bash
sudo mysql <<SQL
-- Seguridad básica (equivalente a mysql_secure_installation)
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;

-- Base de datos y usuario de la aplicación (mínimo privilegio)
CREATE DATABASE IF NOT EXISTS laboratorio
  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER IF NOT EXISTS 'webapp'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT SELECT, INSERT, UPDATE, DELETE ON laboratorio.* TO 'webapp'@'localhost';

USE laboratorio;
CREATE TABLE IF NOT EXISTS servicios (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  practica    INT          NOT NULL,
  servicio    VARCHAR(40)  NOT NULL,
  software    VARCHAR(60)  NOT NULL,
  nombre_dns  VARCHAR(100) NOT NULL,
  estado      ENUM('Instalado','Pendiente') NOT NULL DEFAULT 'Pendiente'
);
INSERT INTO servicios (practica, servicio, software, nombre_dns, estado) VALUES
  (1, 'DHCP',     'Kea 3.0',                          'srv-dhcp', 'Instalado'),
  (2, 'DNS',      'BIND 9.20',                        'ns1',      'Instalado'),
  (3, 'Web',      'Nginx 1.28 + PHP 8.5 + MySQL 8.4', 'www',      'Instalado'),
  (4, 'FTP/SFTP', 'OpenSSH / vsftpd',                 'ftp',      'Pendiente'),
  (5, 'Correo',   'Postfix + Dovecot',                'mail',     'Pendiente');
SQL
```

> El usuario `webapp` puede leer y modificar **datos**, pero **no** puede borrar tablas ni crear usuarios. Si alguien explotara una falla en la aplicación, el daño quedaría limitado.

Comprueba:

```bash
sudo mysql -e "SELECT practica, servicio, estado FROM laboratorio.servicios;"
sudo mysql -e "SHOW GRANTS FOR 'webapp'@'localhost';"
```

---

## 6. Certificados con OpenSSL: tu propia CA

Sin internet no puedes usar Let's Encrypt, que además solo emite certificados para dominios públicos que controles. En su lugar crearás **tu propia autoridad certificadora (CA)**:

```
 CA Laboratorio leonel.mx  (ca-leonel.mx.crt, válida 10 años)   ← los clientes confían en ESTA
        │ firma
        ▼
 www.leonel.mx  (www.leonel.mx.crt, válido 397 días)            ← lo usa Nginx (y luego FTP y correo)
   SAN: leonel.mx, www, srv-dhcp, ftp, mail, 192.168.50.1
```

> 💡 **¿Por qué una CA y no un certificado autofirmado?** Con un autofirmado, cada cliente tendría que aceptar una excepción para **cada** certificado. Con una CA, el cliente confía **una sola vez** en ella y acepta todo lo que firme. Las prácticas de FTP y Correo usarán este mismo certificado sin pasos extra en los clientes.

### 6.1 Crear la CA

```bash
sudo mkdir -p /etc/ssl/lab
cd /etc/ssl/lab

sudo openssl req -x509 -new -newkey rsa:4096 -noenc -sha256 -days 3650 \
  -keyout "ca-${DOMINIO}.key" -out "ca-${DOMINIO}.crt" \
  -subj "/C=MX/O=Laboratorio ${DOMINIO}/CN=CA Laboratorio ${DOMINIO}" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

sudo chmod 600 "ca-${DOMINIO}.key"
```

| Opción              | Significado                                                           |
|---------------------|-----------------------------------------------------------------------|
| `-x509 -new`        | Crea directamente un certificado (no una solicitud)                   |
| `-newkey rsa:4096`  | Llave RSA de 4096 bits para la CA                                     |
| `-noenc`            | La llave no lleva contraseña (en OpenSSL 3 reemplaza a `-nodes`)       |
| `CA:TRUE,pathlen:0` | Es una CA, pero no puede crear CAs intermedias                        |
| `keyCertSign`       | Su única función es **firmar** certificados                           |

> ⚠️ `ca-leonel.mx.key` es la llave más importante del laboratorio: quien la tenga puede firmar certificados en los que tus clientes confiarán. Por eso tiene permisos `600` y **nunca** se copia a otro equipo. Al cliente solo se le entrega el `.crt`.

### 6.2 Crear el certificado del servidor

Primero define las extensiones. El **SAN** (*Subject Alternative Name*) es la lista de nombres válidos para el certificado. Los navegadores modernos **solo** revisan el SAN e ignoran el CN.

```bash
sudo tee "www.${DOMINIO}.ext" > /dev/null <<EOF
basicConstraints       = critical, CA:FALSE
keyUsage               = critical, digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth
subjectAltName         = DNS:${DOMINIO}, DNS:www.${DOMINIO}, DNS:srv-dhcp.${DOMINIO}, DNS:ftp.${DOMINIO}, DNS:mail.${DOMINIO}, IP:192.168.${OCT}.1
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer
EOF
```

Después crea la llave, la solicitud (CSR) y firma con tu CA:

```bash
# Llave y solicitud de firma (CSR)
sudo openssl req -new -newkey rsa:2048 -noenc \
  -keyout "www.${DOMINIO}.key" -out "www.${DOMINIO}.csr" \
  -subj "/C=MX/O=Laboratorio ${DOMINIO}/CN=www.${DOMINIO}"

# La CA firma la solicitud
sudo openssl x509 -req -in "www.${DOMINIO}.csr" \
  -CA "ca-${DOMINIO}.crt" -CAkey "ca-${DOMINIO}.key" -CAcreateserial \
  -days 397 -sha256 -extfile "www.${DOMINIO}.ext" \
  -out "www.${DOMINIO}.crt"

sudo chmod 600 "www.${DOMINIO}.key"
sudo chmod 644 "ca-${DOMINIO}.crt" "www.${DOMINIO}.crt"
ls -l /etc/ssl/lab/
```

> **¿Por qué 397 días?** Desde 2020, Apple, Google y Mozilla rechazan certificados de servidor con más de 398 días de vigencia. Con 397 funciona en cualquier navegador.

### 6.3 Verificar los certificados

```bash
sudo openssl verify -CAfile "ca-${DOMINIO}.crt" "www.${DOMINIO}.crt"
openssl x509 -in "www.${DOMINIO}.crt" -noout -subject -issuer -dates -ext subjectAltName
openssl x509 -in "ca-${DOMINIO}.crt" -noout -fingerprint -sha256
```

Salida esperada (las fechas varían):

```
www.leonel.mx.crt: OK
subject=C=MX, O=Laboratorio leonel.mx, CN=www.leonel.mx
issuer=C=MX, O=Laboratorio leonel.mx, CN=CA Laboratorio leonel.mx
notBefore=...
notAfter=...
X509v3 Subject Alternative Name:
    DNS:leonel.mx, DNS:www.leonel.mx, DNS:srv-dhcp.leonel.mx, DNS:ftp.leonel.mx, DNS:mail.leonel.mx, IP Address:192.168.50.1
sha256 Fingerprint=AB:CD:...
```

Anota la **huella SHA-256** de la CA (`Fingerprint`). En la sección 9 la compararás en el cliente, antes de confiar en el certificado.

---

## 7. El sitio: archivos y PHP

### 7.1 Estructura de carpetas

```
/var/www/leonel.mx/
├── config.php              ← credenciales de MySQL (FUERA de la carpeta pública)
└── public/                 ← raíz web: solo esto es visible desde el navegador
    ├── index.php
    └── ca-leonel.mx.crt    ← certificado público de la CA, para que lo descarguen los clientes
```

```bash
sudo mkdir -p "/var/www/${DOMINIO}/public"
sudo cp "/etc/ssl/lab/ca-${DOMINIO}.crt" "/var/www/${DOMINIO}/public/"
```

### 7.2 Credenciales fuera de la raíz web

```bash
sudo tee "/var/www/${DOMINIO}/config.php" > /dev/null <<EOF
<?php
// Credenciales de la base de datos. Este archivo NO está dentro de public/
return [
    'dsn'  => 'mysql:host=localhost;dbname=laboratorio;charset=utf8mb4',
    'user' => 'webapp',
    'pass' => '${DB_PASS}',
];
EOF
```

> Si cerraste la sesión y perdiste `DB_PASS`, edita el archivo y escribe la contraseña a mano.

### 7.3 La página principal

```bash
sudo nano "/var/www/${DOMINIO}/public/index.php"
```

```php
<?php
declare(strict_types=1);

$config  = require __DIR__ . '/../config.php';
$dominio = $_SERVER['SERVER_NAME'] ?? 'localhost';
$https   = ($_SERVER['HTTPS'] ?? '') === 'on';

function e(string $s): string
{
    return htmlspecialchars($s, ENT_QUOTES, 'UTF-8');
}

try {
    $pdo = new PDO($config['dsn'], $config['user'], $config['pass'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ]);
    $mysql     = (string) $pdo->query('SELECT VERSION()')->fetchColumn();
    $servicios = $pdo->query(
        'SELECT practica, servicio, software, nombre_dns, estado FROM servicios ORDER BY practica'
    )->fetchAll(PDO::FETCH_ASSOC);
    $error = false;
} catch (PDOException $ex) {
    error_log('Error de MySQL: ' . $ex->getMessage());   // El detalle va al log, no al visitante
    $mysql     = 'sin conexión';
    $servicios = [];
    $error     = true;
}
?>
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><?= e($dominio) ?> · Laboratorio</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 860px; margin: 2rem auto; padding: 0 1rem; color: #1f2933; }
    .ok { color: #137333; } .no { color: #b3261e; }
    table { border-collapse: collapse; width: 100%; margin-top: 1rem; }
    th, td { border: 1px solid #d0d7de; padding: .45rem .6rem; text-align: left; }
    th { background: #f3f4f6; }
    code { background: #f3f4f6; padding: .1rem .3rem; border-radius: 4px; }
  </style>
</head>
<body>
  <h1><?= e($dominio) ?></h1>
  <p>Servidor web del laboratorio de Administración de servidores.</p>
  <ul>
    <li>Conexión:
      <?= $https ? '<span class="ok">HTTPS 🔒</span>' : '<span class="no">HTTP sin cifrar</span>' ?>
      · <?= e($_SERVER['SERVER_PROTOCOL'] ?? '') ?></li>
    <li>Tu IP (entregada por Kea): <code><?= e($_SERVER['REMOTE_ADDR'] ?? '') ?></code></li>
    <li>Servidor: <code><?= e(gethostname() ?: '') ?></code>
      · PHP <code><?= e(PHP_VERSION) ?></code>
      · MySQL <code><?= e($mysql) ?></code></li>
  </ul>

  <?php if ($error): ?>
    <p class="no">No fue posible conectar con la base de datos. Revisa el log del servidor.</p>
  <?php endif; ?>

  <h2>Servicios del laboratorio</h2>
  <table>
    <tr><th>#</th><th>Servicio</th><th>Software</th><th>Nombre DNS</th><th>Estado</th></tr>
    <?php foreach ($servicios as $s): ?>
      <tr>
        <td><?= (int) $s['practica'] ?></td>
        <td><?= e($s['servicio']) ?></td>
        <td><?= e($s['software']) ?></td>
        <td><code><?= e($s['nombre_dns'] . '.' . $dominio) ?></code></td>
        <td class="<?= $s['estado'] === 'Instalado' ? 'ok' : 'no' ?>"><?= e($s['estado']) ?></td>
      </tr>
    <?php endforeach; ?>
  </table>
</body>
</html>
```

**Buenas prácticas en este código:**

| Práctica                               | Dónde                                                    |
|----------------------------------------|----------------------------------------------------------|
| Credenciales fuera de la raíz web      | `require __DIR__ . '/../config.php'`                     |
| Escapar toda salida (evita XSS)        | función `e()` con `htmlspecialchars`                     |
| No mostrar errores internos al visitante | `error_log()`; el usuario solo ve un mensaje genérico  |
| El dominio no está "quemado" en el código | `$_SERVER['SERVER_NAME']`, así sirve para cualquier alumno |

### 7.4 Permisos

Nginx y PHP-FPM corren como `www-data` y solo necesitan **leer**:

```bash
sudo chown -R root:www-data "/var/www/${DOMINIO}"
sudo find "/var/www/${DOMINIO}" -type d -exec chmod 750 {} \;
sudo find "/var/www/${DOMINIO}" -type f -exec chmod 640 {} \;
ls -la "/var/www/${DOMINIO}" "/var/www/${DOMINIO}/public"
```

> En la práctica de FTP crearás un usuario con permiso de **escritura** solo en `public/`.

### 7.5 Ocultar la versión de PHP

```bash
sudo sed -i 's/^expose_php = .*/expose_php = Off/' /etc/php/8.5/fpm/php.ini
grep '^expose_php' /etc/php/8.5/fpm/php.ini
sudo systemctl restart php8.5-fpm
```

---

## 8. Nginx: HTTP, HTTPS y PHP-FPM

### 8.1 Desactivar el sitio por defecto

El sitio `default` escucha en **todas** las interfaces, incluida la `192.168.1.x` de la escuela. Desactívalo:

```bash
sudo rm /etc/nginx/sites-enabled/default
```

> El archivo original se queda en `/etc/nginx/sites-available/default` por si lo necesitas.

### 8.2 Configurar el sitio

```bash
sudo nano /etc/nginx/sites-available/leonel.mx
```

```nginx
# ---------- HTTP: solo redirige a HTTPS ----------
server {
    listen 127.0.0.1:80;
    listen 192.168.50.1:80;
    server_name leonel.mx www.leonel.mx srv-dhcp.leonel.mx;

    # Excepción: el certificado de la CA se descarga por HTTP,
    # porque el cliente todavía no confía en HTTPS.
    location = /ca-leonel.mx.crt {
        root /var/www/leonel.mx/public;
        default_type application/x-x509-ca-cert;
    }

    location / {
        return 301 https://www.leonel.mx$request_uri;
    }
}

# ---------- HTTPS ----------
server {
    listen 127.0.0.1:443 ssl;
    listen 192.168.50.1:443 ssl;
    http2 on;
    server_name leonel.mx www.leonel.mx srv-dhcp.leonel.mx;

    root  /var/www/leonel.mx/public;
    index index.php index.html;

    # Certificado firmado por tu CA
    ssl_certificate     /etc/ssl/lab/www.leonel.mx.crt;
    ssl_certificate_key /etc/ssl/lab/www.leonel.mx.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;

    # Seguridad
    server_tokens off;
    add_header Strict-Transport-Security "max-age=86400" always;
    add_header X-Content-Type-Options    "nosniff" always;
    add_header X-Frame-Options           "SAMEORIGIN" always;
    add_header Referrer-Policy           "strict-origin-when-cross-origin" always;

    access_log /var/log/nginx/leonel.mx.access.log;
    error_log  /var/log/nginx/leonel.mx.error.log;

    location / {
        try_files $uri $uri/ =404;
    }

    # PHP: Nginx entrega los .php a PHP-FPM por un socket Unix
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.5-fpm.sock;
    }

    # Bloquear archivos ocultos (.git, .env, .htaccess...)
    location ~ /\. {
        deny all;
    }
}
```

| Directiva                     | Qué hace                                                                   |
|-------------------------------|----------------------------------------------------------------------------|
| `listen 192.168.50.1:443 ssl` | Igual que Kea y BIND: solo escucha en la red del laboratorio y en localhost |
| `return 301 https://...`      | Todo lo que llega por HTTP se redirige a HTTPS                              |
| `http2 on`                    | Activa HTTP/2 (sintaxis de Nginx 1.25 en adelante)                          |
| `ssl_protocols`               | Solo TLS 1.2 y 1.3. Las versiones 1.0 y 1.1 están prohibidas (RFC 8996)     |
| `server_tokens off`           | El encabezado `Server` muestra `nginx` sin el número de versión             |
| `Strict-Transport-Security`   | HSTS: el navegador recordará usar solo HTTPS. Aquí dura 1 día; en producción, 1 año |
| `fastcgi_pass unix:...`       | Conexión con PHP-FPM sin pasar por la red                                   |

### 8.3 Adaptar a tu dominio y octeto, activar y validar

```bash
cd /etc/nginx/sites-available
[ "$DOMINIO" != "leonel.mx" ] && sudo mv leonel.mx "${DOMINIO}"
sudo sed -i -e "s/leonel\.mx/${DOMINIO}/g" -e "s/192\.168\.50\./192.168.${OCT}./g" "${DOMINIO}"
sudo ln -sf "/etc/nginx/sites-available/${DOMINIO}" /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

Salida esperada de `nginx -t`:

```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

### 8.4 Firewall (si UFW está activo)

```bash
sudo ufw allow in on enp0s9 to any port 80,443 proto tcp comment 'Web'
```

---

## 9. Los clientes confían en tu CA

El navegador del cliente todavía no conoce tu CA. Si abres `https://www.leonel.mx` ahora, verás **"La conexión no es privada"**. El cliente descargará el certificado público de la CA por HTTP, gracias a la excepción de la sección 8.2, y lo instalará como raíz de confianza.

> ⚠️ **Lección de seguridad:** antes de confiar en una CA, compara su **huella SHA-256** con la que anotaste en el servidor (sección 6.3). Si no coinciden, alguien pudo haber cambiado el archivo en el camino. Por eso la descarga por HTTP solo es aceptable si verificas la huella.

### 9.1 Cliente Linux (Ubuntu)

```bash
DOMINIO=leonel.mx
curl -fsSO "http://www.${DOMINIO}/ca-${DOMINIO}.crt"
openssl x509 -in "ca-${DOMINIO}.crt" -noout -fingerprint -sha256     # Compárala con la del servidor
sudo cp "ca-${DOMINIO}.crt" /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

Salida esperada: `1 added, 0 removed; done.`

> En `/usr/local/share/ca-certificates/` el archivo **debe** terminar en `.crt`; si no, `update-ca-certificates` lo ignora.

### 9.2 Cliente Windows (PowerShell como administrador)

```powershell
$d = "leonel.mx"
Invoke-WebRequest -Uri "http://www.$d/ca-$d.crt" -OutFile "$env:TEMP\ca-$d.crt"
$c = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 "$env:TEMP\ca-$d.crt"
[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($c.RawData)) -replace '-',':'   # Compárala
Import-Certificate -FilePath "$env:TEMP\ca-$d.crt" -CertStoreLocation Cert:\LocalMachine\Root
```

> **Firefox** tiene su propio almacén de certificados. En Windows, normalmente usa también el del sistema. Si aun así muestra advertencia, ve a **Ajustes → Privacidad y seguridad → Certificados → Ver certificados → Autoridades → Importar**.

---

## 10. Pruebas de funcionamiento

### Prueba 1 – Servicios activos y configuración válida (servidor)

```bash
sudo nginx -t
systemctl is-active nginx php8.5-fpm mysql
sudo ss -tlnp | grep -E ':(80|443|3306) '
```

✅ **Éxito:**
- Los tres servicios aparecen como `active`.
- Nginx escucha en `127.0.0.1` y `192.168.50.1`, en los puertos 80 y 443, y **no** en `192.168.1.50`.
- MySQL escucha solo en `127.0.0.1:3306`.

### Prueba 2 – Redirección de HTTP a HTTPS

```bash
curl -sI http://www.leonel.mx | grep -iE '^HTTP|^location'
curl -sI http://leonel.mx/algo?x=1 | grep -i '^location'
```

✅ **Éxito:** responde `HTTP/1.1 301 Moved Permanently` con `Location: https://www.leonel.mx/` (y `/algo?x=1`, conservando la ruta).

### Prueba 3 – HTTPS validado con tu CA

```bash
curl --cacert /etc/ssl/lab/ca-leonel.mx.crt -s https://www.leonel.mx | grep -E 'HTTPS|PHP|MySQL'
curl --cacert /etc/ssl/lab/ca-leonel.mx.crt -sI https://www.leonel.mx
```

✅ **Éxito:**
- La página muestra `HTTPS 🔒`, `PHP 8.5.x` y `MySQL 8.4.x`.
- Los encabezados incluyen `HTTP/2 200`, `server: nginx` (sin versión), `strict-transport-security` y `x-content-type-options`.

### Prueba 4 – Inspección del certificado y TLS

```bash
openssl s_client -connect www.leonel.mx:443 -servername www.leonel.mx \
  -CAfile /etc/ssl/lab/ca-leonel.mx.crt </dev/null 2>/dev/null \
  | grep -E 'subject=|issuer=|Protocol|Verify return code'
```

✅ **Éxito:**
- `subject=...CN=www.leonel.mx`.
- `issuer=...CN=CA Laboratorio leonel.mx`.
- `Protocol: TLSv1.3`.
- `Verify return code: 0 (ok)`.

### Prueba 5 – PHP y MySQL, mínimo privilegio

```bash
# Los datos que muestra la página salen de MySQL
sudo mysql -e "SELECT servicio, estado FROM laboratorio.servicios;"

# webapp NO puede borrar tablas
WEBPASS=$(sudo php -r '$c = require "/var/www/'"${DOMINIO}"'/config.php"; echo $c["pass"];')
MYSQL_PWD="$WEBPASS" mysql -u webapp -e "DROP TABLE laboratorio.servicios;"
```

✅ **Éxito:** el `DROP` falla con `ERROR 1142 (42000): DROP command denied to user 'webapp'@'localhost'`.

> 💡 Cambia un estado y recarga la página, por ejemplo con `sudo mysql -e "UPDATE laboratorio.servicios SET estado='Instalado' WHERE practica=4;"`. Verás que el contenido es dinámico. Al terminar, regrésalo a `Pendiente`.

### Prueba 6 – Archivos protegidos

```bash
C="--cacert /etc/ssl/lab/ca-leonel.mx.crt -s -o /dev/null -w %{http_code}\n"
curl $C https://www.leonel.mx/../config.php      # El cliente normaliza la ruta
curl $C https://www.leonel.mx/config.php         # Fuera de public/
curl $C https://www.leonel.mx/.env               # Archivo oculto
```

✅ **Éxito:** las respuestas son `404`, `404` y `403`. Las credenciales nunca son accesibles desde la web.

### Prueba 7 – Cliente Linux (IP por DHCP, nombre por DNS, CA instalada)

```bash
resolvectl query www.leonel.mx
curl -sI http://www.leonel.mx | grep -i location
curl -s https://www.leonel.mx | grep -oE 'Tu IP \(entregada por Kea\): <code>[0-9.]+'
curl -sI https://www.leonel.mx | head -n 1
```

✅ **Éxito:**
- `curl` funciona **sin `-k` ni `--cacert`**, porque el sistema ya confía en tu CA.
- La página muestra la IP del cliente, que viene del pool o de la reservación de Kea.
- La primera línea es `HTTP/2 200`.

### Prueba 8 – Cliente Windows (navegador)

1. Abre `http://www.leonel.mx` en el navegador. Debe redirigir solo a `https://www.leonel.mx`.
2. Debe aparecer el **candado** 🔒 sin advertencias.
3. Haz clic en el candado → **Certificado**. El emisor es `CA Laboratorio leonel.mx` y entre los nombres alternativos están `www.leonel.mx` y `mail.leonel.mx`.
4. La página muestra tu IP de Kea y la tabla de servicios desde MySQL.

En PowerShell:

```powershell
Invoke-WebRequest https://www.leonel.mx -UseBasicParsing | Select-Object StatusCode
```

✅ **Éxito:** `StatusCode 200` sin errores de certificado.

### Prueba 9 – Logs de acceso

```bash
sudo tail -n 5 /var/log/nginx/leonel.mx.access.log
```

✅ **Éxito:** aparecen las IPs de tus clientes (`192.168.50.x`) con las peticiones `GET / HTTP/2.0` y código `200`.

### Prueba 10 – No expuesto en la red de la escuela

Desde tu equipo anfitrión (red `192.168.1.x`):

```bash
curl -m 3 -sI http://192.168.1.50
```

✅ **Éxito:** `Connection refused` o tiempo agotado. El sitio solo existe en la red del laboratorio.

---

## 11. Creación de evidencias

### 11.1 Script de recolección

```bash
nano ~/evidencias_web.sh
```

```bash
#!/usr/bin/env bash
# Recolector de evidencias - Servidor Web Nginx + PHP 8.5 + MySQL 8.4 (Ubuntu 26.04.1 LTS)
# Uso: sudo ./evidencias_web.sh <dominio> <octeto> "<Nombre del alumno>"

set -uo pipefail

DOMINIO="${1:-leonel.mx}"
OCT="${2:-50}"
ALUMNO="${3:-Sin nombre}"
IFACE="${IFACE:-enp0s9}"
IP="192.168.${OCT}.1"
CA="/etc/ssl/lab/ca-${DOMINIO}.crt"
CRT="/etc/ssl/lab/www.${DOMINIO}.crt"
FECHA="$(date +%Y%m%d_%H%M%S)"
DIR="evidencias_web_${FECHA}"

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
ev 02_versiones.txt        "nginx -v; php -v | head -n 1; mysqld --version; openssl version; dpkg -l | grep -E 'nginx|php8.5|mysql-server'"
ev 03_servicios.txt        "systemctl is-active nginx php8.5-fpm mysql; systemctl status nginx php8.5-fpm mysql --no-pager | grep -E 'Active|Loaded'"
ev 04_puertos.txt          "ss -tlnp | grep -E ':(80|443|3306) '"
ev 05_nginx_validacion.txt "nginx -t"
ev 06_nginx_sitio.txt      "cat /etc/nginx/sites-available/${DOMINIO}; ls -l /etc/nginx/sites-enabled/"
ev 07_certificados.txt     "ls -l /etc/ssl/lab/; openssl verify -CAfile ${CA} ${CRT}; openssl x509 -in ${CRT} -noout -subject -issuer -dates -ext subjectAltName; openssl x509 -in ${CA} -noout -subject -fingerprint -sha256"
ev 08_tls.txt              "openssl s_client -connect ${IP}:443 -servername www.${DOMINIO} -CAfile ${CA} </dev/null 2>/dev/null | grep -E 'subject=|issuer=|Protocol|Cipher is|Verify return code'"
ev 09_redireccion_http.txt "curl -sI --resolve www.${DOMINIO}:80:${IP} http://www.${DOMINIO}/ | grep -iE '^HTTP|^location'"
ev 10_https_encabezados.txt "curl -sI --cacert ${CA} --resolve www.${DOMINIO}:443:${IP} https://www.${DOMINIO}/"
ev 11_https_pagina.txt     "curl -s --cacert ${CA} --resolve www.${DOMINIO}:443:${IP} https://www.${DOMINIO}/ | sed -e 's/<[^>]*>/ /g' | tr -s ' ' | grep -v '^ *$' | head -n 40"
ev 12_mysql.txt            "mysql -e \"SELECT * FROM laboratorio.servicios; SHOW GRANTS FOR 'webapp'@'localhost';\""
ev 13_archivos_protegidos.txt "for u in /config.php /.env /index.php; do printf '%-12s ' \$u; curl -s -o /dev/null -w '%{http_code}\n' --cacert ${CA} --resolve www.${DOMINIO}:443:${IP} https://www.${DOMINIO}\$u; done"
ev 14_permisos.txt         "ls -la /var/www/${DOMINIO} /var/www/${DOMINIO}/public; grep '^expose_php' /etc/php/8.5/fpm/php.ini"
ev 15_access_log.txt       "tail -n 50 /var/log/nginx/${DOMINIO}.access.log"

echo ">>> Capturando el handshake TLS durante 60 s en $IFACE. Abre https://www.${DOMINIO} en el cliente AHORA..."
timeout 60 tcpdump -i "$IFACE" -n 'tcp port 80 or tcp port 443' -w "$DIR/16_web.pcap" 2>/dev/null
ev 16_web_resumen.txt      "tcpdump -n -r $DIR/16_web.pcap 2>/dev/null | head -n 40"

# Integridad y empaquetado
( cd "$DIR" && sha256sum * > SHA256SUMS.txt )
tar -czf "${DIR}.tar.gz" "$DIR"
sha256sum "${DIR}.tar.gz" | tee "${DIR}.tar.gz.sha256"

echo
echo "✅ Evidencias generadas en: $DIR/"
echo "✅ Paquete: ${DIR}.tar.gz"
```

```bash
chmod +x ~/evidencias_web.sh
sudo ~/evidencias_web.sh "$DOMINIO" "$OCT" "Nombre Apellido"
```

Durante los 60 segundos de captura, abre `https://www.leonel.mx` en el cliente. En Wireshark, con el filtro `tls.handshake`, verás el `Client Hello` con el nombre `www.leonel.mx` en la extensión **SNI**. Todo lo demás viaja cifrado: compáralo con la captura de DNS, donde todo se leía en claro.

### 11.2 Evidencias del cliente

**Linux:**

```bash
{
  echo "Alumno: Nombre Apellido | Fecha: $(date)"
  ip -br addr
  resolvectl query www.leonel.mx
  ls -l /etc/ssl/certs | grep -i leonel
  curl -sI http://www.leonel.mx | grep -iE '^HTTP|^location'
  curl -sI https://www.leonel.mx
  curl -s https://www.leonel.mx | sed -e 's/<[^>]*>/ /g' | tr -s ' ' | grep -v '^ *$' | head -n 25
} 2>&1 | tee evidencia_web_cliente_$(hostname)_$(date +%Y%m%d_%H%M).txt
```

**Windows (PowerShell):**

```powershell
$f = "evidencia_web_cliente_$env:COMPUTERNAME_$(Get-Date -f yyyyMMdd_HHmm).txt"
"Alumno: Nombre Apellido | Fecha: $(Get-Date)" | Out-File $f
ipconfig /all | Out-File $f -Append
Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -like "*Laboratorio*" | Format-List Subject, Thumbprint, NotAfter | Out-File $f -Append
Invoke-WebRequest https://www.leonel.mx -UseBasicParsing | Select-Object StatusCode, Headers | Format-List | Out-File $f -Append
```

### 11.3 Capturas de pantalla recomendadas

1. El navegador del cliente mostrando la página con el **candado** 🔒 y la barra de direcciones.
2. El visor de certificados del navegador: emisor `CA Laboratorio leonel.mx` y los SAN.
3. `nginx -t` y `systemctl is-active nginx php8.5-fpm mysql`.
4. El `ERROR 1142` de la prueba 5 (mínimo privilegio).
5. Wireshark con el `Client Hello` y su SNI.

---

## 12. Solución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| `nginx -t`: `cannot load certificate` | Ruta o nombre del certificado incorrecto | `ls -l /etc/ssl/lab/` y revisa `ssl_certificate` |
| `nginx -t`: `bind() to 192.168.50.1:80 failed (99: Cannot assign requested address)` | La IP no existe todavía o el octeto está mal | Revisa `ip -br addr show enp0s9` y el `sed` de la sección 8.3 |
| Nginx no arranca tras reiniciar el servidor | Arrancó antes de que `enp0s9` tuviera IP | Verifica `optional: true` en `enp0s3` (sección 4.3); como respaldo, `echo 'net.ipv4.ip_nonlocal_bind=1' \| sudo tee /etc/sysctl.d/60-nonlocal-bind.conf` y reinicia |
| `502 Bad Gateway` | PHP-FPM detenido o socket incorrecto | `systemctl status php8.5-fpm` y `ls -l /run/php/`. Debe ser `php8.5-fpm.sock` |
| Descarga el `.php` en vez de ejecutarlo | Falta el bloque `location ~ \.php$` | Revisa la configuración y `sudo nginx -t` |
| `File not found.` en la página | `root` incorrecto o permisos | `root /var/www/<dominio>/public` y permisos de la sección 7.4 |
| La página dice "No fue posible conectar con la base de datos" | Contraseña de `config.php` distinta a la de MySQL | `sudo tail /var/log/php8.5-fpm.log` y `/var/log/nginx/<dominio>.error.log`. Cambia la clave con `ALTER USER` |
| Log: `SQLSTATE[HY000] [2002] Permission denied` | PHP (`www-data`) no puede entrar a la carpeta del socket de MySQL | `ls -ld /run/mysqld` debe mostrar `drwxr-xr-x`. Reinicia MySQL con `sudo systemctl restart mysql`, que recrea la carpeta con permisos 755 |
| El navegador muestra "La conexión no es privada" | El cliente no confía en tu CA | Instala la CA (sección 9) y reinicia el navegador |
| `NET::ERR_CERT_COMMON_NAME_INVALID` | El nombre no está en el SAN | Revisa `openssl x509 -ext subjectAltName`; vuelve a emitir con la sección 6.2 |
| `curl: (60) SSL certificate problem` en el cliente | CA no instalada o archivo sin extensión `.crt` | `ls /usr/local/share/ca-certificates/` y `sudo update-ca-certificates` |
| Error HSTS tras cambiar el certificado | El navegador recuerda HSTS | Corrige el certificado. HSTS dura 1 día en este laboratorio |
| `apt update` falla en la sección 4 | Tu BIND no puede salir o la NAT no está conectada | `ip route` debe mostrar la ruta por `enp0s3`; `sudo resolvectl dns enp0s3 10.0.2.3` |

---

## 13. Rúbrica sugerida

| Criterio                                                               | Puntos |
|------------------------------------------------------------------------|:------:|
| Stack instalado (Nginx, PHP 8.5-FPM, MySQL 8.4); servidor sin internet  | 10     |
| MySQL: base, tabla y usuario con mínimo privilegio (`ERROR 1142`)       | 10     |
| CA propia creada correctamente (CA:TRUE, llave protegida)               | 10     |
| Certificado de servidor con SAN correcto y verificado (`OK`)            | 15     |
| Nginx: redirección 301, HTTPS, HTTP/2, TLS 1.2/1.3 y encabezados de seguridad | 15 |
| PHP + MySQL funcionando; credenciales fuera de la raíz web              | 10     |
| **Continuidad:** el cliente usa DHCP + DNS y abre `https://www.<dominio>` con candado | 15 |
| Paquete de evidencias con hashes verificables                           | 10     |
| Reporte: diferencia entre CA y autofirmado, y qué protege TLS           | 5      |
| **Total**                                                              | **100** |

---

### Referencias

- Nginx – *Configuring HTTPS servers*: <https://nginx.org/en/docs/http/configuring_https_servers.html>
- Ubuntu Server docs – *Nginx*, *PHP*, *MySQL*: <https://documentation.ubuntu.com/server/>
- OpenSSL 3.5 – `openssl-req(1)`, `openssl-x509(1)`: <https://docs.openssl.org/3.5/man1/>
- Mozilla SSL Configuration Generator: <https://ssl-config.mozilla.org/>
- RFC 8996 (TLS 1.0 y 1.1 obsoletos), RFC 6797 (HSTS)