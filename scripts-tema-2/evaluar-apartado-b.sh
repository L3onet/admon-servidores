#!/usr/bin/env bash

# ==========================================
# APARTADO B. ADMINISTRACIÓN DE USUARIOS
# Y GRUPOS - TOTAL: 10 PUNTOS
# ==========================================
# No recibe parámetros.
# Ejecutar con sudo.

B1="Si"
B2="Si"
B3="Si"

declare -a ERRORES_B1
declare -a ERRORES_B2
declare -a ERRORES_B3

# ==========================================
# B1. EXISTENCIA DE USUARIOS Y GRUPOS
# 4 PUNTOS
# ==========================================

for grupo in docentes alumnos; do
    if ! getent group "$grupo" >/dev/null 2>&1; then
        B1="No"
        ERRORES_B1+=("No existe el grupo '$grupo'.")
    fi
done

for usuario in profe1 alumno1 alumno2; do

    if ! getent passwd "$usuario" >/dev/null 2>&1; then
        B1="No"
        ERRORES_B1+=("No existe el usuario '$usuario'.")
    elif ! id "$usuario" >/dev/null 2>&1; then
        B1="No"
        ERRORES_B1+=(
            "No se puede obtener el ID de '$usuario'."
        )
    fi

done

# ==========================================
# B2. PERTENENCIA DE USUARIOS A GRUPOS
# 3 PUNTOS
# ==========================================

verificar_grupo() {
    local usuario="$1"
    local grupo="$2"

    if ! getent passwd "$usuario" >/dev/null 2>&1; then
        B2="No"
        ERRORES_B2+=(
            "No se puede evaluar '$usuario': no existe."
        )
        return
    fi

    if ! getent group "$grupo" >/dev/null 2>&1; then
        B2="No"
        ERRORES_B2+=(
            "No se puede evaluar '$grupo': no existe."
        )
        return
    fi

    if ! id -nG "$usuario" |
         grep -Fxq "$grupo"; then

        # id -nG devuelve todos los grupos en
        # una línea separados por espacios.
        # Usamos una lista separada por líneas.
        if ! id -nG "$usuario" |
             tr ' ' '\n' |
             grep -Fxq "$grupo"; then

            B2="No"
            ERRORES_B2+=(
                "El usuario '$usuario' no pertenece al grupo '$grupo'."
            )
        fi
    fi
}

verificar_grupo profe1 docentes
verificar_grupo alumno1 alumnos
verificar_grupo alumno2 alumnos

# ==========================================
# B3. RESTRICCIONES DE ACCESO
# 3 PUNTOS
# ==========================================

if [ "$EUID" -ne 0 ]; then
    B3="No"
    ERRORES_B3+=(
        "Ejecute el script con sudo para verificar privilegios."
    )
else

    for usuario in alumno1 alumno2; do

        if ! getent passwd "$usuario" >/dev/null 2>&1; then
            B3="No"
            ERRORES_B3+=(
                "El usuario '$usuario' no existe."
            )
            continue
        fi

        SHELL_USUARIO=$(
            getent passwd "$usuario" | cut -d: -f7
        )

        if [ "$SHELL_USUARIO" != "/usr/sbin/nologin" ]; then
            B3="No"
            ERRORES_B3+=(
                "El usuario '$usuario' tiene shell '$SHELL_USUARIO'; se esperaba '/usr/sbin/nologin'."
            )
        fi

        # Comprobar privilegios sudo mediante
        # código de salida de sudo -l -U.
        # Los mensajes no dependen del idioma.

        if sudo -n -l -U "$usuario" \
           >/dev/null 2>&1; then

            B3="No"
            ERRORES_B3+=(
                "El usuario '$usuario' tiene permisos sudo."
            )
        fi

    done

fi

# ==========================================
# RESULTADOS
# ==========================================

mostrar_resultado() {
    local indicador="$1"
    local estado="$2"
    local puntos="$3"
    shift 3

    echo "$indicador -> $estado"

    if [ "$estado" = "No" ]; then
        for error in "$@"; do
            echo "  - $error"
        done
    fi
}

echo "========================================="
echo "RESULTADOS - APARTADO B"
echo "========================================="

mostrar_resultado "B1" "$B1" 4 "${ERRORES_B1[@]}"
mostrar_resultado "B2" "$B2" 3 "${ERRORES_B2[@]}"
mostrar_resultado "B3" "$B3" 3 "${ERRORES_B3[@]}"

# ==========================================
# CALIFICACIÓN
# ==========================================

TOTAL=0

[ "$B1" = "Si" ] && ((TOTAL+=4))
[ "$B2" = "Si" ] && ((TOTAL+=3))
[ "$B3" = "Si" ] && ((TOTAL+=3))

echo "-----------------------------------------"
echo "PUNTUACIÓN: $TOTAL / 10"
echo "========================================="