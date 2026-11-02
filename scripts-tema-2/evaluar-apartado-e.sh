#!/usr/bin/env bash

# ==================================================
# APARTADO E. ADMINISTRACIÓN REMOTA SSH
# TOTAL: 15 PUNTOS
#
# Uso:
# sudo bash evaluar_apartado_e.sh IP_SERVIDOR IP_CLIENTE
#
# Evaluación local en Ubuntu Server.
# No requiere ejecutar comandos en Windows.
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
    [E1]=3
    [E2]=3
    [E3]=3
    [E4]=3
    [E5]=3
)

for i in E1 E2 E3 E4 E5; do
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
# COMPROBACIONES AUXILIARES
# ==================================================

if ! command -v sshd >/dev/null 2>&1 &&
   [ ! -x /usr/sbin/sshd ]; then
    SSHD=""
else
    SSHD=$(command -v sshd 2>/dev/null)
    SSHD="${SSHD:-/usr/sbin/sshd}"
fi

# Verificar que la IP pertenezca al servidor.
IP_LOCAL=0

if ip -o -4 addr show scope global |
   awk -v ip="$IP_SERVIDOR" '
   {
       split($4, direccion, "/")
       if (direccion[1] == ip) encontrado=1
   }
   END {exit !encontrado}
   '; then
    IP_LOCAL=1
fi

# Configuración efectiva para profe1
# considerando la IP del cliente.
obtener_config_ssh() {
    "$SSHD" -T \
        -C "user=profe1,addr=$IP_CLIENTE,host=$IP_CLIENTE" \
        2>/dev/null
}

valor_config() {
    local clave="$1"

    printf '%s\n' "$CONFIG_SSH" |
        awk -v k="$clave" '$1==k {
            $1=""
            sub(/^[[:space:]]+/, "")
            print
            exit
        }'
}

# ==================================================
# E1. INSTALACIÓN Y FUNCIONAMIENTO SSH
# 3 PUNTOS
# ==================================================

if ! dpkg-query -W -f='${Status}' \
     openssh-server 2>/dev/null |
     grep -Fxq 'install ok installed'; then
    fallar E1 "El paquete openssh-server no está instalado."
fi

if [ -z "$SSHD" ]; then
    fallar E1 "No se encontró el ejecutable sshd."
fi

if ! systemctl is-active --quiet ssh; then
    fallar E1 "El servicio ssh no está activo."
fi

if ! systemctl status ssh --no-pager \
     >/dev/null 2>&1; then
    fallar E1 "No se pudo consultar el estado del servicio SSH."
fi

if ! ss -tlnp |
     awk '$1=="LISTEN" && $4 ~ /:22$/ {ok=1}
          END {exit !ok}'; then
    fallar E1 "No existe un servicio escuchando en TCP 22."
fi

# ==================================================
# E2. CONFIGURACIÓN LOCAL DE ACCESO SSH
# 3 PUNTOS
# ==================================================

if [ "$IP_LOCAL" -ne 1 ]; then
    fallar E2 \
        "La IP $IP_SERVIDOR no está asignada al servidor."
fi

if ! id profe1 >/dev/null 2>&1; then
    fallar E2 "El usuario profe1 no existe."
else
    SHELL_PROFE=$(getent passwd profe1 | cut -d: -f7)

    if [ ! -x "$SHELL_PROFE" ]; then
        fallar E2 \
            "El shell de profe1 no existe o no es ejecutable."
    fi

    case "$SHELL_PROFE" in
        */nologin|*/false)
            fallar E2 \
                "profe1 tiene un shell que impide sesiones interactivas."
            ;;
    esac
fi

if [ -z "$SSHD" ]; then
    fallar E2 "No se puede consultar la configuración SSH."
else
    CONFIG_SSH=$(obtener_config_ssh)

    if [ -z "$CONFIG_SSH" ]; then
        fallar E2 \
            "No se pudo obtener la configuración SSH para profe1."
    else
        ALLOW_USERS=$(valor_config allowusers)
        DENY_USERS=$(valor_config denyusers)
        ALLOW_GROUPS=$(valor_config allowgroups)
        DENY_GROUPS=$(valor_config denygroups)

        if [ -n "$ALLOW_USERS" ]; then
            if ! printf '%s\n' "$ALLOW_USERS" |
                 tr ' ' '\n' |
                 grep -Eq '^profe1$|^profe1@'; then
                fallar E2 \
                    "profe1 no figura en AllowUsers."
            fi
        fi

        if printf '%s\n' "$DENY_USERS" |
           tr ' ' '\n' |
           grep -Fxq 'profe1'; then
            fallar E2 "profe1 está restringido por DenyUsers."
        fi

        # Los grupos de acceso se consultan
        # para identificar restricciones.
        if [ -n "$ALLOW_GROUPS" ]; then
            EN_GRUPO=0

            for grupo in $ALLOW_GROUPS; do
                if id -nG profe1 2>/dev/null |
                   tr ' ' '\n' |
                   grep -Fxq "$grupo"; then
                    EN_GRUPO=1
                fi
            done

            if [ "$EN_GRUPO" -ne 1 ]; then
                fallar E2 \
                    "profe1 no pertenece a un grupo permitido por AllowGroups."
            fi
        fi

        for grupo in $DENY_GROUPS; do
            if id -nG profe1 2>/dev/null |
               tr ' ' '\n' |
               grep -Fxq "$grupo"; then
                fallar E2 \
                    "profe1 pertenece al grupo denegado '$grupo'."
            fi
        done
    fi
