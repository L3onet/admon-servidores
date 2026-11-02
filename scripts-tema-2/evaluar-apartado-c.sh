#!/usr/bin/env bash

# ==================================================
# APARTADO C. SEGURIDAD DE ARCHIVOS Y SAMBA
# TOTAL: 22 PUNTOS
#
# Uso:
# sudo bash evaluar_apartado_c.sh IP_SERVIDOR IP_CLIENTE
#
# Todas las pruebas se ejecutan en el propio servidor
# (smbclient contra IP_SERVIDOR); no hace falta SSH ni
# un cliente Linux. IP_CLIENTE solo se valida.
#
# Contraseñas Samba de profe1 y alumno1, en este orden:
#   1) archivo /root/.samba-profe1 y /root/.samba-alumno1
#      (formato: username = profe1 / password = CLAVE);
#   2) variables SMB_PASS_PROFE1 y SMB_PASS_ALUMNO1;
#   3) se piden por teclado (sin mostrarlas).
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

# Credenciales Samba temporales (se borran al terminar).
TMP_CRED=$(mktemp -d /tmp/eval-samba.XXXXXX) || exit 1
chmod 700 "$TMP_CRED"
trap 'rm -rf "$TMP_CRED"' EXIT

CRED_PROFE=""
CRED_ALUMNO=""

# Prepara un archivo de credenciales para $1 y deja su ruta en $2.
preparar_credenciales() {
    local usuario="$1"
    local destino="$2"
    local archivo="/root/.samba-$usuario"
    local variable="SMB_PASS_${usuario^^}"
    local clave="${!variable:-}"
    local temporal="$TMP_CRED/$usuario"

    if [ -r "$archivo" ]; then
        printf -v "$destino" '%s' "$archivo"
        return 0
    fi

    if [ -z "$clave" ] && [ -t 0 ]; then
        read -rs -p "Contraseña Samba de $usuario: " clave
        echo
    fi

    [ -n "$clave" ] || return 1

    printf 'username = %s\npassword = %s\n' "$usuario" "$clave" > "$temporal"
    chmod 600 "$temporal"
    printf -v "$destino" '%s' "$temporal"
}

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

preparar_credenciales profe1 CRED_PROFE || CRED_PROFE=""
preparar_credenciales alumno1 CRED_ALUMNO || CRED_ALUMNO=""

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
elif [ -z "$CRED_PROFE" ]; then
    fallar C3 "No se obtuvo la contraseña Samba de profe1."
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
# C6. ACCESO AUTORIZADO
# 3 PUNTOS
#
# profe1 lista "publico" y alumno1 sube un archivo
# a "entregas" (se borra al terminar).
# ==================================================

if ! existe_comando smbclient; then
    fallar C6 "smbclient no está instalado."
elif [ -z "$CRED_PROFE" ] || [ -z "$CRED_ALUMNO" ]; then
    fallar C6 "Faltan las contraseñas Samba de profe1 o alumno1."
else

    if ! smbclient "//$IP_SERVIDOR/publico" \
         -A "$CRED_PROFE" -m SMB3 -c 'ls' \
         >/dev/null 2>&1; then
        fallar C6 "profe1 no puede listar el recurso publico."
    fi

    ARCHIVO_PRUEBA="$TMP_CRED/prueba_samba.txt"
    NOMBRE_PRUEBA="prueba_eval_$$.txt"
    printf 'Prueba Samba\n' > "$ARCHIVO_PRUEBA"

    SALIDA=$(smbclient "//$IP_SERVIDOR/entregas" \
        -A "$CRED_ALUMNO" -m SMB3 \
        -c "put $ARCHIVO_PRUEBA $NOMBRE_PRUEBA" 2>&1)

    if [ "$?" -ne 0 ]; then
        fallar C6 "alumno1 no puede subir a entregas: $SALIDA"
    else
        smbclient "//$IP_SERVIDOR/entregas" \
            -A "$CRED_ALUMNO" -m SMB3 \
            -c "del $NOMBRE_PRUEBA" >/dev/null 2>&1
    fi
fi

# ==================================================
# C7. ACCESO DENEGADO A RECURSO RESTRINGIDO
# 3 PUNTOS
# ==================================================

if ! existe_comando smbclient; then
    fallar C7 "smbclient no está instalado."
elif [ -z "$CRED_ALUMNO" ]; then
    fallar C7 "Falta la contraseña Samba de alumno1."
else

    # Las credenciales deben ser válidas en un recurso permitido.
    if ! smbclient "//$IP_SERVIDOR/publico" \
         -A "$CRED_ALUMNO" -m SMB3 -c 'ls' \
         >/dev/null 2>&1; then
        fallar C7 "alumno1 no se pudo autenticar en publico."
    else
        SALIDA=$(smbclient "//$IP_SERVIDOR/docentes" \
            -A "$CRED_ALUMNO" -m SMB3 -c 'ls' 2>&1)

        if [ "$?" -eq 0 ]; then
            fallar C7 "alumno1 pudo listar el recurso docentes."
        elif ! printf '%s\n' "$SALIDA" |
             grep -q 'NT_STATUS_ACCESS_DENIED'; then
            fallar C7 "El acceso falló por un motivo no confirmado: $SALIDA"
        fi
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