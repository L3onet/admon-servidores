#!/usr/bin/env bash

# ==================================================
# APARTADO C. SEGURIDAD DE ARCHIVOS Y SAMBA
# TOTAL: 22 PUNTOS
#
# Uso:
# sudo bash evaluar_apartado_c.sh IP_SERVIDOR IP_CLIENTE
#
# Requisitos:
# - Samba y smbclient instalados.
# - SSH por llave hacia el cliente.
# - Archivos de credenciales Samba.
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

# Usuario SSH del cliente. Se puede modificar
# mediante la variable SSH_CLIENT_USER.
SSH_CLIENT_USER="${SSH_CLIENT_USER:-${SUDO_USER:-root}}"

# Archivos de credenciales Samba.
# Formato:
# username = profe1
# password = CONTRASENA
CRED_PROFE="/root/.samba-profe1"
CRED_ALUMNO="/root/.samba-alumno1"

# Los mismos archivos deben existir en el cliente.
CRED_CLIENTE_PROFE="/root/.samba-profe1"
CRED_CLIENTE_ALUMNO="/root/.samba-alumno1"

declare -A ESTADO
declare -A PUNTOS
declare -A ERRORES

PUNTOS=(
    [C1]=2
    [C2]=3
    [C3]=4
    [C4]=4
    [C5]=3
    [C6]=3
    [C7]=3
)

for i in C1 C2 C3 C4 C5 C6 C7; do
    ESTADO[$i]="Si"
    ERRORES[$i]=""
done

fallar() {
    local indicador="$1"
    local motivo="$2"

    ESTADO[$indicador]="No"
    ERRORES[$indicador]+="  - $motivo"$'\n'
}

existe_comando() {
    command -v "$1" >/dev/null 2>&1
}

