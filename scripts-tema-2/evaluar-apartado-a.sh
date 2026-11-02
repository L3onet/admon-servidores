#!/usr/bin/env bash

# ==========================================
# APARTADO A. PREPARACIÓN Y CONECTIVIDAD
# TOTAL: 5 PUNTOS
#
# Uso:
# bash evaluar_apartado_a.sh IP_SERVIDOR IP_CLIENTE
# ==========================================

if [ "$#" -ne 2 ]; then
    echo "Uso: bash $0 ip_servidor ip_cliente"
    exit 1
fi

IP_SERVIDOR="$1"
IP_CLIENTE="$2"

A1="Si"
A2="Si"

declare -a ERRORES_A1=()
declare -a ERRORES_A2=()

# ==========================================
# VALIDACIÓN DE DIRECCIONES IPv4
# ==========================================

validar_ip() {
    local ip="$1"
    local octeto
    local -a octetos

    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] ||
        return 1

    IFS='.' read -r -a octetos <<< "$ip"

    for octeto in "${octetos[@]}"; do
        (( 10#$octeto <= 255 )) || return 1
    done

    return 0
}

if ! validar_ip "$IP_SERVIDOR"; then
    echo "Error: IP del servidor no válida: $IP_SERVIDOR"
    exit 1
fi

if ! validar_ip "$IP_CLIENTE"; then
    echo "Error: IP del cliente no válida: $IP_CLIENTE"
    exit 1
fi

# ==========================================
# FUNCIÓN PARA REGISTRAR ERRORES
# ==========================================

fallar_a1() {
    A1="No"
    ERRORES_A1+=("$1")
}

fallar_a2() {
    A2="No"
    ERRORES_A2+=("$1")
}

# ==========================================
# A1. IDENTIFICACIÓN DE RED
# 3 PUNTOS
# ==========================================

# Comprobar hostnamectl
if ! hostnamectl >/dev/null 2>&1; then
    fallar_a1 "No se pudo consultar la información del servidor mediante hostnamectl."
fi

# Comprobar interfaces de red
if ! ip -br link >/dev/null 2>&1; then
    fallar_a1 "No se pudieron consultar las interfaces de red."
fi

# Comprobar IPv4 global configurada
if ! ip -br -4 addr show scope global |
     grep -q .; then

    fallar_a1 "No se encontró ninguna dirección IPv4 global configurada."
fi

# Comprobar la IP proporcionada
if ! ip -o -4 addr show scope global |
     awk -v ip="$IP_SERVIDOR" '
        {
            split($4, direccion, "/")
            if (direccion[1] == ip)
                encontrado=1
        }
        END {exit !encontrado}
     '; then

    fallar_a1 "La IP $IP_SERVIDOR no está configurada en ninguna interfaz del servidor."
fi

# Comprobar rutas de red
if ! ip -4 route show | grep -q .; then
    fallar_a1 "No existen rutas IPv4 configuradas en el servidor."
fi

# ==========================================
# A2. COMPROBACIÓN DE CONECTIVIDAD
# 2 PUNTOS
# ==========================================

# Identificar puerta de enlace predeterminada
GATEWAY=$(
    ip -4 route show default |
    awk '/default via/ {print $3; exit}'
)

if [ -z "$GATEWAY" ]; then

    fallar_a2 "No existe una puerta de enlace predeterminada configurada."

else

    # Comprobar conectividad con gateway
    if ! ping -n -c 4 -W 2 "$GATEWAY" \
         >/dev/null 2>&1; then

        fallar_a2 "No existe respuesta ICMP desde el gateway $GATEWAY."
    fi

fi

# Comprobar conectividad con cliente
if ! ping -n -c 4 -W 2 "$IP_CLIENTE" \
     >/dev/null 2>&1; then

    fallar_a2 "No existe respuesta ICMP desde el cliente $IP_CLIENTE."
fi

# Comprobar conectividad con Internet
if ! ping -n -c 4 -W 2 1.1.1.1 \
     >/dev/null 2>&1; then

    fallar_a2 "No existe respuesta ICMP desde Internet (1.1.1.1)."
fi

# ==========================================
# MOSTRAR RESULTADOS
# ==========================================

mostrar_resultado() {
    local indicador="$1"
    local estado="$2"
    shift 2

    echo "$indicador -> $estado"

    if [ "$estado" = "No" ]; then
        for error in "$@"; do
            echo "  - $error"
        done
    fi
}

echo "========================================="
echo "RESULTADOS - APARTADO A"
echo "========================================="

mostrar_resultado "A1" "$A1" "${ERRORES_A1[@]}"
mostrar_resultado "A2" "$A2" "${ERRORES_A2[@]}"

# ==========================================
# CALIFICACIÓN
# ==========================================

TOTAL=0

if [ "$A1" = "Si" ]; then
    TOTAL=$((TOTAL + 3))
fi

if [ "$A2" = "Si" ]; then
    TOTAL=$((TOTAL + 2))
fi

echo "-----------------------------------------"
echo "PUNTUACIÓN: $TOTAL / 5"
echo "========================================="