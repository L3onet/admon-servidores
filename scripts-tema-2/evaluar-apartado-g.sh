#!/usr/bin/env bash

# ==================================================
# APARTADO G. VERIFICACIÓN INTEGRAL ACCESO REMOTO
# TOTAL: 8 PUNTOS
#
# Uso:
# sudo bash evaluar_apartado_g.sh IP_SERVIDOR IP_CLIENTE
#
# G1: Identificación del servidor (2 puntos)
# G2: Registros SSH remotos (3 puntos)
# G3: Archivo de evidencia creado en el acceso remoto (3 puntos)
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
    [G1]=2
    [G2]=3
    [G3]=3
)

for i in G1 G2 G3; do
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

# ==================================================
# G1. IDENTIFICACIÓN DEL SERVIDOR
# 2 PUNTOS
# ==================================================

if ! hostname >/dev/null 2>&1; then
    fallar G1 "No se pudo consultar hostname."
fi

if ! whoami >/dev/null 2>&1; then
    fallar G1 "No se pudo identificar el usuario."
fi

if ! date >/dev/null 2>&1; then
    fallar G1 "No se pudo consultar la fecha del sistema."
fi

if ! hostname -I >/dev/null 2>&1; then
    fallar G1 "No se pudieron consultar las direcciones IP."
fi

if ! ip -o -4 addr show scope global |
     awk -v ip="$IP_SERVIDOR" '
     {
         split($4, direccion, "/")
         if (direccion[1] == ip)
             encontrado=1
     }
     END {exit !encontrado}
     '; then

    fallar G1 \
        "La IP $IP_SERVIDOR no está asignada al servidor."
fi

if ! id profe1 >/dev/null 2>&1; then
    fallar G1 "El usuario profe1 no existe."
fi

# ==================================================
# G2. REGISTROS DE INICIO DE SESIÓN REMOTO
# 3 PUNTOS
#
# Verifica:
# - Servicio SSH activo.
# - Registros de los últimos 15 minutos.
# - Autenticación aceptada para profe1.
# - Origen de conexión: IP_CLIENTE.
# ==================================================

if ! systemctl is-active --quiet ssh; then
    fallar G2 "El servicio SSH no está activo."
fi

if ! journalctl -u ssh --since '15 minutes ago' \
     --no-pager >/dev/null 2>&1; then

    fallar G2 "No se pudieron consultar los registros SSH."

else

    REGISTROS=$(
        journalctl -u ssh \
            --since '15 minutes ago' \
            --no-pager 2>/dev/null
    )

    if ! printf '%s\n' "$REGISTROS" |
         grep -Eq 'Accepted (publickey|password|keyboard-interactive) for profe1'; then

        fallar G2 \
            "No se encontró un inicio de sesión SSH aceptado para profe1 en los últimos 15 minutos."
    fi

    if ! printf '%s\n' "$REGISTROS" |
         grep -E 'Accepted (publickey|password|keyboard-interactive) for profe1' |
         grep -Fq "from $IP_CLIENTE port"; then

        fallar G2 \
            "No se encontró una autenticación aceptada de profe1 desde $IP_CLIENTE."
    fi

fi

# Comprobar sesiones actuales, como información
# complementaria y no como requisito obligatorio.

SESIONES_WHO=$(who 2>/dev/null)
SESIONES_W=$(w -h 2>/dev/null)

CONEXIONES=$(ss -tnp 2>/dev/null |
    grep -E ':22|:5901' || true)

# ==================================================
# G3. ARCHIVO CREADO DE FORMA REMOTA
# 3 PUNTOS
#
# Práctica (sección 4.4): desde el escritorio remoto
# VNC, profe1 crea
#   ~/Escritorio/evidencia-vnc.txt   (o ~/Desktop/...)
# con el texto "Acceso remoto por VNC - <fecha>".
#
# Se acepta también el archivo alternativo
#   ~/evidencia_remota.txt
# con la línea exacta "Archivo creado remotamente".
# ==================================================

if ! id profe1 >/dev/null 2>&1; then

    fallar G3 "El usuario profe1 no existe."

else

    HOME_PROFE=$(getent passwd profe1 | cut -d: -f6)

    ARCHIVO=""
    TEXTO=""

    for candidato in \
        "$HOME_PROFE/Escritorio/evidencia-vnc.txt" \
        "$HOME_PROFE/Desktop/evidencia-vnc.txt" \
        "$HOME_PROFE/evidencia-vnc.txt" \
        "$HOME_PROFE/evidencia_remota.txt"; do

        if [ -f "$candidato" ]; then
            ARCHIVO="$candidato"
            break
        fi
    done

    if [ -z "$ARCHIVO" ]; then

        fallar G3 \
            "No existe evidencia-vnc.txt en el Escritorio de profe1 (ni evidencia_remota.txt)."

    else

        case "$ARCHIVO" in
            */evidencia_remota.txt)
                TEXTO='^Archivo creado remotamente$'
                ;;
            *)
                TEXTO='^Acceso remoto por VNC'
                ;;
        esac

        if [ ! -r "$ARCHIVO" ]; then
            fallar G3 "No se puede leer $ARCHIVO."
        elif ! grep -Eq "$TEXTO" "$ARCHIVO"; then
            fallar G3 "El archivo $ARCHIVO no contiene el texto esperado."
        fi

        PROPIETARIO=$(stat -c '%U' "$ARCHIVO")

        if [ "$PROPIETARIO" != "profe1" ]; then
            fallar G3 \
                "El archivo pertenece a '$PROPIETARIO' y no a profe1."
        fi

    fi
fi

# ==================================================
# RESULTADOS
# ==================================================

TOTAL=0

echo "========================================="
echo "RESULTADOS - APARTADO G"
echo "========================================="

for indicador in G1 G2 G3; do

    echo "$indicador -> ${ESTADO[$indicador]}"

    if [ "${ESTADO[$indicador]}" = "No" ]; then
        printf '%s' "${ERRORES[$indicador]}"
    else
        TOTAL=$((TOTAL + PUNTOS[$indicador]))
    fi

done

echo "-----------------------------------------"
echo "PUNTUACIÓN: $TOTAL / 8"
echo "========================================="