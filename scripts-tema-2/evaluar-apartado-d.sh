#!/usr/bin/env bash

# ==================================================
# APARTADO D. PROTECCIÓN MEDIANTE UFW
# TOTAL: 14 PUNTOS
#
# Uso:
# sudo bash evaluar_apartado_d.sh IP_SERVIDOR IP_CLIENTE
#
# IP_CLIENTE = Windows autorizado
#
# D3 y D4 comprueban políticas de UFW.
# Las conexiones reales requieren pruebas
# desde equipos Windows.
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
    [D1]=3
    [D2]=4
    [D3]=3
    [D4]=4
)

for i in D1 D2 D3 D4; do
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

for cmd in ufw ss awk grep systemctl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: falta el comando $cmd."
        exit 1
    fi
done

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

# Obtener estado y reglas.
UFW_VERBOSE=$(ufw status verbose 2>&1)
UFW_NUMBERED=$(ufw status numbered 2>&1)

# ==================================================
# FUNCIONES PARA EXAMINAR LAS REGLAS UFW
# ==================================================

# Evalúa reglas simples IPv4 de puerto individual.
# Una regla de perfil, rango, interfaz o subred
# requiere revisión y se trata conservadoramente.

reglas_puerto() {
    local puerto="$1"

    printf '%s\n' "$UFW_NUMBERED" |
        sed -E 's/^\[[[:space:]]*[0-9]+\][[:space:]]*//' |
        awk -v p="$puerto" '
        $0 ~ /[[:space:]](ALLOW|DENY|REJECT) IN[[:space:]]/ {
            destino=$0
            sub(/[[:space:]]+(ALLOW|DENY|REJECT) IN.*/, "", destino)

            if (destino == p "/tcp" || destino == p)
                print $0
        }'
}

# Extraer acción y origen de una regla simple.
regla_accion() {
    printf '%s\n' "$1" |
        sed -nE 's/^.*[[:space:]](ALLOW|DENY|REJECT) IN[[:space:]].*$/\1/p'
}

regla_origen() {
    printf '%s\n' "$1" |
        sed -E 's/^.*[[:space:]](ALLOW|DENY|REJECT) IN[[:space:]]+//' |
        sed -E 's/[[:space:]]*#.*$//; s/[[:space:]]+$//'
}

# Detecta permisos para un puerto desde cualquier origen
# que no sea el cliente o una red (/16 a /32) que lo contenga.
# Esto incluye reglas amplias no reconocidas,
# que impiden certificar automáticamente
# la política como segura.

permiso_inseguro() {
    local puerto="$1"
    local linea accion origen

    while IFS= read -r linea; do
        [ -z "$linea" ] && continue

        accion=$(regla_accion "$linea")
        origen=$(regla_origen "$linea")

        if [ "$accion" = "ALLOW" ] &&
           ! origen_autoriza_cliente "$origen"; then
            return 0
        fi
    done < <(reglas_puerto "$puerto")

    # Reglas complejas que podrían abrir el puerto.
    # Revisar permisos amplios de cualquier puerto.
    if printf '%s\n' "$UFW_NUMBERED" |
       grep -Eq 'Anywhere[[:space:]]+ALLOW IN[[:space:]]+Anywhere'; then
        return 0
    fi

    return 1
}

# Comprobar permiso específico del cliente.
permiso_cliente() {
    local puerto="$1"
    local linea accion origen

    while IFS= read -r linea; do
        [ -z "$linea" ] && continue

        accion=$(regla_accion "$linea")
        origen=$(regla_origen "$linea")

        if [ "$accion" = "ALLOW" ] &&
           origen_autoriza_cliente "$origen"; then
            return 0
        fi
    done < <(reglas_puerto "$puerto")

    return 1
}

puerto_escuchando() {
    local puerto="$1"

    ss -tln |
        awk -v p="$puerto" '
        $1=="LISTEN" && $4 ~ ":" p "$" {
            encontrado=1
        }
        END {exit !encontrado}'
}

# ==================================================
# D1. ESTADO Y REGLAS DEL FIREWALL
# 3 PUNTOS
# ==================================================

if ! printf '%s\n' "$UFW_VERBOSE" |
     grep -q '^Status: active'; then
    fallar D1 "El firewall UFW no está activo."
fi