validar_ip() {
    local ip="$1"
    local octeto
    local -a partes

    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

    IFS='.' read -r -a partes <<< "$ip"

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
# C1. INSTALACIÓN Y CONFIGURACIÓN DE SAMBA
# 2 PUNTOS
# ==================================================

if ! existe_comando smbd; then
    fallar C1 "El comando smbd no está instalado."
else
    smbd --version >/dev/null 2>&1 ||
        fallar C1 "No se pudo consultar la versión de Samba."

    smbd -b | grep -q CONFIGFILE ||
        fallar C1 "No se identificó CONFIGFILE."
fi

[ -f /etc/samba/smb.conf ] ||
    fallar C1 "No existe /etc/samba/smb.conf."

[ -r /etc/samba/smb.conf ] ||
    fallar C1 "No se puede leer smb.conf."

# ==================================================
# C2. USUARIOS REGISTRADOS EN SAMBA
# 3 PUNTOS
# ==================================================

if ! existe_comando pdbedit; then
    fallar C2 "El comando pdbedit no está disponible."
else
    USUARIOS_SAMBA=$(pdbedit -L 2>/dev/null)

    if [ "$?" -ne 0 ]; then
        fallar C2 "No se pudo consultar la base de Samba."
    else
        for usuario in profe1 alumno1 alumno2; do
            if ! printf '%s\n' "$USUARIOS_SAMBA" |
                 cut -d: -f1 |
                 grep -Fxq "$usuario"; then
                fallar C2 "Falta el usuario '$usuario' en Samba."
            fi
        done
    fi

    pdbedit -Lv profe1 >/dev/null 2>&1 ||
        fallar C2 "No se pudo consultar profe1 con pdbedit -Lv."
fi

# ==================================================
# C3. RECURSOS COMPARTIDOS Y CONFIGURACIÓN
# 4 PUNTOS
# ==================================================

if ! existe_comando testparm; then
    fallar C3 "testparm no está disponible."
else
    CONFIG=$(testparm -s 2>/dev/null)

    if [ "$?" -ne 0 ]; then
        fallar C3 "La configuración Samba contiene errores."
    else
        for recurso in publico docentes entregas; do
            if ! printf '%s\n' "$CONFIG" |
                 grep -Fxq "[$recurso]"; then
                fallar C3 "No está configurado [$recurso]."
            fi
        done
    fi
fi

if ! existe_comando smbclient; then
    fallar C3 "smbclient no está instalado."
elif [ ! -f "$CRED_PROFE" ]; then
    fallar C3 "Falta el archivo de credenciales de profe1."
else
    LISTADO=$(smbclient -L //localhost \
        -A "$CRED_PROFE" -m SMB3 2>&1)

    if [ "$?" -ne 0 ]; then
        fallar C3 "No se pudieron listar los recursos locales: $LISTADO"
    else
        for recurso in publico docentes entregas; do
            if ! printf '%s\n' "$LISTADO" |
                 awk '$2=="Disk" {print $1}' |
                 grep -Fxq "$recurso"; then
                fallar C3 "El recurso '$recurso' no aparece en smbclient."
            fi
        done
    fi
fi

# ==================================================
# C4. PERMISOS DE DIRECTORIOS COMPARTIDOS
# 4 PUNTOS
# ==================================================

if [ ! -d /srv/samba ]; then
    fallar C4 "No existe el directorio /srv/samba."
else
    for recurso in publico docentes entregas; do
        RUTA="/srv/samba/$recurso"

        if [ ! -d "$RUTA" ]; then
            fallar C4 "No existe el directorio $RUTA."
            continue
        fi

        if ! stat -c '%n %U %G %a %A' \
             "$RUTA" >/dev/null 2>&1; then
            fallar C4 "No se pueden consultar permisos de $RUTA."
            continue
        fi

        # Comprobar propietario y grupo válidos.
        USUARIO_DUENO=$(stat -c '%U' "$RUTA")
        GRUPO_DUENO=$(stat -c '%G' "$RUTA")

        if [ "$USUARIO_DUENO" = "UNKNOWN" ] ||
           [ "$GRUPO_DUENO" = "UNKNOWN" ]; then
            fallar C4 "Propietario o grupo inválido en $RUTA."
        fi

        # Verificar setgid, previsto en este escenario
        # para los directorios compartidos.
        if ! find "$RUTA" -maxdepth 0 \
             -type d -perm -2000 |
             grep -q .; then
            fallar C4 "No está configurado setgid en $RUTA."
        fi
    done
fi

# ==================================================
# C5. FUNCIONAMIENTO DEL SERVICIO SAMBA
# 3 PUNTOS
# ==================================================

if ! systemctl is-active --quiet smbd; then
    fallar C5 "El servicio smbd no está activo."
fi

if ! systemctl status smbd --no-pager \
     >/dev/null 2>&1; then
    fallar C5 "No se pudo consultar correctamente smbd."
fi

if ! ss -tlnp |
     awk '$1=="LISTEN" && $4 ~ /:445$/ {ok=1}
          END {exit !ok}'; then
    fallar C5 "El puerto TCP 445 no está escuchando."
fi

# ==================================================
# PRUEBAS DESDE EL CLIENTE
# C6 Y C7
# ==================================================

# Se requiere SSH por llave, sin contraseña interactiva.
SSH_OPTS=(
    -o BatchMode=yes
    -o ConnectTimeout=5
    -o StrictHostKeyChecking=yes
)

CLIENTE_DISPONIBLE=1

if ! ssh "${SSH_OPTS[@]}" \
    "${SSH_CLIENT_USER}@${IP_CLIENTE}" \
    'command -v smbclient >/dev/null' \
    >/dev/null 2>&1; then

    CLIENTE_DISPONIBLE=0

    fallar C6 "No se pudo acceder al cliente por SSH o falta smbclient."
    fallar C7 "No se pudo ejecutar la prueba desde el cliente."
fi

# Comprobación de credenciales en el cliente.
if [ "$CLIENTE_DISPONIBLE" -eq 1 ]; then

    if ! ssh "${SSH_OPTS[@]}" \
         "${SSH_CLIENT_USER}@${IP_CLIENTE}" \
         "sudo -n test -r '$CRED_CLIENTE_PROFE' &&
          sudo -n test -r '$CRED_CLIENTE_ALUMNO'" \
         >/dev/null 2>&1; then

        CLIENTE_DISPONIBLE=0

        fallar C6 "Faltan credenciales Samba en el cliente o sudo sin contraseña."
        fallar C7 "No se pueden consultar credenciales en el cliente."
    fi
fi

# ==================================================
# C6. ACCESO AUTORIZADO
# 3 PUNTOS
# ==================================================

if [ "$CLIENTE_DISPONIBLE" -eq 1 ]; then

    SALIDA_C6=$(ssh "${SSH_OPTS[@]}" \
        "${SSH_CLIENT_USER}@${IP_CLIENTE}" \
        "sudo -n bash -s -- '$IP_SERVIDOR' '$CRED_CLIENTE_PROFE' '$CRED_CLIENTE_ALUMNO'" \
        <<'REMOTO_C6'
IP="$1"
CRED_PROFE="$2"
CRED_ALUMNO="$3"

FALLOS=0

if ! smbclient "//$IP/publico" \
     -A "$CRED_PROFE" -c 'ls' \
     >/dev/null 2>&1; then
    echo "No se puede listar publico como profe1."
    FALLOS=1
fi

ARCHIVO=$(mktemp /tmp/prueba_samba.XXXXXX) || exit 1
NOMBRE=$(basename "$ARCHIVO")

printf 'Prueba Samba\n' > "$ARCHIVO"

SALIDA=$(smbclient "//$IP/entregas" \
    -A "$CRED_ALUMNO" \
    -c "put $ARCHIVO $NOMBRE" 2>&1)

if [ "$?" -ne 0 ]; then
    echo "No se puede subir a entregas como alumno1."
    echo "$SALIDA"
    FALLOS=1
else
    # Limpiar el archivo de prueba del recurso.
    smbclient "//$IP/entregas" \
        -A "$CRED_ALUMNO" \
        -c "del $NOMBRE" >/dev/null 2>&1
fi

rm -f "$ARCHIVO"
exit "$FALLOS"
REMOTO_C6
    )

    if [ "$?" -ne 0 ]; then
        fallar C6 "Falló una prueba autorizada: $SALIDA_C6"
    fi
fi

# ==================================================
# C7. ACCESO DENEGADO A RECURSO RESTRINGIDO
# 3 PUNTOS
# ==================================================

if [ "$CLIENTE_DISPONIBLE" -eq 1 ]; then

    SALIDA_C7=$(ssh "${SSH_OPTS[@]}" \
        "${SSH_CLIENT_USER}@${IP_CLIENTE}" \
        "sudo -n bash -s -- '$IP_SERVIDOR' '$CRED_CLIENTE_ALUMNO'" \
        <<'REMOTO_C7'
IP="$1"
CRED="$2"

# Primero comprobar que las credenciales de
# alumno1 son válidas en un recurso permitido.
if ! smbclient "//$IP/publico" \
     -A "$CRED" -c 'ls' \
     >/dev/null 2>&1; then
    echo "No se pudo autenticar alumno1 en publico."
    exit 2
fi

# Intentar acceso al recurso restringido.
SALIDA=$(smbclient "//$IP/docentes" \
    -A "$CRED" -c 'ls' 2>&1)

CODIGO=$?

if [ "$CODIGO" -eq 0 ]; then
    echo "alumno1 pudo listar el recurso docentes."
    exit 1
fi

if printf '%s\n' "$SALIDA" |
   grep -q 'NT_STATUS_ACCESS_DENIED'; then
    exit 0
fi

echo "La conexión falló por un motivo no confirmado:"
echo "$SALIDA"
exit 3
REMOTO_C7
    )

    if [ "$?" -ne 0 ]; then
        fallar C7 "No se comprobó una denegación válida: $SALIDA_C7"
    fi
fi

# ==================================================
# RESULTADOS
# ==================================================

TOTAL=0

echo "========================================="
echo "RESULTADOS - APARTADO C"
echo "========================================="

for indicador in C1 C2 C3 C4 C5 C6 C7; do

    echo "$indicador -> ${ESTADO[$indicador]}"

    if [ "${ESTADO[$indicador]}" = "No" ]; then
        printf '%s' "${ERRORES[$indicador]}"
    else
        TOTAL=$((TOTAL + PUNTOS[$indicador]))
    fi

done

echo "-----------------------------------------"
echo "PUNTUACIÓN: $TOTAL / 22"
echo "========================================="