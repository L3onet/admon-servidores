#!/usr/bin/env bash

# ==================================================
# APARTADO F. ACCESO REMOTO GRÁFICO MEDIANTE VNC
#
# Uso:
# sudo bash evaluar_apartado_f.sh IP_SERVIDOR IP_CLIENTE
#
# F1: 2 puntos
# F2: 3 puntos
# F3: Evaluación manual (3 puntos)
# F4: 4 puntos
#
# TOTAL AUTOMÁTICO: 9 PUNTOS
# ==================================================

if [ "$#" -ne 2 ]; then
    echo "Uso: sudo bash $0 ip_servidor ip_cliente"
    exit 1
fi

IP_SERVIDOR="$1"
IP_CLIENTE="$2"

if [ "$EUID" -ne 0 ]; then
    echo "Error: ejecute el script con sudo."
    exit 1
fi

export LC_ALL=C

declare -A ESTADO ERRORES PUNTOS

PUNTOS=(
    [F1]=2
    [F2]=3
    [F4]=4
)

for i in F1 F2 F4; do
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

if ! validar_ip "$IP_SERVIDOR" ||
   ! validar_ip "$IP_CLIENTE"; then
    echo "Error: dirección IPv4 inválida."
    exit 1
fi

# Convierte una IPv4 a entero.
ip_a_entero() {
    local IFS=.
    local -a o
    read -r -a o <<< "$1"
    echo $(( (10#${o[0]} << 24) + (10#${o[1]} << 16) + (10#${o[2]} << 8) + 10#${o[3]} ))
}

# Limpia el origen de una regla UFW: quita el comentario
# (# ...) y los espacios sobrantes.
limpiar_origen() {
    printf '%s\n' "$1" |
        sed -E 's/[[:space:]]*#.*$//; s/[[:space:]]+$//; s/^[[:space:]]+//'
}

# Devuelve 0 si el origen de la regla es la IP del cliente
# o una red concreta (CIDR, mínimo /16) que la contiene.
# "Anywhere" y 0.0.0.0/0 no son orígenes autorizados.
origen_autoriza_cliente() {
    local origen red mascara bits
    origen=$(limpiar_origen "$1")

    if [ "$origen" = "$IP_CLIENTE" ] ||
       [ "$origen" = "$IP_CLIENTE/32" ]; then
        return 0
    fi

    [[ "$origen" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]{1,2})$ ]] ||
        return 1

    red="${origen%/*}"
    bits="${origen#*/}"

    validar_ip "$red" || return 1
    (( bits >= 16 && bits <= 32 )) || return 1

    mascara=$(( (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF ))

    (( ($(ip_a_entero "$red") & mascara) ==
       ($(ip_a_entero "$IP_CLIENTE") & mascara) ))
}

# ==================================================
# F1. INSTALACIÓN VNC Y USUARIO AUTORIZADO
# 2 PUNTOS
# ==================================================

if ! dpkg-query -W -f='${binary:Package} ${Status}\n' \
     'tigervnc*' 'tightvnc*' 2>/dev/null |
     grep -Eq '^(tigervnc|tightvnc).* install ok installed$'; then

    fallar F1 \
        "No se encontró TigerVNC o TightVNC instalado."
fi

if ! id profe1 >/dev/null 2>&1; then
    fallar F1 "El usuario profe1 no existe."
fi

HOME_PROFE=$(getent passwd profe1 | cut -d: -f6)

if [ -z "$HOME_PROFE" ]; then
    fallar F1 \
        "No se encontró el directorio personal de profe1."
else
    VNC_DIR="$HOME_PROFE/.vnc"

    if [ ! -d "$VNC_DIR" ]; then
        fallar F1 \
            "No existe el directorio $VNC_DIR."
    elif [ ! -r "$VNC_DIR" ]; then
        fallar F1 \
            "No se puede consultar el directorio VNC."
    fi
fi

# ==================================================
# F2. CONFIGURACIÓN DE SESIÓN VNC
# 3 PUNTOS
#
# Se revisa localmente la sesión de profe1.
# No se ejecuta vncviewer desde Windows.
# ==================================================

if ! id profe1 >/dev/null 2>&1; then

    fallar F2 \
        "No se puede evaluar VNC: profe1 no existe."

else

    # Comprobar que vncserver esté disponible
    # en el entorno del usuario.

    # runuser -l inicia sesión de login: HOME y PATH son los de profe1.
    if ! runuser -l profe1 -s /bin/bash -c 'command -v vncserver' \
         >/dev/null 2>&1; then

        fallar F2 \
            "El comando vncserver no está disponible para profe1."

    else

        # Consultar las sesiones VNC del usuario.

        SALIDA_VNC=$(
            runuser -l profe1 -s /bin/bash -c 'vncserver -list' 2>&1
        )

        CODIGO_VNC=$?

        if [ "$CODIGO_VNC" -ne 0 ]; then

            fallar F2 \
                "No se pudo consultar vncserver -list: $SALIDA_VNC"

        elif ! printf '%s\n' "$SALIDA_VNC" |
             grep -Eq '^[[:space:]]*:?1[[:space:]]+5901([[:space:]]|$)'; then
            # vncserver -list muestra "1   5901 ..." (pantalla y puerto);
            # algunas versiones escriben ":1".

            fallar F2 \
                "No se encontró una sesión VNC activa en :1 para profe1."

        fi
    fi
fi

# ==================================================
# F3. NO SE EVALÚA AUTOMÁTICAMENTE
#
# El docente comprobará la conexión desde
# Windows y asignará manualmente 3 puntos.
# ==================================================

# ==================================================
# F4. RESTRICCIÓN DE ACCESO MEDIANTE UFW
# 4 PUNTOS
#
# Se asume:
# IP_CLIENTE = Windows autorizado.
# Puerto VNC = 5901/TCP.
#
# Política requerida:
# - UFW activo.
# - Entrada denegada por defecto.
# - Permitir 5901/TCP solo desde IP_CLIENTE.
# - No permitir acceso general a 5901/TCP.
# ==================================================

if ! command -v ufw >/dev/null 2>&1; then

    fallar F4 "UFW no está instalado."

else

    UFW_VERBOSE=$(ufw status verbose 2>&1)
    UFW_NUMBERED=$(ufw status numbered 2>&1)

    if ! printf '%s\n' "$UFW_VERBOSE" |
         grep -q '^Status: active'; then

        fallar F4 "El firewall UFW no está activo."

    else

        if ! printf '%s\n' "$UFW_VERBOSE" |
             grep -Eq '^Default: deny \(incoming\)'; then

            fallar F4 \
                "La política predeterminada de entrada no es deny."
        fi

        REGLAS_5901=$(
            printf '%s\n' "$UFW_NUMBERED" |
            sed -E 's/^\[[[:space:]]*[0-9]+\][[:space:]]*//' |
            awk '
              $0 ~ /^5901(\/tcp)?[[:space:]]/ {
                  print
              }
            '
        )

        PERMITIDO=0

        while IFS= read -r linea; do

            [ -z "$linea" ] && continue

            if ! printf '%s\n' "$linea" |
                 grep -q 'ALLOW IN'; then
                continue
            fi

            ORIGEN=$(
                printf '%s\n' "$linea" |
                sed -E 's/^.*ALLOW IN[[:space:]]+//'
            )
            ORIGEN=$(limpiar_origen "$ORIGEN")   # sin "# comentario"

            if origen_autoriza_cliente "$ORIGEN"; then

                PERMITIDO=1

            else

                fallar F4 \
                    "Existe una regla ALLOW para VNC desde '$ORIGEN'."
            fi

        done <<< "$REGLAS_5901"

        if [ "$PERMITIDO" -ne 1 ]; then
            fallar F4 \
                "No existe ALLOW IN para 5901/tcp desde $IP_CLIENTE."
        fi

        # Verificar reglas generales que abran
        # todos los puertos desde cualquier IP.

        if printf '%s\n' "$UFW_NUMBERED" |
           grep -Eq '^(\[[[:space:]]*[0-9]+\][[:space:]]*)?Anywhere[[:space:]]+ALLOW IN[[:space:]]+Anywhere'; then

            fallar F4 \
                "Existe una regla general que permite tráfico entrante."
        fi
    fi
fi

# ==================================================
# RESULTADOS
# ==================================================

TOTAL=0

echo "========================================="
echo "RESULTADOS - APARTADO F"
echo "========================================="

for indicador in F1 F2; do

    echo "$indicador -> ${ESTADO[$indicador]}"

    if [ "${ESTADO[$indicador]}" = "No" ]; then
        printf '%s' "${ERRORES[$indicador]}"
    else
        TOTAL=$((TOTAL + PUNTOS[$indicador]))
    fi

done

echo "F3 -> No evaluado (verificación desde Windows)"

echo "F4 -> ${ESTADO[F4]}"

if [ "${ESTADO[F4]}" = "No" ]; then
    printf '%s' "${ERRORES[F4]}"
else
    TOTAL=$((TOTAL + PUNTOS[F4]))
fi

echo "-----------------------------------------"
echo "PUNTUACIÓN AUTOMÁTICA: $TOTAL / 9"
echo "F3 PENDIENTE: 3 puntos"
echo "TOTAL DEL APARTADO: 12 puntos"
echo "========================================="