if ! printf '%s\n' "$UFW_NUMBERED" |
     grep -Eq '^\[[[:space:]]*[0-9]+\]'; then
    fallar D1 "No se encontraron reglas numeradas en UFW."
fi

if ! printf '%s\n' "$UFW_VERBOSE" |
     grep -q '^Default:'; then
    fallar D1 "No se pudo consultar la política predeterminada."
fi

# ==================================================
# D2. REGLAS Y ORÍGENES AUTORIZADOS
# 4 PUNTOS
# ==================================================

if ! printf '%s\n' "$UFW_VERBOSE" |
     grep -q '^Status: active'; then
    fallar D2 "UFW está inactivo."
fi

if ! printf '%s\n' "$UFW_VERBOSE" |
     grep -Eq '^Default: deny \(incoming\)'; then
    fallar D2 "La política de entrada no es deny."
fi

for puerto in 22 445; do

    if ! permiso_cliente "$puerto"; then
        fallar D2 \
            "No existe ALLOW IN para $puerto/tcp desde $IP_CLIENTE."
    fi

    if permiso_inseguro "$puerto"; then
        fallar D2 \
            "Existe una regla amplia o no autorizada para $puerto/tcp."
    fi

    if ! puerto_escuchando "$puerto"; then
        fallar D2 \
            "No hay un servicio escuchando en TCP $puerto."
    fi
done

# ==================================================
# D3. CONEXIÓN PERMITIDA (POLÍTICA)
# 3 PUNTOS
#
# El cliente Windows debe poder acceder
# por TCP 22 y TCP 445.
# ==================================================

for puerto in 22 445; do

    if ! permiso_cliente "$puerto"; then
        fallar D3 \
            "UFW no autoriza al cliente $IP_CLIENTE en TCP $puerto."
    fi

    if ! puerto_escuchando "$puerto"; then
        fallar D3 \
            "El servicio TCP $puerto no está escuchando."
    fi

done

# Verificar SSH.
if ! systemctl is-active --quiet ssh; then
    fallar D3 "El servicio SSH no está activo."
fi

# Verificar Samba.
if ! systemctl is-active --quiet smbd; then
    fallar D3 "El servicio Samba no está activo."
fi

# ==================================================
# D4. CONEXIÓN BLOQUEADA (POLÍTICA)
# 4 PUNTOS
#
# Comprobar que SSH y VNC no admitan
# conexiones indiscriminadas.
# ==================================================

if ! printf '%s\n' "$UFW_VERBOSE" |
     grep -Eq '^Default: deny \(incoming\)'; then
    fallar D4 \
        "La política de entrada no bloquea por defecto."
fi

for puerto in 22 445 5901; do

    if permiso_inseguro "$puerto"; then
        fallar D4 \
            "Existe ALLOW IN desde un origen no autorizado para TCP $puerto."
    fi

done

# Comprobar si existen registros UFW BLOCK.
# No se utiliza como requisito obligatorio,
# porque puede no haberse generado tráfico
# bloqueado durante la evaluación.
if ! journalctl -k --no-pager 2>/dev/null |
     grep -q 'UFW BLOCK'; then
    AVISO_LOG="No se encontraron registros UFW BLOCK; debe comprobarse el bloqueo desde otro cliente Windows."
else
    AVISO_LOG=""
fi

# ==================================================
# RESULTADOS
# ==================================================

TOTAL=0

echo "========================================="
echo "RESULTADOS - APARTADO D"
echo "========================================="

for indicador in D1 D2 D3 D4; do

    echo "$indicador -> ${ESTADO[$indicador]}"

    if [ "${ESTADO[$indicador]}" = "No" ]; then
        printf '%s' "${ERRORES[$indicador]}"
    else
        TOTAL=$((TOTAL + PUNTOS[$indicador]))
    fi

done

echo "-----------------------------------------"
echo "PUNTUACIÓN DE POLÍTICAS: $TOTAL / 14"
echo "========================================="

if [ -n "$AVISO_LOG" ]; then
    echo "AVISO: $AVISO_LOG"
fi

echo
echo "IMPORTANTE:"
echo "D3 y D4 representan comprobaciones de políticas."
echo "Para validar conexiones reales, ejecute las"
echo "pruebas PowerShell indicadas desde Windows."

