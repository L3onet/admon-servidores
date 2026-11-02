#!/usr/bin/env bash

# ==================================================
# APARTADO H. ADMINISTRACIÓN DE IMPRESORAS
# TOTAL AUTOMÁTICO: 12 PUNTOS
#
# Uso:
# sudo bash evaluar_apartado_h.sh IP_SERVIDOR IP_CLIENTE
#
# H1: CUPS (3 puntos)
# H2: Impresora USB (3 puntos)
# H3: Impresora TCP/IP (3 puntos)
# H4: Colas de impresión (3 puntos)
# H5: No evaluado (Windows)
# ==================================================

if [ "$#" -ne 2 ]; then
    echo "Uso: sudo bash $0 ip_servidor ip_cliente"
    exit 1
fi

IP_SERVIDOR="$1"
IP_CLIENTE="$2"

if [ "$EUID" -ne 0 ]; then
    echo "Error: ejecute con sudo."
    exit 1
fi

export LC_ALL=C

# ==========================================
# CONFIGURACIÓN
# ==========================================

IMPRESORA_USB="Impresora_USB"
IMPRESORA_RED="Impresora_Red"

# IP de impresora de red.
# Se puede cambiar sin modificar el script:
# sudo IP_IMPRESORA=192.168.1.50 bash ...
IP_IMPRESORA="${IP_IMPRESORA:-192.168.1.50}"

declare -A ESTADO ERRORES PUNTOS

PUNTOS=(
    [H1]=3
    [H2]=3
    [H3]=3
    [H4]=3
)

for i in H1 H2 H3 H4; do
    ESTADO[$i]="Si"
    ERRORES[$i]=""
done

fallar() {
    local indicador="$1"
    local motivo="$2"

    ESTADO[$indicador]="No"
    ERRORES[$indicador]+="  - $motivo"$'\n'
}

