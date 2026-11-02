# El gestor de paquetes en Ubuntu Server

> Guía práctica de uso para **Ubuntu Server 22.04 LTS y 24.04 LTS**: APT, dpkg y Snap.

---

## Índice

1. [Cómo funciona la gestión de paquetes](#1-cómo-funciona-la-gestión-de-paquetes)
2. [Actualizar el sistema](#2-actualizar-el-sistema)
3. [Buscar e inspeccionar paquetes](#3-buscar-e-inspeccionar-paquetes)
4. [Instalar paquetes](#4-instalar-paquetes)
5. [Desinstalar paquetes](#5-desinstalar-paquetes)
6. [Consultar lo que está instalado](#6-consultar-lo-que-está-instalado)
7. [Trabajar con archivos .deb y dpkg](#7-trabajar-con-archivos-deb-y-dpkg)
8. [Dependencias](#8-dependencias)
9. [Historial y registros](#9-historial-y-registros)
10. [Respaldar y replicar la lista de paquetes](#10-respaldar-y-replicar-la-lista-de-paquetes)
11. [Congelar y fijar versiones](#11-congelar-y-fijar-versiones)
12. [Uso en scripts (modo no interactivo)](#12-uso-en-scripts-modo-no-interactivo)
13. [Repositorios](#13-repositorios)
14. [Snap](#14-snap)
15. [Actualizar a una nueva versión de Ubuntu](#15-actualizar-a-una-nueva-versión-de-ubuntu)
16. [Mantenimiento y limpieza](#16-mantenimiento-y-limpieza)
17. [Solución de problemas](#17-solución-de-problemas)
18. [Chuleta de comandos](#18-chuleta-de-comandos)

---

## 1. Cómo funciona la gestión de paquetes

Ubuntu instala software mediante **paquetes `.deb`**: archivos que contienen el programa, sus archivos de configuración, scripts de instalación y la lista de **dependencias** que necesita.

| Herramienta | Nivel | Qué hace |
|-------------|-------|----------|
| `dpkg` | Bajo | Instala, desinstala y consulta paquetes `.deb` **locales**. No descarga ni resuelve dependencias |
| `apt` | Alto | Descarga de repositorios, resuelve dependencias y llama a `dpkg`. Pensado para uso interactivo |
| `apt-get` / `apt-cache` | Alto | Equivalentes clásicos de `apt`, con salida estable. Recomendados en **scripts** |
| `snap` | Independiente | Paquetes autocontenidos con sus propias dependencias y actualizaciones automáticas |

Flujo típico:

```
Repositorios ──(apt update)──► lista local de paquetes
                                    │
                    (apt install) ──┴──► descarga .deb ──► dpkg instala
```

Archivos importantes:

| Ruta | Contenido |
|------|-----------|
| `/etc/apt/sources.list.d/` | Repositorios configurados |
| `/etc/apt/apt.conf.d/` | Configuración de APT |
| `/var/lib/apt/lists/` | Listas de paquetes descargadas con `apt update` |
| `/var/cache/apt/archives/` | Archivos `.deb` descargados |
| `/var/lib/dpkg/` | Base de datos de paquetes instalados |
| `/var/log/apt/` y `/var/log/dpkg.log` | Historial |

---

## 2. Actualizar el sistema

```bash
sudo apt update          # 1. descarga la lista actualizada de paquetes
apt list --upgradable    # 2. revisa qué se va a actualizar
sudo apt upgrade         # 3. actualiza
```

| Comando | Diferencia |
|---------|-----------|
| `apt update` | **No instala nada**; solo actualiza la lista de paquetes disponibles |
| `apt upgrade` | Actualiza, pero nunca elimina paquetes; puede dejar alguno "retenido" |
| `apt full-upgrade` | Actualiza aunque tenga que instalar o quitar dependencias (por ejemplo, un kernel nuevo) |

Todo en una línea:

```bash
sudo apt update && sudo apt full-upgrade -y
```

Actualizar **solo un paquete**:

```bash
sudo apt install --only-upgrade nginx
```

### Reinicio de servicios y del servidor

Después de actualizar, `needrestart` puede mostrar qué servicios usan bibliotecas antiguas y ofrecer reiniciarlos. Para saber si hace falta **reiniciar el servidor** (por ejemplo, tras actualizar el kernel):

```bash
[ -f /var/run/reboot-required ] && cat /var/run/reboot-required.pkgs
```

---

## 3. Buscar e inspeccionar paquetes

```bash
apt search servidor web          # busca en nombre y descripción
apt search --names-only '^php8'  # busca solo en el nombre (acepta expresiones regulares)
apt show nginx                   # descripción, versión, tamaño, dependencias
apt policy nginx                 # versión instalada, candidata y repositorio de origen
apt list -a nginx                # todas las versiones disponibles
```

Ejemplo de `apt policy`:

```
nginx:
  Installed: (none)
  Candidate: 1.24.0-2ubuntu7
  Version table:
     1.24.0-2ubuntu7 500
        500 http://mx.archive.ubuntu.com/ubuntu noble/main amd64 Packages
```

### ¿Qué paquete contiene un archivo?

Para archivos **ya instalados**:

```bash
dpkg -S /usr/bin/curl
# curl: /usr/bin/curl
```

Para archivos de paquetes **no instalados**, usa `apt-file`:

```bash
sudo apt install -y apt-file
sudo apt-file update
apt-file search bin/ifconfig
# net-tools: /usr/sbin/ifconfig
```

Muy útil cuando un comando no existe y no sabes qué instalar.

---

## 4. Instalar paquetes

```bash
sudo apt install nginx                  # uno
sudo apt install nginx curl git htop    # varios
sudo apt install -y nginx               # sin pedir confirmación
sudo apt install nginx=1.24.0-2ubuntu7  # versión concreta
sudo apt install --no-install-recommends nginx   # solo dependencias obligatorias
sudo apt install --reinstall nginx      # reinstalar (repara archivos borrados o dañados)
```

> 💡 `--no-install-recommends` instala menos paquetes; es útil en servidores mínimos y contenedores.

Simular antes de instalar (no cambia nada):

```bash
apt install -s nginx
```

Solo descargar, sin instalar:

```bash
sudo apt install --download-only nginx   # queda en /var/cache/apt/archives/
apt download nginx                       # descarga el .deb al directorio actual
```

---

## 5. Desinstalar paquetes

```bash
sudo apt remove nginx       # quita el programa, conserva la configuración en /etc
sudo apt purge nginx        # quita el programa y su configuración
sudo apt autoremove         # quita dependencias que ya ningún paquete necesita
sudo apt autoremove --purge # lo mismo, borrando también su configuración
```

Desinstalar y limpiar en un solo paso:

```bash
sudo apt purge --autoremove nginx
```

> ⚠️ Lee siempre la lista de paquetes que se van a eliminar antes de confirmar. Un `remove` puede arrastrar otros paquetes que dependen del que quitas.

Ver paquetes eliminados que aún conservan configuración (estado `rc`) y purgarlos:

```bash
dpkg -l | awk '/^rc/ {print $2}'
dpkg -l | awk '/^rc/ {print $2}' | xargs -r sudo apt purge -y
```

---

## 6. Consultar lo que está instalado

```bash
apt list --installed                 # todos los paquetes instalados
apt list --installed | grep nginx    # filtrar
apt-mark showmanual                  # instalados explícitamente por ti
apt-mark showauto                    # instalados como dependencia
dpkg -l nginx                        # estado de un paquete
dpkg -L nginx                        # archivos que instaló un paquete
dpkg-query -W -f='${Version}\n' nginx   # solo la versión
```

Estados en `dpkg -l` (primeras dos letras):

| Código | Significado |
|--------|-------------|
| `ii` | Instalado correctamente |
| `rc` | Eliminado, pero conserva configuración |
| `iU` | Desempaquetado, no configurado |
| `iF` | Falló la configuración |

Paquetes que más espacio ocupan:

```bash
dpkg-query -W -f='${Installed-Size}\t${Package}\n' | sort -rn | head -n 15
```

(Tamaño en KiB.)

---

## 7. Trabajar con archivos .deb y dpkg

Algunos programas se distribuyen como archivo `.deb` descargable. **Usa `apt` para instalarlos**, porque resuelve las dependencias:

```bash
sudo apt install ./programa_1.0_amd64.deb
```

> El `./` es necesario: indica a `apt` que es un archivo local y no un nombre de paquete.

Con `dpkg` directamente (no resuelve dependencias):

```bash
sudo dpkg -i programa_1.0_amd64.deb
sudo apt --fix-broken install     # completa las dependencias que falten
```

Inspeccionar un `.deb` sin instalarlo:

```bash
dpkg -I programa_1.0_amd64.deb    # información y dependencias
dpkg -c programa_1.0_amd64.deb    # archivos que contiene
```

Volver a ejecutar la configuración de un paquete (por ejemplo, para cambiar respuestas que diste durante la instalación):

```bash
sudo dpkg-reconfigure tzdata
```

---

## 8. Dependencias

```bash
apt-cache depends nginx      # de qué depende nginx
apt-cache rdepends nginx     # qué paquetes dependen de nginx
apt-cache rdepends --installed nginx   # solo entre los instalados
```

Tipos de relación que verás en `apt show`:

| Campo | Significado |
|-------|-------------|
| `Depends` | Obligatoria |
| `Recommends` | Se instala por defecto, pero no es obligatoria |
| `Suggests` | Opcional; no se instala sola |
| `Conflicts` / `Breaks` | No puede coexistir con ese paquete |

Marcar un paquete como instalado manualmente para que `autoremove` no lo quite:

```bash
sudo apt-mark manual libfoo1
```

---

## 9. Historial y registros

Qué se instaló, actualizó o eliminó, cuándo y con qué comando:

```bash
less /var/log/apt/history.log
```

```
Start-Date: 2026-09-27  17:40:12
Commandline: apt install nginx
Requested-By: leonel (1000)
Install: nginx:amd64 (1.24.0-2ubuntu7), nginx-common:amd64 (1.24.0-2ubuntu7, automatic)
End-Date: 2026-09-27  17:40:20
```

Buscar en el historial, incluidos los archivos rotados:

```bash
zgrep -h 'Commandline' /var/log/apt/history.log* | tail -n 20
zgrep -h ' install ' /var/log/dpkg.log* | grep nginx
```

Salida completa de las operaciones (útil para errores):

```bash
less /var/log/apt/term.log
```

---

## 10. Respaldar y replicar la lista de paquetes

Útil para reinstalar un servidor o configurar otro igual.

### Opción A: solo paquetes instalados manualmente (recomendada)

En el servidor original:

```bash
apt-mark showmanual > paquetes.txt
```

En el servidor nuevo (misma versión de Ubuntu):

```bash
sudo apt update
xargs -a paquetes.txt sudo apt install -y
```

### Opción B: selección completa de dpkg

```bash
# Origen
dpkg --get-selections > selecciones.txt

# Destino
sudo apt update
sudo dpkg --set-selections < selecciones.txt
sudo apt-get dselect-upgrade -y
```

> Respalda también `/etc/apt/sources.list.d/` y `/etc/apt/keyrings/` si usas repositorios de terceros; sin ellos el servidor nuevo no encontrará esos paquetes.

---

## 11. Congelar y fijar versiones

### Congelar (hold)

Impide que un paquete se actualice:

```bash
sudo apt-mark hold postgresql-16
apt-mark showhold
sudo apt-mark unhold postgresql-16
```

### Volver a una versión anterior

```bash
apt list -a nginx
sudo apt install nginx=1.24.0-2ubuntu7 --allow-downgrades
sudo apt-mark hold nginx
```

### Prioridad por repositorio (pinning)

Por ejemplo, para que un paquete salga siempre de un repositorio concreto:

```bash
sudo nano /etc/apt/preferences.d/nginx
```

```
Package: nginx*
Pin: origin nginx.org
Pin-Priority: 900
```

Comprueba el efecto con `apt policy nginx`. Prioridad mayor = preferido; `-1` = nunca instalar.

---

## 12. Uso en scripts (modo no interactivo)

En scripts, Ansible, cloud-init o Dockerfiles, evita cualquier pregunta interactiva:

```bash
#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive   # sin diálogos de configuración
export NEEDRESTART_MODE=a               # reinicia servicios sin preguntar

apt-get update
apt-get install -y --no-install-recommends \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  nginx curl git
```

| Opción | Efecto |
|--------|--------|
| `DEBIAN_FRONTEND=noninteractive` | Usa respuestas por defecto en vez de preguntar |
| `--force-confdef` + `--force-confold` | Si un archivo de configuración cambió, conserva el tuyo sin preguntar |
| `apt-get` en lugar de `apt` | Salida estable; `apt` advierte que su interfaz puede cambiar |

Preconfigurar respuestas antes de instalar (ejemplo con `tzdata`):

```bash
echo 'tzdata tzdata/Areas select America' | sudo debconf-set-selections
echo 'tzdata tzdata/Zones/America select Mexico_City' | sudo debconf-set-selections
```

---

## 13. Repositorios

| Versión | Archivo principal |
|---------|-------------------|
| **24.04** | `/etc/apt/sources.list.d/ubuntu.sources` (formato deb822) |
| **22.04** | `/etc/apt/sources.list` (una línea por repositorio) |

Componentes de Ubuntu:

| Componente | Contenido |
|------------|-----------|
| `main` | Software libre con soporte de Canonical |
| `restricted` | Controladores propietarios con soporte |
| `universe` | Software libre mantenido por la comunidad |
| `multiverse` | Software con restricciones de licencia |

```bash
sudo apt edit-sources            # abre la configuración de repositorios
sudo add-apt-repository universe # activa un componente
sudo add-apt-repository ppa:usuario/nombre   # agrega un PPA
sudo add-apt-repository --remove ppa:usuario/nombre
```

Ver el estado de soporte de seguridad de los paquetes instalados:

```bash
pro security-status
```

> Para configurar espejos, proxy, claves de repositorios de terceros y caché en la red local, consulta el tutorial **"Configurar el gestor de paquetes (APT) en Ubuntu Server"**.

---

## 14. Snap

Ubuntu Server incluye **snapd**. Los snaps traen sus propias dependencias, se actualizan solos y funcionan aislados del sistema. Algunos programas solo se distribuyen así (por ejemplo, `lxd` en versiones recientes).

```bash
snap find nextcloud               # buscar
snap info nextcloud               # detalles y canales disponibles
sudo snap install nextcloud       # instalar
sudo snap install --classic certbot   # snaps con acceso completo al sistema
snap list                         # instalados
sudo snap refresh                 # actualizar todos
sudo snap refresh nextcloud       # actualizar uno
sudo snap revert nextcloud        # volver a la versión anterior
sudo snap remove nextcloud        # desinstalar
```

Canales (versiones) disponibles:

```bash
sudo snap install lxd --channel=5.21/stable
sudo snap refresh lxd --channel=latest/stable
```

Controlar las actualizaciones automáticas:

```bash
snap refresh --time                           # cuándo se actualiza
sudo snap set system refresh.timer=sat,03:00  # sábados a las 3:00
sudo snap refresh --hold nextcloud            # pausar actualizaciones de un snap
sudo snap refresh --unhold nextcloud
```

### APT o Snap

| | APT (.deb) | Snap |
|--|------------|------|
| Dependencias | Compartidas con el sistema | Incluidas en el snap |
| Actualizaciones | Manuales o con unattended-upgrades | Automáticas |
| Tamaño | Menor | Mayor |
| Aislamiento | No | Sí (confinamiento) |
| Versiones | Las del repositorio de Ubuntu | Canales, a menudo más recientes |

---

## 15. Actualizar a una nueva versión de Ubuntu

Por ejemplo, de 22.04 a 24.04:

```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
sudo do-release-upgrade
```

> ⚠️ Haz respaldo antes. Si trabajas por SSH, `do-release-upgrade` abre un SSH adicional en el puerto **1022** como respaldo; permítelo en el firewall si hace falta.

Configurar a qué versiones se ofrece actualizar:

```bash
grep Prompt /etc/update-manager/release-upgrades
# Prompt=lts    → solo de LTS a LTS (recomendado en servidores)
```

---

## 16. Mantenimiento y limpieza

```bash
sudo apt autoremove --purge   # dependencias huérfanas
sudo apt clean                # borra todos los .deb del caché
sudo apt autoclean            # borra solo los .deb obsoletos
du -sh /var/cache/apt/archives
```

Kernels antiguos: `autoremove` los elimina automáticamente, conservando el actual y el anterior.

Snaps: por defecto se guardan 3 versiones de cada uno. Para reducirlo a 2:

```bash
sudo snap set system refresh.retain=2
```

Rutina recomendada:

```bash
sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove --purge -y && sudo apt autoclean
```

---

## 17. Solución de problemas

| Error / síntoma | Solución |
|-----------------|----------|
| `Could not get lock /var/lib/dpkg/lock-frontend` | Otro proceso de APT está en curso (a menudo unattended-upgrades). Espera: `ps aux \| grep -E 'apt\|dpkg'`. **No borres los archivos lock** |
| `dpkg was interrupted, you must manually run 'sudo dpkg --configure -a'` | `sudo dpkg --configure -a` |
| `Unmet dependencies` / dependencias rotas | `sudo apt --fix-broken install` |
| `Unable to locate package` | `sudo apt update`; revisa el nombre con `apt search`; puede estar en `universe` |
| `The following packages have been kept back` | Normalmente requieren `sudo apt full-upgrade`, o están en una actualización por fases que llegará más tarde |
| `command not found` | Busca el paquete: `apt-file search bin/COMANDO` |
| `NO_PUBKEY` | Falta la clave de un repositorio de terceros |
| `Hash Sum mismatch` | `sudo rm -rf /var/lib/apt/lists/*` y `sudo apt update` |
| Un paquete quedó en estado `iF` o `iU` | `sudo dpkg --configure -a`; si falla, `sudo apt install --reinstall PAQUETE` |
| Sin espacio en disco | `sudo apt clean`, `sudo apt autoremove --purge`, `sudo journalctl --vacuum-size=200M` |

Último recurso para un paquete cuyo script de desinstalación falla:

```bash
sudo dpkg --remove --force-remove-reinstreq PAQUETE
```

---

## 18. Chuleta de comandos

| Tarea | Comando |
|-------|---------|
| Actualizar lista | `sudo apt update` |
| Actualizar todo | `sudo apt full-upgrade` |
| Buscar | `apt search TEXTO` |
| Información | `apt show PAQUETE` |
| Versión y origen | `apt policy PAQUETE` |
| Instalar | `sudo apt install PAQUETE` |
| Instalar .deb | `sudo apt install ./archivo.deb` |
| Reinstalar | `sudo apt install --reinstall PAQUETE` |
| Desinstalar | `sudo apt remove PAQUETE` |
| Desinstalar + config | `sudo apt purge PAQUETE` |
| Limpiar dependencias | `sudo apt autoremove --purge` |
| Instalados | `apt list --installed` |
| Instalados por mí | `apt-mark showmanual` |
| Archivos de un paquete | `dpkg -L PAQUETE` |
| Paquete de un archivo | `dpkg -S /ruta/archivo` |
| Congelar | `sudo apt-mark hold PAQUETE` |
| Reparar | `sudo dpkg --configure -a && sudo apt --fix-broken install` |
| Historial | `less /var/log/apt/history.log` |
| Snap: instalar | `sudo snap install PAQUETE` |
| Snap: listar | `snap list` |