fi

# ==================================================
# E3. AUTENTICACIÓN POR LLAVES SSH
# 3 PUNTOS
# ==================================================

if [ -z "$SSHD" ]; then
    fallar E3 "No está disponible sshd."
else
    CONFIG_SSH=$(obtener_config_ssh)

    PUBKEY=$(valor_config pubkeyauthentication)

    if [ "$PUBKEY" != "yes" ]; then
        fallar E3 \
            "La autenticación mediante llave pública no está habilitada."
    fi
fi

HOME_PROFE=$(getent passwd profe1 | cut -d: -f6)

if [ -z "$HOME_PROFE" ]; then
    fallar E3 "No se encontró el directorio personal de profe1."
else
    SSH_DIR="$HOME_PROFE/.ssh"
    AUTH_KEYS="$SSH_DIR/authorized_keys"

    if [ ! -d "$SSH_DIR" ]; then
        fallar E3 "No existe $SSH_DIR."
    else
        PERMISOS_DIR=$(stat -c '%a' "$SSH_DIR")

        if (( 8#$PERMISOS_DIR & 022 )); then
            fallar E3 \
                "El directorio .ssh permite escritura de grupo u otros."
        fi
    fi

    if [ ! -f "$AUTH_KEYS" ]; then
        fallar E3 "No existe authorized_keys para profe1."
    else
        if ! grep -Eq \
             '^[[:space:]]*(ssh-ed25519|ssh-rsa|ecdsa-sha2-)' \
             "$AUTH_KEYS"; then
            fallar E3 \
                "authorized_keys no contiene una llave pública reconocida."
        fi

        PERMISOS_KEYS=$(stat -c '%a' "$AUTH_KEYS")

        if (( 8#$PERMISOS_KEYS & 022 )); then
            fallar E3 \
                "authorized_keys tiene permisos de escritura inseguros."
        fi
    fi
fi

# ==================================================
# E4. RESTRICCIONES DE SEGURIDAD SSH
# 3 PUNTOS
#
# Política evaluada:
# - Root sin acceso SSH.
# - Contraseña deshabilitada.
# - Llave pública habilitada.
# - Máximo 3 intentos de autenticación.
# ==================================================

if [ -z "$SSHD" ]; then
    fallar E4 "No está disponible sshd."
else
    CONFIG_SSH=$(obtener_config_ssh)

    ROOT=$(valor_config permitrootlogin)
    PASSWORD=$(valor_config passwordauthentication)
    PUBKEY=$(valor_config pubkeyauthentication)
    MAXTRIES=$(valor_config maxauthtries)

    if [ "$ROOT" != "no" ]; then
        fallar E4 \
            "PermitRootLogin=$ROOT; se requiere no."
    fi

    if [ "$PASSWORD" != "no" ]; then
        fallar E4 \
            "PasswordAuthentication=$PASSWORD; se requiere no."
    fi

    if [ "$PUBKEY" != "yes" ]; then
        fallar E4 \
            "PubkeyAuthentication=$PUBKEY; se requiere yes."
    fi

    if ! [[ "$MAXTRIES" =~ ^[0-9]+$ ]] ||
       [ "$MAXTRIES" -gt 3 ]; then
        fallar E4 \
            "MaxAuthTries=$MAXTRIES; se requiere 3 o menos."
    fi
fi

# ==================================================
# E5. VALIDACIÓN Y REGISTROS SSH
# 3 PUNTOS
# ==================================================

if [ -z "$SSHD" ]; then
    fallar E5 "No se encontró sshd para validar la configuración."
else
    if ! "$SSHD" -t >/dev/null 2>&1; then
        fallar E5 \
            "La configuración SSH contiene errores de sintaxis."
    fi
fi

if ! journalctl -u ssh --since '10 minutes ago' \
     --no-pager >/dev/null 2>&1; then
    fallar E5 \
        "No se pudieron consultar los registros SSH."
fi

# Revisar si existen registros recientes.
REGISTROS=$(journalctl -u ssh \
    --since '10 minutes ago' \
    --no-pager 2>/dev/null)

if ! printf '%s\n' "$REGISTROS" |
     grep -Eq 'Accepted (publickey|password|keyboard-interactive) for profe1'; then
    fallar E5 \
        "No se encontró una autenticación SSH reciente de profe1."
fi

# ==================================================
# RESULTADOS
# ==================================================

TOTAL=0

echo "========================================="
echo "RESULTADOS - APARTADO E"
echo "========================================="

for indicador in E1 E2 E3 E4 E5; do

    echo "$indicador -> ${ESTADO[$indicador]}"

    if [ "${ESTADO[$indicador]}" = "No" ]; then
        printf '%s' "${ERRORES[$indicador]}"
    else
        TOTAL=$((TOTAL + PUNTOS[$indicador]))
    fi
done

echo "-----------------------------------------"
echo "PUNTUACIÓN: $TOTAL / 15"
echo "========================================="