validar_ip() {
    local ip="$1"
    local octeto
    local -a partes

    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] ||
        return 1

    IFS='.' read -r -a partes <<< "$ip"

    [ "${#partes[@]}" -eq 4 ] || return 1

    for octeto in "${partes[@]}"; do
        (( 10#$octeto <= 255 )) || return 1
    done
}

for direccion in "$IP_SERVIDOR" "$IP_CLIENTE" "$IP_IMPRESORA"; do
    if ! validar_ip "$direccion"; then
        echo "Error: dirección IPv4 inválida: $direccion"
        exit 1
    fi
done

existe_comando() {
    command -v "$1" >/dev/null 2>&1
}

# Consultar cola configurada en CUPS.
existe_cola() {
    lpstat -p "$1" >/dev/null 2>&1
}

# Enviar un trabajo y recuperar su identificador.
enviar_trabajo() {
    local cola="$1"
    local mensaje="$2"

    printf '%s\n' "$mensaje" |
        lp -d "$cola" 2>&1
}

# ==================================================
# H1. INSTALACIÓN Y FUNCIONAMIENTO DE CUPS
# 3 PUNTOS
# ==================================================

if ! dpkg-query -W -f='${Status}' cups 2>/dev/null |
     grep -Fxq 'install ok installed'; then

    fallar H1 "El paquete cups no está instalado."
fi

if ! systemctl is-active --quiet cups; then
    fallar H1 "El servicio cups no está activo."
fi

if ! systemctl status cups --no-pager \
     >/dev/null 2>&1; then

    fallar H1 \
        "No se pudo consultar el estado del servicio cups."
fi

if ! existe_comando lpstat; then
    fallar H1 "El comando lpstat no está disponible."
else
    if ! lpstat -r 2>/dev/null |
         grep -Fq 'scheduler is running'; then

        fallar H1 \
            "El planificador de impresión no está funcionando."
    fi
fi

if ! ss -tlnp |
     awk '$1=="LISTEN" && $4 ~ /:631$/ {ok=1}
          END {exit !ok}'; then

    fallar H1 "El puerto TCP 631 no está escuchando."
fi

# ==================================================
# H2. CONFIGURACIÓN DE IMPRESORA USB
# 3 PUNTOS
# ==================================================

if ! existe_comando lsusb; then
    fallar H2 "El comando lsusb no está instalado."
else
    if ! lsusb >/dev/null 2>&1; then
        fallar H2 "No se pudieron consultar dispositivos USB."
    fi
fi

if ! existe_comando lpinfo; then
    fallar H2 "El comando lpinfo no está disponible."
else
    if ! lpinfo -v >/dev/null 2>&1; then
        fallar H2 \
            "No se pudieron consultar dispositivos de impresión."
    fi
fi

if ! existe_comando lpstat; then
    fallar H2 "lpstat no está disponible."
else

    lpstat -v >/dev/null 2>&1 ||
        fallar H2 "No se pudieron consultar las impresoras."

    lpstat -p >/dev/null 2>&1 ||
        fallar H2 "No se pudo consultar el estado de impresoras."

    lpstat -a >/dev/null 2>&1 ||
        fallar H2 "No se pudo consultar aceptación de trabajos."
fi

if ! existe_cola "$IMPRESORA_USB"; then

    fallar H2 \
        "No existe la cola de impresión '$IMPRESORA_USB'."

else

    URI_USB=$(lpstat -v "$IMPRESORA_USB" 2>/dev/null)

    # Se exige una conexión USB real.
    # Para impresoras virtuales se debe adaptar
    # este criterio.
    if ! printf '%s\n' "$URI_USB" |
         grep -Eqi 'usb://'; then

        fallar H2 \
            "La impresora $IMPRESORA_USB no utiliza una conexión USB."
    fi

    if ! lpstat -a "$IMPRESORA_USB" 2>/dev/null |
         grep -q 'accepting requests'; then

        fallar H2 \
            "La impresora USB no acepta trabajos."
    fi

    # Trabajo de prueba.
    if ! enviar_trabajo "$IMPRESORA_USB" \
         "Prueba de impresion USB" >/dev/null 2>&1; then

        fallar H2 \
            "No se pudo enviar el trabajo a $IMPRESORA_USB."
    fi
fi

# ==================================================
# H3. CONFIGURACIÓN DE IMPRESORA TCP/IP
# 3 PUNTOS
# ==================================================

if ! existe_cola "$IMPRESORA_RED"; then

    fallar H3 \
        "No existe la impresora '$IMPRESORA_RED'."

else

    URI_RED=$(lpstat -v "$IMPRESORA_RED" 2>/dev/null)

    if ! printf '%s\n' "$URI_RED" |
         grep -Eqi 'socket://|ipp://|ipps://|lpd://'; then

        fallar H3 \
            "La impresora de red no tiene una URI TCP/IP reconocida."
    fi

    if ! lpstat -a "$IMPRESORA_RED" 2>/dev/null |
         grep -q 'accepting requests'; then

        fallar H3 \
            "La impresora de red no acepta trabajos."
    fi
fi

# Comprobar conectividad con impresora de red.
if ! ping -n -c 3 -W 2 "$IP_IMPRESORA" \
     >/dev/null 2>&1; then

    fallar H3 \
        "La impresora $IP_IMPRESORA no responde al ping."
fi

# Puede utilizar IPP (631) o JetDirect (9100).
PUERTO_OK=0

if nc -z -w 3 "$IP_IMPRESORA" 631 \
   >/dev/null 2>&1; then
    PUERTO_OK=1
fi

if nc -z -w 3 "$IP_IMPRESORA" 9100 \
   >/dev/null 2>&1; then
    PUERTO_OK=1
fi

if [ "$PUERTO_OK" -ne 1 ]; then
    fallar H3 \
        "No responde ningún puerto de impresión (631 o 9100)."
fi

if existe_cola "$IMPRESORA_RED"; then

    if ! enviar_trabajo "$IMPRESORA_RED" \
         "Prueba de impresion TCP/IP" >/dev/null 2>&1; then

        fallar H3 \
            "No se pudo enviar el trabajo a $IMPRESORA_RED."
    fi
fi

# ==================================================
# H4. ADMINISTRACIÓN DE COLAS DE IMPRESIÓN
# 3 PUNTOS
# ==================================================

if ! lpstat -t >/dev/null 2>&1; then
    fallar H4 "No se pudo consultar el estado general."
fi

if ! lpstat -o >/dev/null 2>&1; then
    fallar H4 "No se pudieron consultar trabajos de impresión."
fi

if ! lpstat -p >/dev/null 2>&1; then
    fallar H4 "No se pudieron consultar las colas."
fi

if ! existe_cola "$IMPRESORA_RED"; then

    fallar H4 \
        "No existe la cola $IMPRESORA_RED."

else

    # Crear trabajo de prueba.
    RESPUESTA=$(enviar_trabajo "$IMPRESORA_RED" \
        "Trabajo de prueba")

    CODIGO=$?

    if [ "$CODIGO" -ne 0 ]; then

        fallar H4 \
            "No se pudo crear un trabajo de impresión."

    else

        # Obtener ID del trabajo devuelto por lp.
        JOB_ID=$(
            printf '%s\n' "$RESPUESTA" |
            sed -nE \
            's/^request id is ([^ ]+).*/\1/p'
        )

        if [ -z "$JOB_ID" ]; then

            fallar H4 \
                "No se pudo identificar el trabajo enviado."

        else

            # Cancelar solamente el trabajo creado
            # por el propio script.
            if ! cancel "$JOB_ID" >/dev/null 2>&1; then

                fallar H4 \
                    "No se pudo cancelar el trabajo $JOB_ID."
            fi
        fi
    fi
fi

# ==================================================
# H5. NO SE EVALÚA AUTOMÁTICAMENTE
#
# La prueba corresponde a un cliente Windows.
# ==================================================

# ==================================================
# RESULTADOS
# ==================================================

TOTAL=0

echo "========================================="
echo "RESULTADOS - APARTADO H"
echo "========================================="

for indicador in H1 H2 H3 H4; do

    echo "$indicador -> ${ESTADO[$indicador]}"

    if [ "${ESTADO[$indicador]}" = "No" ]; then
        printf '%s' "${ERRORES[$indicador]}"
    else
        TOTAL=$((TOTAL + PUNTOS[$indicador]))
    fi

done

echo "H5 -> No evaluado (cliente Windows)"

echo "-----------------------------------------"
echo "PUNTUACIÓN AUTOMÁTICA: $TOTAL / 12"
echo "H5 PENDIENTE: 2 puntos"
echo "TOTAL DEL APARTADO: 14 puntos"
echo "========================================="