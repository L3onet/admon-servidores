# Práctica: Instalación y configuración de impresoras USB y TCP/IP, y compartición con Samba, en Ubuntu Server 26.04.1 LTS

> **Sistema:** Ubuntu Server 26.04.1 LTS (Resolute Raccoon), sin entorno gráfico.
> **Sistema de impresión:** CUPS (*Common UNIX Printing System*).
> **Material:** una impresora USB, una impresora de red (TCP/IP), cable USB A-B y acceso a la LAN del laboratorio.
>
> Los recuadros **📸 Evidencia** indican qué capturar para el reporte. Las salidas de los comandos se guardan en `~/evidencias/`.

---

## Índice

- [Datos de la práctica](#datos-de-la-práctica)
- [Tipos de conexión de impresoras](#tipos-de-conexión-de-impresoras)
- [Administración de impresión en Linux](#administración-de-impresión-en-linux)
- [Preparación del servidor de impresión](#preparación-del-servidor-de-impresión)
- [Instalación y configuración de impresora USB](#instalación-y-configuración-de-impresora-usb)
- [Instalación y configuración de impresora TCP/IP](#instalación-y-configuración-de-impresora-tcpip)
- [Impresora compartida para varios usuarios](#impresora-compartida-para-varios-usuarios)
- [Impresora USB compartida con Samba](#impresora-usb-compartida-con-samba)
- [Ventajas de TCP/IP frente a USB](#ventajas-de-tcpip-frente-a-usb)
- [Anexo A. Lista de evidencias](#anexo-a-lista-de-evidencias)
- [Anexo B. Solución de problemas](#anexo-b-solución-de-problemas)
- [Anexo C. Práctica sin impresora física (impresora PDF)](#anexo-c-práctica-sin-impresora-física-impresora-pdf)

---

## Datos de la práctica

| Elemento | Valor de ejemplo |
|----------|------------------|
| Servidor de impresión | `servidor-lab`, IP `192.168.1.50` |
| Red del laboratorio | `192.168.1.0/24` |
| Impresora USB | Conectada al servidor; cola `USB_Lab` |
| Impresora TCP/IP | IP `192.168.1.80`; cola `Red_Lab` |
| Recurso Samba de la impresora USB | `\\192.168.1.50\USB_Lab` |
| Usuarios de Samba | `profe1` (grupo `docentes`, autorizado) y `alumno1` (grupo `alumnos`, sin acceso) |
| Administrador | `alumno` |

> ⚠️ **Las IP de este documento son de ejemplo.** Sustitúyelas por las de tu laboratorio en cada bloque. La IP y la red reales del servidor se obtienen así:

```bash
ip -br -4 addr show scope global      # IP del servidor y máscara
ip route | grep default               # puerta de enlace; indica cuál es tu red
```

```bash
mkdir -p ~/evidencias
```

---

# Tipos de conexión de impresoras

## Impresora USB

| Aspecto | Descripción |
|---------|-------------|
| **Características** | Conexión directa punto a punto entre la impresora y **un** equipo. Es *plug and play*: el sistema la detecta al conectarla. Las impresoras modernas suelen soportar **IPP-over-USB** (IPP Everywhere por USB), lo que permite usarlas sin controlador |
| **Forma de conexión** | Cable del puerto USB-A del equipo al puerto USB-B (o USB-C) de la impresora. En Linux aparece como `/dev/usb/lp0` (clase de impresora) o es gestionada por `ipp-usb` |
| **Medio utilizado** | Cable de cobre USB 2.0 (480 Mbit/s); longitud máxima recomendada: **5 m** |
| **Ventajas** | Instalación sencilla y barata, sin configurar red. Alta fiabilidad y nula exposición a ataques por red. Baja latencia |
| **Limitaciones** | Solo el equipo conectado puede imprimir directamente. Para compartirla, ese equipo debe estar **siempre encendido** y actuar como servidor. Distancia limitada por el cable. Un fallo del equipo deja la impresora inaccesible |
| **Uso actual** | Muy extendido en hogares, puestos individuales, impresoras de etiquetas y tickets, y para la configuración inicial de impresoras de red |
| **Escenario recomendado** | Un solo usuario o una oficina pequeña, con la impresora junto al equipo. También cuando no hay infraestructura de red o se necesita aislamiento |

## Impresora TCP/IP (de red)

| Aspecto | Descripción |
|---------|-------------|
| **Características** | La impresora tiene su propia **tarjeta de red** y **dirección IP**, y funciona como un nodo más de la red. Incluye un servidor de impresión integrado y, normalmente, una página web de administración |
| **Forma de conexión** | Se conecta a un switch o punto de acceso. Los equipos (o un servidor de impresión) le envían los trabajos con un protocolo de red: **IPP** (631/tcp), **AppSocket/JetDirect** (9100/tcp) o **LPD** (515/tcp) |
| **Medio utilizado** | Cable Ethernet UTP (Cat 5e/6, hasta 100 m por tramo) o inalámbrico Wi-Fi (802.11) |
| **Ventajas** | Acceso para **muchos usuarios** a la vez, sin depender de un equipo concreto. Ubicación libre dentro de la red. Administración y monitoreo remotos (niveles de tóner, errores). Se integra con servidores de impresión para cuotas y control de acceso |
| **Limitaciones** | Requiere infraestructura de red y planificación de IPs. Mayor coste. Expuesta a riesgos de seguridad si no se protege. Depende del estado de la red |
| **Uso actual** | Estándar en empresas, escuelas, laboratorios e impresoras multifunción. La mayoría de modelos actuales soporta impresión **sin controlador** (IPP Everywhere, AirPrint, Mopria) |
| **Escenario recomendado** | Varios usuarios o departamentos compartiendo el dispositivo, oficinas, aulas y centros de cómputo |

## Conexión paralela (solo documental)

| Aspecto | Descripción |
|---------|-------------|
| **Características** | Interfaz **Centronics / IEEE 1284**. Transmite 8 bits simultáneamente, uno por cada línea de datos |
| **Forma de conexión** | Puerto **DB-25** en el equipo y conector **Centronics 36** en la impresora. En Linux: `/dev/lp0`, URI `parallel:/dev/lp0` |
| **Medio utilizado** | Cable multifilar blindado, de hasta unos 3 m (hasta 10 m con IEEE 1284) |
| **Ventajas** | Sencillez; compatible con impresoras antiguas de matriz de puntos |
| **Limitaciones** | Lenta (≈150 KB/s estándar, ≈2 MB/s en modo ECP), cables voluminosos, sin *plug and play* real. Ausente en los equipos actuales |
| **Uso actual** | **Obsoleto.** Solo sobrevive en equipos industriales o de punto de venta antiguos |
| **Escenario recomendado** | Mantenimiento de equipos heredados; con adaptadores USB-paralelo si no hay puerto |

## Conexión serial (solo documental)

| Aspecto | Descripción |
|---------|-------------|
| **Características** | Interfaz **RS-232**. Transmite los bits uno tras otro por una sola línea de datos |
| **Forma de conexión** | Puerto **DB-9** o **DB-25**. Hay que ajustar velocidad (baudios), bits de datos, paridad y control de flujo. En Linux: `/dev/ttyS0`, URI `serial:/dev/ttyS0?baud=9600` |
| **Medio utilizado** | Cable serial, de hasta unos 15 m a velocidades bajas |
| **Ventajas** | Alcance mayor que el paralelo, cable sencillo, gran robustez en entornos industriales |
| **Limitaciones** | Muy lenta (típicamente 9.600 a 115.200 bit/s), configuración manual de parámetros |
| **Uso actual** | Impresoras de tickets, etiquetas y equipos industriales antiguos; hoy casi siempre sustituida por USB o red |
| **Escenario recomendado** | Terminales de punto de venta, básculas y equipos industriales heredados |

## Comparación general

| Tipo | Velocidad típica | Distancia | Usuarios | Vigencia | En esta práctica |
|------|------------------|-----------|----------|----------|------------------|
| Serial | ≤ 115 kbit/s | ~15 m | 1 | Obsoleta | Documental |
| Paralela | ≤ 2 MB/s | ~3–10 m | 1 | Obsoleta | Documental |
| **USB** | 480 Mbit/s | 5 m | 1 (o compartida por un servidor) | Vigente | **Práctica** |
| **TCP/IP** | 100 Mbit/s – 1 Gbit/s | Ilimitada dentro de la red | Muchos | Vigente, estándar empresarial | **Práctica** |

---

# Administración de impresión en Linux

## Conceptos

| Concepto | Definición | En CUPS |
|----------|------------|---------|
| **Servidor de impresión** | Sistema que recibe, almacena, procesa y envía los trabajos a las impresoras, y controla quién imprime y dónde | El servicio `cupsd` |
| **Cola de impresión** | Lista ordenada de trabajos pendientes para una impresora. Cada cola tiene nombre, dispositivo, controlador y opciones | `lpstat -o`; se crean con `lpadmin -p` |
| **Trabajo de impresión** | Cada documento enviado a imprimir. Tiene un ID (`Cola-N`), propietario, tamaño, estado y opciones | `Red_Lab-12` |
| **Impresora local** | Conectada físicamente al servidor (USB, paralelo, serial) | URI `usb://...`, `parallel:/dev/lp0` |
| **Impresora de red** | Con IP propia, a la que se accede por la red | URI `ipp://`, `socket://`, `lpd://` |
| **Impresora compartida** | Cola de un servidor que se ofrece a otros equipos de la red, sea local o de red | `printer-is-shared=true`; los clientes usan `ipp://servidor:631/printers/cola`. Con Samba, también `\\servidor\cola` |

## Flujo de un trabajo en CUPS

```
 Usuario            Servidor CUPS (cupsd)                                  Impresora
┌───────┐ lp/IPP ┌──────────────────────────────────────────────────┐
│ Doc.  │───────►│ Cola ─► Planificador ─► Filtros ─► Backend ──────┼──► USB / IPP / 9100 / LPD
└───────┘        │ (spool)                 (PDF→formato   (usb, ipp,│
                 │ /var/spool/cups          de la impresora) socket)│
                 └──────────────────────────────────────────────────┘
```

1. El usuario envía el documento (`lp`, una aplicación o un cliente de red por IPP).
2. `cupsd` lo guarda en la **cola** (`/var/spool/cups`).
3. Los **filtros** lo convierten al lenguaje de la impresora (PDF, PCL, PWG Raster, PostScript).
4. El **backend** lo transmite por el medio adecuado.

## Administración de trabajos de impresión

| Tarea | Comando |
|-------|---------|
| Enviar un trabajo | `lp -d COLA archivo` |
| Enviar varias copias | `lp -d COLA -n 3 archivo` |
| Ver trabajos pendientes | `lpstat -o` / `lpq -P COLA` |
| Ver trabajos terminados | `lpstat -W completed -o` |
| Cancelar un trabajo | `cancel COLA-12` / `lprm -P COLA 12` |
| Cancelar todos los trabajos de una cola | `cancel -a COLA` |
| Retener un trabajo | `lp -i COLA-12 -H hold` |
| Liberar un trabajo retenido | `lp -i COLA-12 -H resume` |
| Mover un trabajo a otra cola | `lpmove COLA-12 OTRA_COLA` |
| Pausar / reanudar la impresora | `cupsdisable COLA` / `cupsenable COLA` |
| Rechazar / aceptar trabajos nuevos | `cupsreject COLA` / `cupsaccept COLA` |

> Diferencia clave: **`cupsdisable`** detiene la impresión pero la cola sigue **aceptando** trabajos; **`cupsreject`** **deja de aceptar** trabajos nuevos pero imprime los que ya están.

## Herramientas de Linux para gestionar la impresión

| Herramienta | Función |
|-------------|---------|
| `cupsd` | Servicio (demonio) del servidor de impresión |
| `lpadmin` | Crear, modificar y eliminar colas; permisos por usuario |
| `lpinfo` | Listar dispositivos (`-v`) y controladores (`-m`) disponibles |
| `lpstat` | Estado de impresoras, colas y trabajos |
| `lp`, `lpr` | Enviar trabajos |
| `cancel`, `lprm` | Cancelar trabajos |
| `lpq` | Ver la cola (estilo BSD) |
| `lpmove` | Mover trabajos entre colas |
| `lpoptions` | Opciones por defecto (papel, dúplex, color) |
| `cupsenable` / `cupsdisable` | Activar o pausar una impresora |
| `cupsaccept` / `cupsreject` | Aceptar o rechazar trabajos |
| `cupsctl` | Ajustes globales del servidor (compartir, administración remota) |
| `driverless` | Detectar impresoras sin controlador (IPP Everywhere / AirPrint) |
| `ipptool` | Consultar a una impresora por IPP |
| `ipp-usb` | Hace que una impresora USB con IPP-over-USB funcione como impresora de red local |
| `lsusb`, `dmesg`, `journalctl` | Detección del hardware |
| Interfaz web `https://servidor:631` | Administración gráfica de CUPS |

## Archivos y rutas de CUPS

| Ruta | Contenido |
|------|-----------|
| `/etc/cups/cupsd.conf` | Configuración principal del servidor |
| `/etc/cups/printers.conf` | Colas definidas (lo gestiona CUPS; no se edita a mano) |
| `/etc/cups/ppd/` | Descripción de capacidades de cada cola (archivos PPD) |
| `/var/spool/cups/` | Trabajos en espera |
| `/var/log/cups/access_log` | Peticiones recibidas |
| `/var/log/cups/error_log` | Errores y diagnóstico |
| `/var/log/cups/page_log` | Registro de páginas impresas |
| `/usr/lib/cups/backend/` | Backends: `usb`, `ipp`, `socket`, `lpd`... |

> **Tendencia actual:** CUPS está reemplazando los controladores clásicos (archivos PPD) por la impresión **sin controlador** mediante IPP Everywhere. Por eso, siempre que la impresora lo soporte, en esta práctica se usa `-m everywhere`.

---

# Preparación del servidor de impresión

Ubuntu Server **no incluye CUPS** en la instalación mínima. Aquí se instala solo el núcleo del sistema de impresión; las herramientas adicionales se instalan **en el paso donde se necesitan**, en los recuadros **"Instalación necesaria"**.

### Comprobar si CUPS ya está instalado

```bash
dpkg -l cups 2>/dev/null | grep ^ii || echo "CUPS no está instalado"
```

### Instalar el servidor de impresión

```bash
sudo apt update
sudo apt install -y cups cups-client cups-bsd cups-filters avahi-daemon
```

| Paquete | Función |
|---------|---------|
| `cups` | Servidor de impresión (`cupsd`) e interfaz web |
| `cups-client` | Comandos `lp`, `lpstat`, `lpadmin`, `cancel`, `lpoptions` |
| `cups-bsd` | Comandos estilo BSD: `lpr`, `lpq`, `lprm` |
| `cups-filters` | Filtros de conversión de documentos y la herramienta `driverless` |
| `avahi-daemon` | Descubrimiento de impresoras en la red (mDNS/DNS-SD) |

### Paquetes que se instalarán más adelante

| Paquete | Para qué | Dónde se instala |
|---------|----------|------------------|
| `usbutils` | `lsusb` (detectar la impresora USB) | Impresora USB, paso 2 |
| `ipp-usb` | Impresoras USB sin controlador (IPP-over-USB) | Impresora USB, paso 3 |
| `hplip`, `printer-driver-*`, `foomatic-db-compressed-ppds` | Controladores según la marca | Impresora USB, paso 4 / TCP/IP, paso 5 |
| `printer-driver-foo2zjs` | Impresoras HP láser que HPLIP no incluye (por ejemplo, LaserJet Pro M12w) | Impresora USB, paso 4 |
| `avahi-utils` | `avahi-browse` (buscar impresoras en la red) | Impresora TCP/IP, paso 1 |
| `iputils-ping`, `netcat-openbsd` | `ping` y `nc` (conectividad y puertos) | Impresora TCP/IP, paso 2 |
| `cups-ipp-utils` | `ipptool` (consultar la impresora por IPP) | Impresora TCP/IP, paso 3 |
| `ufw` | Firewall, para compartir la impresora | Impresora compartida |
| `samba`, `smbclient` | Compartir la impresora por SMB y probarla | Impresora USB compartida con Samba |

### Habilitar el servicio y dar permisos de administración

```bash
sudo systemctl enable --now cups
sudo usermod -aG lpadmin alumno     # permite administrar impresoras
newgrp lpadmin                      # aplica el grupo en la sesión actual
```

### Comprobar el servicio

```bash
systemctl status cups --no-pager | tee ~/evidencias/0-cups-estado.txt
apt policy cups | head -n 3 | tee -a ~/evidencias/0-cups-estado.txt
lpstat -r
```

```
● cups.service - CUPS Scheduler
     Active: active (running) ...
scheduler is running
```

### Interfaz web desde otro equipo (opcional)

Por defecto CUPS solo atiende en `localhost`. Para administrarlo desde la LAN:

**Instalación necesaria** (el firewall suele venir incluido; esto lo asegura):

```bash
sudo apt install -y ufw
```

```bash
sudo cupsctl --remote-admin --remote-any
sudo ufw allow from 192.168.1.0/24 to any port 631 proto tcp comment 'CUPS LAN'
```

Desde el navegador del cliente: `https://192.168.1.50:631` (acepta el certificado autofirmado e inicia sesión con un usuario del grupo `lpadmin`).

> 📸 **Evidencia 0:** `systemctl status cups` en `active (running)`.

---

# Instalación y configuración de impresora USB

## 1. Conexión física de la impresora al servidor

1. Enciende la impresora y verifica que no muestre errores (papel, tóner, atascos).
2. Conecta el cable **USB-A** a un puerto del servidor y el extremo **USB-B** (o USB-C) a la impresora.
3. Evita concentradores (*hubs*) USB sin alimentación propia.

**Si el servidor es una máquina virtual (VirtualBox):** con la VM encendida, menú **Dispositivos → USB → [nombre de la impresora]**. Para que se conecte siempre: **Configuración → USB → ☑ Habilitar controlador USB (2.0/3.0) → Añadir filtro** con la impresora.

**Si el servidor es una máquina virtual (VMware Fusion):** con la VM encendida, menú **Máquina virtual → USB y Bluetooth → Conectar [nombre de la impresora]**. La impresora deja de estar disponible en el Mac y pasa a la VM. Si al conectar el cable aparece un aviso preguntando a dónde conectar el dispositivo, elige la máquina virtual.

> 📸 **Evidencia 1:** fotografía de la impresora conectada al servidor (o la captura del dispositivo USB asignado a la VM).

## 2. Verificación del reconocimiento del dispositivo por Linux

**Instalación necesaria** (proporciona `lsusb`):

```bash
sudo apt install -y usbutils
```

Mensajes del kernel en tiempo real (ejecútalo **antes** de conectar el cable):

```bash
sudo journalctl -k -f
```

Al conectar aparecerá algo como:

```
usb 1-1: new high-speed USB device number 3 using xhci_hcd
usb 1-1: New USB device found, idVendor=03f0, idProduct=002a
usb 1-1: Product: HP LaserJet Professional P1102
usb 1-1: Manufacturer: Hewlett-Packard
usblp 1-1:1.0: usblp0: USB Bidirectional printer dev 3 if 0 alt 0 proto 2 vid 0x03F0 pid 0x002A
```

Pulsa `Ctrl+C` y comprueba:

```bash
lsusb | tee ~/evidencias/2.1-lsusb.txt
ls -l /dev/usb/lp* 2>/dev/null
```

```
Bus 001 Device 003: ID 03f0:002a HP, Inc LaserJet Professional P1102
crw-rw---- 1 root lp 180, 0 sep 27 19:10 /dev/usb/lp0
```

> Si la impresora soporta **IPP-over-USB**, puede que no aparezca `/dev/usb/lp0`: en ese caso la gestiona `ipp-usb` (ver paso 3).

> 📸 **Evidencia 2:** mensajes del kernel al conectar y salida de `lsusb`.

## 3. Identificación de la impresora

### 3.1 Datos del dispositivo USB

Usa el `idVendor:idProduct` que mostró `lsusb`:

```bash
sudo lsusb -v -d 03f0:002a 2>/dev/null | grep -E 'iManufacturer|iProduct|iSerial|bInterfaceClass|bInterfaceProtocol' \
  | tee ~/evidencias/2.2-usb-detalle.txt
```

```
  iManufacturer           1 Hewlett-Packard
  iProduct                2 HP LaserJet Professional P1102
  iSerial                 3 000000000Q8B4G8ESI1c
      bInterfaceClass         7 Printer
      bInterfaceProtocol      2 Bidirectional
```

| `bInterfaceClass 7` + `bInterfaceProtocol` | Significado |
|--------------------------------------------|-------------|
| `1` Unidirectional / `2` Bidirectional | Impresora USB clásica (requiere controlador) |
| `4` (IPP-over-USB) | Soporta impresión **sin controlador** por USB |

### 3.2 URI del dispositivo en CUPS

```bash
sudo lpinfo -v | tee ~/evidencias/2.3-lpinfo.txt
```

**Impresora USB clásica:**

```
direct usb://HP/LaserJet%20Professional%20P1102?serial=000000000Q8B4G8ESI1c
```

**Impresora con IPP-over-USB** (`bInterfaceProtocol 4` en el paso 3.1):

**Instalación necesaria:**

```bash
sudo apt install -y ipp-usb
```

`ipp-usb` se activa solo cuando detecta la impresora. Tras instalarlo, **desconecta y vuelve a conectar el cable USB**, y comprueba:

```bash
systemctl status ipp-usb --no-pager
driverless
```

```
ipp://HP%20LaserJet%20MFP%20M140w%20(USB)._ipp._tcp.local/
```

> Copia la URI exacta: la necesitarás en el paso 5.

> 📸 **Evidencia 3:** salida de `lpinfo -v` con la URI `usb://` (o la URI de `driverless`).

## 4. Instalación o selección del controlador correspondiente

Elige la opción según la impresora:

| Caso | Controlador | Cómo seleccionarlo |
|------|-------------|--------------------|
| **A. IPP-over-USB** (protocolo 4) | Sin controlador: **IPP Everywhere** | `-m everywhere` |
| **B. Controlador en los paquetes** | PPD del fabricante o de Gutenprint/Foomatic | Buscar con `lpinfo -m` |
| **C. HP con HPLIP** | Asistente de HP | `sudo hp-setup -i` |
| **D. Sin controlador específico** | Genérico PCL | `drv:///sample.drv/laserjet.ppd` |
| **E. HP láser que no aparece en HPLIP** (p. ej. LaserJet Pro M12w) | `foo2zjs` | Buscar con `lpinfo -m` tras instalar `printer-driver-foo2zjs` |

### Instalar el paquete de controladores (casos B, C, D y E)

El caso A **no necesita instalar nada**. En los demás, instala el paquete que corresponda a la marca:

| Marca | Paquete | Instalación |
|-------|---------|-------------|
| HP | `hplip` | `sudo apt install -y hplip` |
| HP láser basadas en ZjStream que HPLIP no incluye (caso E) | `printer-driver-foo2zjs` | `sudo apt install -y printer-driver-foo2zjs` |
| Epson, Canon y otras (inyección de tinta) | `printer-driver-gutenprint` | `sudo apt install -y printer-driver-gutenprint` |
| Brother (láser) | `printer-driver-brlaser` | `sudo apt install -y printer-driver-brlaser` |
| Samsung / Xerox (láser) | `printer-driver-splix` | `sudo apt install -y printer-driver-splix` |
| Varias marcas (base de datos Foomatic) | `foomatic-db-compressed-ppds` | `sudo apt install -y foomatic-db-compressed-ppds` |
| Genérico PCL (caso D) | Incluido en `cups` | — |

Ejemplo para una HP:

```bash
sudo apt install -y hplip
sudo systemctl restart cups
```

### Buscar un controlador (caso B)

```bash
lpinfo -m | grep -i 'p1102' | tee ~/evidencias/2.4-controladores.txt
```

```
drv:///hpcups.drv/hp-laserjet_professional_p1102.ppd HP LaserJet Professional p1102, hpcups 3.25.x
```

Copia el primer campo (el nombre del controlador).

> ⚠️ Algunos modelos de HP necesitan además un complemento propietario (*plugin*): `sudo hp-plugin -i`.

### Modelo que no aparece en la lista de HPLIP (caso E)

Algunas impresoras HP no tienen entrada propia en HPLIP. Es el caso de la **HP LaserJet Pro M12w**: al buscarla en la lista de `hpcups` solo aparecen modelos parecidos (M1132, M1136, P1102...). No elijas uno "parecido" a ciegas; primero comprueba si otro paquete trae el modelo exacto:

```bash
sudo apt install -y printer-driver-foo2zjs
sudo systemctl restart cups
lpinfo -m | grep -i 'm12w' | tee ~/evidencias/2.4-controladores.txt
```

```
foo2zjs:0/ppd/foo2zjs/HP-LaserJet_Pro_M12w.ppd HP LaserJet Pro M12w Foomatic/foo2zjs-z2 (recommended)
```

Ese es el controlador a usar: es específico del modelo y **no necesita el plugin propietario** de HP. En la interfaz web de CUPS aparece en la lista como *HP LaserJet Pro M12w Foomatic/foo2zjs-z2 (recommended)*.

> Si `foo2zjs` no diera buen resultado con tu unidad, la alternativa es el controlador de la gama anterior en HPLIP, que sí requiere el plugin: `drv:///hpcups.drv/hp-laserjet_professional_p1102w.ppd` y `sudo hp-plugin -i`. Imprime una página de prueba para decidir.

> 📸 **Evidencia 4:** el controlador encontrado (o la confirmación de IPP Everywhere).

## 5. Incorporación de la impresora al sistema

**Caso A (IPP-over-USB, sin controlador):**

```bash
sudo lpadmin -p USB_Lab -E \
  -v 'ipp://HP%20LaserJet%20MFP%20M140w%20(USB)._ipp._tcp.local/' \
  -m everywhere
```

**Caso B (USB clásica con controlador):**

```bash
sudo lpadmin -p USB_Lab -E \
  -v 'usb://HP/LaserJet%20Professional%20P1102?serial=000000000Q8B4G8ESI1c' \
  -m 'drv:///hpcups.drv/hp-laserjet_professional_p1102.ppd'
```

**Caso E (HP LaserJet Pro M12w con `foo2zjs`):**

```bash
sudo lpadmin -p USB_Lab -E \
  -v 'usb://HP/LaserJet%20Pro%20M12w?serial=XXXXXXXXXXXX' \
  -m 'foo2zjs:0/ppd/foo2zjs/HP-LaserJet_Pro_M12w.ppd'
```

> La URI del ejemplo es orientativa: copia la línea `usb://...` exacta que mostró `sudo lpinfo -v` en el paso 3.2.

| Opción | Significado |
|--------|-------------|
| `-p USB_Lab` | Nombre de la cola (sin espacios) |
| `-E` | Habilita la impresora y la pone a aceptar trabajos |
| `-v` | URI del dispositivo (paso 3) |
| `-m` | Controlador (paso 4) |

> Los mensajes del tipo *"Printer drivers are deprecated..."* son solo avisos: la cola se crea igualmente.

## 6. Creación y configuración de la cola de impresión

```bash
# Descripción y ubicación
sudo lpadmin -p USB_Lab -D "Impresora USB del laboratorio" -L "Servidor - Aula 3"

# Impresora predeterminada del servidor
sudo lpadmin -d USB_Lab

# Si un trabajo falla, cancelarlo en lugar de detener la impresora
sudo lpadmin -p USB_Lab -o printer-error-policy=abort-job

# Opciones disponibles y papel carta por defecto
lpoptions -p USB_Lab -l | grep -i -E 'pagesize|media'
sudo lpadmin -p USB_Lab -o PageSize=Letter
```

> El nombre exacto de la opción de papel (`PageSize` o `media`) y sus valores dependen del controlador; consúltalos con `lpoptions -p USB_Lab -l`.

La interfaz web ofrece lo mismo en: **Administración → Añadir impresora**.

## 7. Verificación del estado de la impresora

```bash
lpstat -p USB_Lab -l | tee ~/evidencias/2.7-estado-usb.txt
lpstat -v USB_Lab | tee -a ~/evidencias/2.7-estado-usb.txt
lpstat -a USB_Lab | tee -a ~/evidencias/2.7-estado-usb.txt
lpstat -d | tee -a ~/evidencias/2.7-estado-usb.txt
```

```
printer USB_Lab is idle.  enabled since dom 27 sep 2026 19:15:02
	Form mounted:
	Content types: any
	Printer types: unknown
	Description: Impresora USB del laboratorio
	Location: Servidor - Aula 3
	...
device for USB_Lab: usb://HP/LaserJet%20Professional%20P1102?serial=000000000Q8B4G8ESI1c
USB_Lab accepting requests since dom 27 sep 2026 19:15:02
system default destination: USB_Lab
```

Qué comprobar: **`idle`** + **`enabled`** + **`accepting requests`**.

> 📸 **Evidencia 7:** salida de `lpstat -p USB_Lab -l` y `lpstat -v`.

## 8. Envío de un trabajo de prueba

Página de prueba de CUPS:

```bash
lp -d USB_Lab /usr/share/cups/data/testprint
```

```
request id is USB_Lab-1 (1 file(s))
```

Documento de texto con datos que identifiquen la práctica:

```bash
{
  echo "PRÁCTICA - IMPRESORA USB"
  echo "Servidor : $(hostname)"
  echo "Alumno   : $(whoami)"
  echo "Fecha    : $(date)"
  echo "Cola     : USB_Lab"
} > /tmp/prueba-usb.txt

lp -d USB_Lab -t "Prueba USB" /tmp/prueba-usb.txt
```

> 📸 **Evidencia 8:** comandos `lp` con su `request id`.

## 9. Consulta del estado de la cola

Envía varios trabajos seguidos para verlos en la cola:

```bash
lpstat -o USB_Lab            # trabajos pendientes
lpq -P USB_Lab               # vista estilo BSD
lpstat -W completed -o USB_Lab | tee ~/evidencias/2.9-completados-usb.txt
```

```
Rank    Owner   Job     File(s)                         Total Size
active  alumno  2       Prueba USB                      1024 bytes

USB_Lab-1               alumno           12288   dom 27 sep 2026 19:16:40
USB_Lab-2               alumno            1024   dom 27 sep 2026 19:17:05
```

Practica la administración de trabajos:

```bash
cupsdisable USB_Lab                          # pausa la impresora
lp -d USB_Lab /tmp/prueba-usb.txt            # el trabajo queda en espera
lpstat -o USB_Lab                            # se ve pendiente
cancel USB_Lab-3                             # cancelarlo (usa el ID mostrado)
cupsenable USB_Lab                           # reanuda la impresora
```

> 📸 **Evidencia 9:** la cola con trabajos pendientes y la lista de completados.

## 10. Resultado de la prueba de impresión

```bash
sudo tail -n 5 /var/log/cups/page_log
sudo grep -i 'USB_Lab' /var/log/cups/error_log | tail -n 10
```

Resultado esperado:

- Hojas impresas: la página de prueba de CUPS y el texto de `/tmp/prueba-usb.txt`.
- `lpstat -W completed -o` muestra los trabajos como completados.
- `lpstat -p USB_Lab` vuelve a `idle`.

> 📸 **Evidencia 10:** fotografía de las hojas impresas y el registro de trabajos completados.

---

# Instalación y configuración de impresora TCP/IP

## 1. Dirección IP asignada a la impresora

**Obtener la IP:**

- En el **panel de la impresora**: Menú → Red → Configuración TCP/IP.
- Imprimiendo la **página de configuración de red** (en muchos modelos, manteniendo pulsado el botón de información o de Wi-Fi).
- Buscándola desde el servidor.

**Instalación necesaria** (proporciona `avahi-browse`):

```bash
sudo apt install -y avahi-utils
```

```bash
avahi-browse -rt _ipp._tcp | grep -E 'hostname|address' | tee ~/evidencias/3.1-descubrimiento.txt
```

```
   hostname = [HP-LaserJet-M404.local]
   address = [192.168.1.80]
```

**Asignar una IP fija.** Una impresora compartida debe tener siempre la misma IP. Hay dos formas:

| Método | Dónde |
|--------|-------|
| Reserva DHCP (recomendado) | En el router/servidor DHCP, asociando la MAC de la impresora a `192.168.1.80` |
| IP estática | Panel de la impresora o su página web: `http://192.168.1.80` |

Datos de ejemplo:

| Parámetro | Valor |
|-----------|-------|
| IP | `192.168.1.80` |
| Máscara | `255.255.255.0` |
| Puerta de enlace | `192.168.1.1` |

> 📸 **Evidencia 1:** página de configuración de red de la impresora (o el panel) mostrando la IP.

## 2. Verificación de conectividad entre el servidor Linux y la impresora

**Instalación necesaria** (`ping` y `nc`; en la instalación mínima pueden faltar):

```bash
sudo apt install -y iputils-ping netcat-openbsd
```

```bash
ping -c 4 192.168.1.80 | tee ~/evidencias/3.2-ping.txt
```

```
64 bytes from 192.168.1.80: icmp_seq=1 ttl=64 time=1.21 ms
...
4 packets transmitted, 4 received, 0% packet loss
```

Puertos de impresión abiertos en la impresora:

```bash
for p in 631 9100 515; do nc -zv -w 3 192.168.1.80 $p; done 2>&1 | tee ~/evidencias/3.2-puertos.txt
```

```
Connection to 192.168.1.80 631 port [tcp/ipp] succeeded!
Connection to 192.168.1.80 9100 port [tcp/*] succeeded!
nc: connect to 192.168.1.80 port 515 (tcp) timed out
```

> 📸 **Evidencia 2:** `ping` exitoso y puertos abiertos.

## 3. Identificación del protocolo utilizado para la comunicación

| Protocolo | Puerto | URI en CUPS | Características |
|-----------|--------|-------------|-----------------|
| **IPP** (*Internet Printing Protocol*) | 631/tcp | `ipp://IP/ipp/print` | Estándar actual. Bidireccional: informa el estado, niveles de tinta y capacidades. Permite impresión **sin controlador** (IPP Everywhere) |
| **IPPS** (IPP sobre TLS) | 631/tcp | `ipps://IP/ipp/print` | IPP **cifrado** |
| **AppSocket / JetDirect (RAW)** | 9100/tcp | `socket://IP:9100` | Envía los datos tal cual. Muy compatible, pero unidireccional y requiere controlador |
| **LPD/LPR** | 515/tcp | `lpd://IP/queue` | Protocolo antiguo de UNIX; se mantiene por compatibilidad |

Comprobar si la impresora soporta **IPP Everywhere**.

**Instalación necesaria** (proporciona `ipptool`):

```bash
sudo apt install -y cups-ipp-utils
```

```bash
ipptool -tv ipp://192.168.1.80/ipp/print get-printer-attributes.test 2>/dev/null \
  | grep -E 'printer-make-and-model|printer-state |ipp-versions-supported|document-format-supported' \
  | tee ~/evidencias/3.3-ipp.txt
```

```
printer-make-and-model (textWithoutLanguage) = HP LaserJet Pro M404dn
printer-state (enum) = idle
ipp-versions-supported (1setOf keyword) = 1.0,1.1,2.0
document-format-supported (1setOf mimeMediaType) = application/pdf,image/pwg-raster,image/urf,...
```

Si aparecen `image/pwg-raster` o `image/urf`, la impresora soporta **impresión sin controlador**.

> Si `/ipp/print` no responde, prueba otras rutas: `driverless` lista las URIs correctas de las impresoras detectadas.

**Protocolo elegido en esta práctica: IPP (puerto 631).** Si la impresora no soporta IPP, usa **AppSocket (9100)**.

> 📸 **Evidencia 3:** atributos IPP de la impresora.

## 4. Incorporación de la impresora al servidor

Lista las URIs detectadas en la red:

```bash
driverless
sudo lpinfo -v | grep -E 'ipp|socket|dnssd'
```

## 5. Instalación o selección del controlador

| Caso | Controlador | URI |
|------|-------------|-----|
| **A. Soporta IPP Everywhere** (recomendado) | `-m everywhere` (se genera automáticamente consultando la impresora) | `ipp://192.168.1.80/ipp/print` |
| **B. No soporta IPP** | PPD del fabricante (`lpinfo -m \| grep -i modelo`) | `socket://192.168.1.80:9100` |

**Instalación necesaria:**

- **Caso A:** ninguna. CUPS genera la descripción de la impresora consultándola por IPP.
- **Caso B:** instala el paquete de controladores de la marca (misma tabla que en la impresora USB, paso 4). Por ejemplo, para una HP:

```bash
sudo apt install -y hplip
sudo systemctl restart cups
```

## 6. Creación y configuración de la cola de impresión

**Caso A (IPP Everywhere):**

```bash
sudo lpadmin -p Red_Lab -E \
  -v ipp://192.168.1.80/ipp/print \
  -m everywhere \
  -D "Impresora de red del laboratorio" \
  -L "Aula 3 - junto a la puerta" \
  -o printer-error-policy=retry-job
```

**Caso B (AppSocket con controlador):**

```bash
lpinfo -m | grep -i 'm404'
sudo lpadmin -p Red_Lab -E \
  -v socket://192.168.1.80:9100 \
  -m 'NOMBRE_DEL_CONTROLADOR' \
  -D "Impresora de red del laboratorio" \
  -L "Aula 3 - junto a la puerta"
```

Opciones por defecto (papel carta, dúplex si está disponible):

```bash
lpoptions -p Red_Lab -l | grep -i -E 'media|pagesize|sides|duplex'
sudo lpadmin -p Red_Lab -o media=na_letter_8.5x11in
sudo lpadmin -p Red_Lab -o sides=two-sided-long-edge    # solo si la impresora tiene dúplex
```

> `printer-error-policy=retry-job` hace que, si la impresora está apagada o sin red, CUPS **reintente** en lugar de perder el trabajo.

## 7. Verificación del estado del dispositivo

Estado desde CUPS:

```bash
lpstat -p Red_Lab -l | tee ~/evidencias/3.7-estado-red.txt
lpstat -v Red_Lab | tee -a ~/evidencias/3.7-estado-red.txt
```

```
printer Red_Lab is idle.  enabled since dom 27 sep 2026 19:30:11
	Description: Impresora de red del laboratorio
	Location: Aula 3 - junto a la puerta
device for Red_Lab: ipp://192.168.1.80/ipp/print
```

Estado real consultado a la impresora por IPP (tóner y alertas):

```bash
ipptool -tv ipp://192.168.1.80/ipp/print get-printer-attributes.test 2>/dev/null \
  | grep -E 'printer-state|marker-names|marker-levels' | tee -a ~/evidencias/3.7-estado-red.txt
```

```
printer-state (enum) = idle
printer-state-reasons (keyword) = none
marker-names (nameWithoutLanguage) = black cartridge
marker-levels (integer) = 72
```

> 📸 **Evidencia 7:** estado de la cola y atributos IPP (estado y nivel de tóner).

## 8. Envío de una prueba de impresión

```bash
lp -d Red_Lab /usr/share/cups/data/testprint

{
  echo "PRÁCTICA - IMPRESORA TCP/IP"
  echo "Servidor  : $(hostname) ($(hostname -I | awk '{print $1}'))"
  echo "Impresora : 192.168.1.80 (IPP, puerto 631)"
  echo "Usuario   : $(whoami)"
  echo "Fecha     : $(date)"
} > /tmp/prueba-red.txt

lp -d Red_Lab -t "Prueba TCP/IP" /tmp/prueba-red.txt
```

## 9. Consulta del estado del trabajo

```bash
lpstat -o Red_Lab
lpstat -l -o Red_Lab                 # detalle: estado de cada trabajo
lpstat -W completed -o Red_Lab | tee ~/evidencias/3.9-completados-red.txt
```

Registro del envío por red:

```bash
sudo grep -E 'Red_Lab' /var/log/cups/error_log | tail -n 10
```

> 📸 **Evidencia 9:** trabajos en cola y completados.

## 10. Resultado obtenido

- Hojas impresas en la impresora de red.
- `lpstat -W completed -o Red_Lab` muestra los trabajos terminados.
- La impresora vuelve a `idle`.

> 📸 **Evidencia 10:** fotografía de la impresión y el registro de trabajos completados.

---

# Impresora compartida para varios usuarios

Así se demuestra la ventaja principal de centralizar la impresión: el servidor CUPS ofrece **ambas colas** a los equipos del laboratorio y controla quién puede imprimir.

### Compartir las colas

**Instalación necesaria** (firewall, si no lo instalaste para la interfaz web):

```bash
sudo apt install -y ufw
```

```bash
sudo cupsctl --share-printers
sudo lpadmin -p Red_Lab -o printer-is-shared=true
sudo lpadmin -p USB_Lab -o printer-is-shared=true
sudo ufw allow from 192.168.1.0/24 to any port 631 proto tcp comment 'CUPS LAN'
```

### Control de acceso por usuario o grupo

```bash
sudo lpadmin -p Red_Lab -u allow:@alumnos,profe1      # solo el grupo alumnos y profe1
sudo lpadmin -p USB_Lab -u allow:profe1               # la USB, solo el docente
```

### Cuotas por usuario

Máximo 50 páginas por usuario cada 24 horas:

```bash
sudo lpadmin -p Red_Lab -o job-quota-period=86400 -o job-page-limit=50
```

### Agregar la impresora en los clientes

**Instalación necesaria en clientes Linux sin entorno gráfico** (los escritorios Ubuntu ya traen CUPS):

```bash
sudo apt install -y cups cups-client
```

Windows y macOS no necesitan instalar nada: incluyen soporte IPP.

| Cliente | Dirección |
|---------|-----------|
| Linux (CUPS) | `sudo lpadmin -p Lab -E -v ipp://192.168.1.50:631/printers/Red_Lab -m everywhere` |
| Windows 10/11 | Configuración → Impresoras → Agregar → *"La impresora que deseo no está en la lista"* → *Seleccionar una impresora compartida por nombre* → `http://192.168.1.50:631/printers/Red_Lab` |
| macOS | Preferencias → Impresoras → `+` → IP → Protocolo IPP → Dirección `192.168.1.50`, Cola `printers/Red_Lab` |

### Verificar

```bash
lpstat -W completed -o Red_Lab     # en el servidor: trabajos de distintos usuarios y equipos
sudo tail -n 20 /var/log/cups/page_log
```

> 📸 **Evidencia extra:** trabajos de al menos dos usuarios o equipos distintos en la misma cola.

---

# Impresora USB compartida con Samba

La sección anterior comparte las colas por **IPP**, el protocolo propio de CUPS. Aquí se comparte la **impresora USB** además por **SMB**, el protocolo de las carpetas compartidas de Windows. Así los clientes la usan como `\\servidor\USB_Lab` y se autentican con sus **usuarios de Samba**.

```
 Cliente                      Servidor                                   Impresora
┌─────────┐  SMB 445/tcp  ┌──────────────────────────────────────┐
│ Windows │──────────────►│ smbd ──► CUPS (cola USB_Lab) ────────┼──► USB
│ Linux   │               │ [USB_Lab]   filtros y controlador    │
└─────────┘               └──────────────────────────────────────┘
```

Samba no imprime por sí mismo: recibe el trabajo, comprueba quién lo envía y se lo entrega a CUPS. Por eso hay **dos capas de permisos**, y las dos deben permitir al usuario:

| Capa | Dónde se configura | Quién puede imprimir en esta práctica |
|------|--------------------|---------------------------------------|
| **Samba** | `valid users` del recurso en `smb.conf` | El grupo `docentes` |
| **CUPS** | `lpadmin -p USB_Lab -u allow:...` | `profe1` (definido en la sección anterior) |

## 1. Requisitos

La cola `USB_Lab` debe estar creada y funcionando (impresora USB, pasos 5 a 8):

```bash
lpstat -p USB_Lab
```

Usuarios y grupos. Si hiciste la práctica de Samba ya existen; estos comandos solo crean lo que falte:

```bash
sudo groupadd -f docentes
sudo groupadd -f alumnos
id profe1  2>/dev/null || sudo useradd -m -s /bin/bash -G docentes profe1
id alumno1 2>/dev/null || sudo useradd -m -s /usr/sbin/nologin -G alumnos alumno1
```

## 2. Instalación de Samba

```bash
sudo apt install -y samba smbclient
smbd --version
```

Alta de los usuarios en Samba (omite los que ya aparezcan en `sudo pdbedit -L`):

```bash
sudo smbpasswd -a profe1
sudo smbpasswd -a alumno1
```

## 3. Carpeta de cola de Samba

Samba guarda aquí cada trabajo mientras se lo pasa a CUPS. No se crea sola:

```bash
sudo mkdir -p /var/spool/samba
sudo chmod 1777 /var/spool/samba
```

## 4. Configuración de `smb.conf`

Respalda el archivo y activa la impresión mediante CUPS en `[global]`. Los comandos eliminan cualquier ajuste anterior de impresión (incluido el bloque *"Sin impresoras"* de la práctica de Samba) y escriben el nuevo:

```bash
sudo cp -a /etc/samba/smb.conf /etc/samba/smb.conf.antes-impresora

sudo sed -i -e '/^[;# ]*load printers *=/d' -e '/^[;# ]*printing *=/d' \
            -e '/^[;# ]*printcap name *=/d' -e '/^[;# ]*disable spoolss *=/d' \
            -e '/^[;# ]*cups options *=/d' -e '/^ *# Sin impresoras/d' /etc/samba/smb.conf

sudo sed -i '/^\[global\]/a\   printing = cups\n   printcap name = cups\n   load printers = no' /etc/samba/smb.conf
```

| Directiva | Significado |
|-----------|-------------|
| `printing = cups` | Samba entrega los trabajos a CUPS |
| `printcap name = cups` | La lista de impresoras se obtiene de CUPS |
| `load printers = no` | No publica todas las colas automáticamente: solo las que se declaren como recurso |

Añade el recurso de la impresora al final del archivo:

```bash
sudo tee -a /etc/samba/smb.conf > /dev/null <<'EOF'

[USB_Lab]
   comment = Impresora USB del laboratorio
   path = /var/spool/samba
   printable = yes
   printer name = USB_Lab
   valid users = @docentes
   guest ok = no
   browseable = yes
EOF
```

| Directiva | Significado |
|-----------|-------------|
| `[USB_Lab]` | Nombre del recurso: los clientes usan `\\servidor\USB_Lab` |
| `path` | Carpeta de cola del paso 3 |
| `printable = yes` | Lo convierte en recurso de **impresora** (no de archivos) |
| `printer name` | Nombre exacto de la cola en CUPS (`lpstat -p`) |
| `valid users = @docentes` | Solo el grupo `docentes` puede conectarse |

> Si tu `smb.conf` tiene una línea `hosts allow`, comprueba que incluya **tu red real**.

> El `smb.conf` original de Ubuntu trae una sección `[printers]` que da acceso a **todas** las colas de CUPS a cualquier usuario de Samba. Si quieres compartir solo `USB_Lab`, elimina esa sección (o coméntala con `;`).

Valida la sintaxis:

```bash
testparm -s 2>&1 | tee ~/evidencias/5.1-testparm-impresora.txt
```

Debe mostrar `Loaded services file OK.` y el recurso `[USB_Lab]` con `printable = Yes`.

> 📸 **Evidencia SMB-1:** el recurso `[USB_Lab]` en la salida de `testparm -s`.

## 5. Reinicio del servicio y firewall

```bash
sudo systemctl restart smbd
sudo ufw allow from 192.168.1.0/24 to any port 445 proto tcp comment 'Samba LAN'
```

> Usa `restart`, no `reload`. Con `reload`, el servicio de impresión de Samba sigue aplicando los permisos anteriores del recurso.

## 6. Verificación del recurso

```bash
smbclient -L //localhost -U profe1
```

```
	Sharename       Type      Comment
	---------       ----      -------
	USB_Lab         Printer   Impresora USB del laboratorio
	IPC$            IPC       IPC Service (...)
```

El recurso debe aparecer con el tipo **`Printer`**.

> 📸 **Evidencia SMB-2:** la lista de recursos con `USB_Lab` de tipo `Printer`.

## 7. Prueba de impresión a través de Samba

Desde el servidor (o desde cualquier cliente Linux, cambiando `localhost` por la IP del servidor):

```bash
{
  echo "PRÁCTICA - IMPRESORA USB COMPARTIDA CON SAMBA"
  echo "Servidor : $(hostname)"
  echo "Usuario  : profe1"
  echo "Fecha    : $(date)"
} > /tmp/prueba-smb.txt

smbclient //localhost/USB_Lab -U profe1 -c 'print /tmp/prueba-smb.txt'
```

```
putting file /tmp/prueba-smb.txt as prueba-smb.txt-398 (0.3 kb/s) (average 0.3 kb/s)
```

Comprueba que el trabajo llegó a CUPS **con el usuario de Samba como propietario**:

```bash
lpstat -W completed -o USB_Lab | tee ~/evidencias/5.3-trabajos-samba.txt
```

```
USB_Lab-3               profe1            1024   sáb 03 oct 2026 14:14:16
```

> ⚠️ El mensaje `putting file` solo indica que **Samba** aceptó el trabajo. Si después no aparece en la lista de completados ni se imprime, lo rechazó **CUPS**: revisa los permisos de la cola (paso 8).

> 📸 **Evidencia SMB-3:** el comando `print` aceptado, el trabajo de `profe1` en la lista de completados y la hoja impresa.

## 8. Restricción y prueba de acceso denegado

Un usuario fuera de `valid users` no puede ni conectarse al recurso:

```bash
smbclient //localhost/USB_Lab -U alumno1 -c 'print /tmp/prueba-smb.txt'
# Esperado: tree connect failed: NT_STATUS_ACCESS_DENIED
```

Para autorizar a más usuarios hay que abrir **las dos capas** y reiniciar Samba. Por ejemplo, para permitir también al grupo `alumnos`:

```bash
sudo sed -i '/^\[USB_Lab\]/,$ s/valid users = @docentes$/valid users = @docentes @alumnos/' /etc/samba/smb.conf
sudo lpadmin -p USB_Lab -u allow:@alumnos,@docentes
sudo systemctl restart smbd
```

| Situación | Lo que ve el cliente |
|-----------|----------------------|
| Usuario fuera de `valid users` | `tree connect failed: NT_STATUS_ACCESS_DENIED` |
| `valid users` cambiado, pero Samba sin reiniciar | `NT_STATUS_ACCESS_DENIED opening remote file` |
| Samba lo permite, CUPS no | `putting file ...` (parece correcto), pero el trabajo no se imprime |

> 📸 **Evidencia SMB-4:** el intento de `alumno1` con `NT_STATUS_ACCESS_DENIED`.

## 9. Agregar la impresora en los clientes

En los clientes se elige un controlador **PostScript genérico**: el cliente envía PostScript y el servidor lo convierte al lenguaje de la impresora con su propio controlador. Así no hay que instalar el controlador del fabricante en cada equipo.

| Cliente | Pasos |
|---------|-------|
| **Windows 10/11** | Configuración → Bluetooth y dispositivos → Impresoras y escáneres → Agregar dispositivo → *Agregar manualmente* → *Seleccionar una impresora compartida por nombre* → `\\192.168.1.50\USB_Lab` → usuario `profe1` y su contraseña de Samba. Cuando pida controlador: fabricante **Microsoft** → **Microsoft PS Class Driver** (o **Generic** → **MS Publisher Imagesetter**) |
| **Linux (CUPS)** | Ver los comandos de abajo |
| **macOS** | Ajustes del Sistema → Impresoras y escáneres → Añadir → pestaña *Avanzado* → Tipo *Impresora Windows mediante spoolss* → URL `smb://192.168.1.50/USB_Lab` → Usar: *Impresora PostScript genérica* |

**Cliente Linux con CUPS** (el paquete `smbclient` aporta el backend `smb`):

```bash
sudo apt install -y cups cups-client smbclient
sudo lpadmin -p Lab_SMB -E \
  -v 'smb://profe1:CONTRASEÑA@192.168.1.50/USB_Lab' \
  -m drv:///sample.drv/generic.ppd
lp -d Lab_SMB /usr/share/cups/data/testprint
```

> La contraseña queda guardada en la configuración de CUPS del cliente, que solo `root` puede leer. No uses una contraseña que compartas con otros servicios.

> Si en Windows prefieres el controlador del fabricante, también funciona: el cliente envía los datos ya preparados y CUPS los pasa a la impresora sin convertir. Si en ese caso el registro de CUPS muestra `Unsupported format 'application/octet-stream'`, añade `cups options = raw` al recurso `[USB_Lab]`.

En el servidor, los trabajos de cada cliente aparecen con su usuario de Samba:

```bash
lpstat -W completed -o USB_Lab
sudo tail -n 10 /var/log/cups/page_log
```

> 📸 **Evidencia SMB-5:** la impresora agregada en el cliente y una hoja impresa desde él.

---

# Ventajas de TCP/IP frente a USB

| Criterio | Impresora USB | Impresora TCP/IP |
|----------|---------------|------------------|
| Usuarios simultáneos | 1 equipo; los demás dependen de que ese equipo la comparta | Todos los equipos de la red |
| Dependencia | Si el equipo anfitrión se apaga, nadie imprime | Independiente de cualquier PC |
| Ubicación | A menos de 5 m del equipo | Cualquier punto con red (hasta 100 m por tramo, o Wi-Fi) |
| Estado del dispositivo | Limitado | Completo por IPP: tóner, bandejas, errores, contadores |
| Administración | Local, en el equipo conectado | Remota: página web propia, IPP, SNMP |
| Escalabilidad | Una impresora por puerto USB | Decenas de impresoras gestionadas desde un servidor |
| Control de acceso y cuotas | Solo si el equipo anfitrión hace de servidor | Centralizado en CUPS: usuarios, grupos, cuotas y registros |
| Rendimiento con varios usuarios | Un cuello de botella: el equipo anfitrión procesa todo | La impresora recibe los trabajos directamente o desde un servidor dedicado |
| Coste y complejidad inicial | Bajo | Mayor (red, IP, seguridad) |
| Seguridad | Sin exposición a la red | Requiere protegerla (firewall, IPPS, contraseñas) |

**Conclusión para escenarios multiusuario:** con varios usuarios, la impresora TCP/IP gestionada desde un servidor CUPS ofrece:

- **disponibilidad**, porque no depende de un equipo de escritorio;
- **acceso concurrente** desde cualquier punto de la red;
- **administración centralizada**, con permisos por usuario o grupo, cuotas y registro de páginas;
- **monitoreo del dispositivo**.

La impresora USB sigue siendo la mejor opción para un puesto individual, por su sencillez y aislamiento.

---

## Anexo A. Lista de evidencias

| # | Apartado | Evidencia | Archivo en `~/evidencias` |
|---|----------|-----------|---------------------------|
| 0 | Preparación | CUPS activo | `0-cups-estado.txt` |
| USB-1 | Impresora USB | Fotografía de la conexión física | foto |
| USB-2 | Impresora USB | Kernel detecta el dispositivo y `lsusb` | `2.1-lsusb.txt` + captura |
| USB-3 | Impresora USB | Identificación (`lsusb -v`, `lpinfo -v`) | `2.2-usb-detalle.txt`, `2.3-lpinfo.txt` |
| USB-4 | Impresora USB | Controlador seleccionado | `2.4-controladores.txt` |
| USB-5/6 | Impresora USB | Comandos `lpadmin` de alta y configuración | captura |
| USB-7 | Impresora USB | Estado de la impresora | `2.7-estado-usb.txt` |
| USB-8 | Impresora USB | Trabajo de prueba enviado | captura |
| USB-9 | Impresora USB | Estado de la cola | `2.9-completados-usb.txt` |
| USB-10 | Impresora USB | Hoja impresa | foto |
| RED-1 | Impresora TCP/IP | IP de la impresora | foto/captura |
| RED-2 | Impresora TCP/IP | Conectividad (`ping`, puertos) | `3.2-ping.txt`, `3.2-puertos.txt` |
| RED-3 | Impresora TCP/IP | Protocolo identificado (IPP) | `3.3-ipp.txt` |
| RED-4/5/6 | Impresora TCP/IP | Alta de la cola y controlador | captura |
| RED-7 | Impresora TCP/IP | Estado del dispositivo | `3.7-estado-red.txt` |
| RED-8 | Impresora TCP/IP | Prueba enviada | captura |
| RED-9 | Impresora TCP/IP | Estado del trabajo | `3.9-completados-red.txt` |
| RED-10 | Impresora TCP/IP | Hoja impresa | foto |
| Extra | Compartida | Trabajos de varios usuarios o equipos | captura |
| SMB-1 | Samba | Recurso `[USB_Lab]` validado | `5.1-testparm-impresora.txt` |
| SMB-2 | Samba | Recurso de tipo `Printer` publicado | captura |
| SMB-3 | Samba | Trabajo impreso a través de Samba | `5.3-trabajos-samba.txt` + foto |
| SMB-4 | Samba | Acceso denegado a un usuario no autorizado | captura |
| SMB-5 | Samba | Impresora agregada en un cliente | captura + foto |

Empaquetar las evidencias:

```bash
tar czf evidencias-impresoras-$(hostname)-$(date +%F).tar.gz -C ~ evidencias
```

---

## Anexo B. Solución de problemas

### Comandos de diagnóstico

```bash
lpstat -t                                   # resumen completo de CUPS
sudo tail -f /var/log/cups/error_log        # errores en vivo
sudo cupsctl --debug-logging                # registro detallado
sudo cupsctl --no-debug-logging             # volver al registro normal
```

### Problemas frecuentes

| Síntoma | Causa probable | Solución |
|---------|----------------|----------|
| `lsusb` no muestra la impresora | Cable, puerto o impresora apagada; en VM, USB no asignado | Cambia cable o puerto; en VirtualBox: Dispositivos → USB; en VMware Fusion: Máquina virtual → USB y Bluetooth |
| El modelo HP no aparece en la lista de controladores | HPLIP no lo incluye (p. ej. LaserJet Pro M12w) | `sudo apt install -y printer-driver-foo2zjs` y busca con `lpinfo -m` (impresora USB, paso 4, caso E) |
| `lpinfo -v` no muestra `usb://` | Dispositivo gestionado por `ipp-usb` | Usa la URI que da `driverless` (caso A) |
| `lpadmin: Unable to create PPD: No IPP attributes` | La impresora no soporta IPP Everywhere o la URI es incorrecta | Comprueba la URI con `driverless`; o usa `socket://IP:9100` con controlador |
| `lpadmin: Forbidden` | Usuario sin permisos | Usa `sudo` o añade el usuario a `lpadmin` |
| Estado `stopped` / *disabled* | La impresora dio error y CUPS la pausó | Resuelve el error y ejecuta `cupsenable COLA` |
| `not accepting requests` | La cola está en modo rechazo | `cupsaccept COLA` |
| Trabajos atascados en la cola | Impresora apagada o inaccesible | `lpstat -l -o`; revisa la red; `cancel -a COLA` si hace falta |
| Imprime caracteres extraños | Controlador incorrecto | Cambia el controlador con `lpadmin -p COLA -m ...` |
| `ping` a la impresora falla | Otra subred, IP incorrecta o impresora sin red | Verifica la IP en el panel; que esté en `192.168.1.0/24` |
| Los clientes no ven la impresora compartida | No se comparte o el firewall bloquea 631 | `cupsctl --share-printers`; `printer-is-shared=true`; `ufw allow ... 631` |
| La IP de la impresora cambió | Asignación DHCP sin reserva | Reserva DHCP o IP estática (impresora TCP/IP, paso 1) |
| HP: `Missing plugin` | El modelo requiere el complemento de HP | `sudo hp-plugin -i` |

### Impresora compartida con Samba

| Síntoma | Causa probable | Solución |
|---------|----------------|----------|
| `smbclient -L` no muestra `USB_Lab` | Falta `printable = yes`, o `printer name` no coincide con la cola de CUPS | Compara con `lpstat -p`; `testparm -s`; `sudo systemctl restart smbd` |
| `tree connect failed: NT_STATUS_ACCESS_DENIED` | El usuario no está en `valid users` | Revisa el grupo con `id usuario` y el recurso en `smb.conf` |
| `NT_STATUS_ACCESS_DENIED opening remote file` tras cambiar `valid users` | Samba se recargó pero no se reinició | `sudo systemctl restart smbd` |
| `putting file ...` pero no se imprime ni aparece en completados | CUPS rechazó al usuario: `client-error-not-authorized` en `error_log` | `sudo lpadmin -p USB_Lab -u allow:...` con ese usuario o grupo |
| El trabajo llega a CUPS pero sale en blanco o con símbolos | Controlador equivocado en el **servidor** | Cambia el controlador de la cola (impresora USB, paso 4) |
| `Unsupported format 'application/octet-stream'` en `error_log` | El cliente envía datos del controlador del fabricante | Añade `cups options = raw` al recurso y reinicia `smbd` |
| Windows 11 no conecta: error `0x0000011b` o `0x00000709` | Desde la versión 22H2, Windows usa otro transporte para impresoras compartidas | En el cliente: directiva *Configurar las opciones de conexión RPC* → *RPC a través de canalizaciones con nombre*. Como alternativa, agrega la impresora por IPP (sección anterior) |
| Tiempo agotado desde el cliente | El firewall no permite 445, o `hosts allow` tiene otra red | `sudo ufw status`; revisa `hosts allow` |

Registro de lo que Samba entrega a CUPS:

```bash
sudo grep -E 'USB_Lab|not-authorized' /var/log/cups/error_log | tail -n 10
ls -l /var/spool/samba
```

Para volver a la configuración anterior de Samba:

```bash
sudo cp -a /etc/samba/smb.conf.antes-impresora /etc/samba/smb.conf
sudo systemctl restart smbd
```

### Eliminar una cola para repetir la práctica

```bash
cancel -a USB_Lab
sudo lpadmin -x USB_Lab
```

---

## Anexo C. Práctica sin impresora física (impresora PDF)

Si en algún momento no hay impresora disponible, puedes practicar colas, trabajos y administración con una **impresora virtual que genera PDF**. **No sustituye** las evidencias de las impresoras USB y TCP/IP.

**Instalación necesaria:**

```bash
sudo apt install -y printer-driver-cups-pdf
sudo lpadmin -p PDF_Lab -E -v cups-pdf:/ -m lsb/usr/cups-pdf/CUPS-PDF_opt.ppd
```

> Si el controlador no se encuentra con ese nombre, búscalo con `lpinfo -m | grep -i pdf`.

```bash
lp -d PDF_Lab /usr/share/cups/data/testprint
lpstat -W completed -o PDF_Lab
ls ~/PDF/
```

El PDF generado aparece en `~/PDF/`.