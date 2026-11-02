#!/usr/bin/env bash
# Recolector de evidencias - Servidor DHCP Kea (Ubuntu 26.04.1 LTS, Kea 3.0)
# Uso: sudo ./recolectar_evidencias.sh <interfaz> "<Nombre del alumno>"

set -uo pipefail

IFACE="${1:-enp0s9}"
ALUMNO="${2:-Sin nombre}"
FECHA="$(date +%Y%m%d_%H%M%S)"
DIR="evidencias_dhcp_${FECHA}"
SOCK="/run/kea/kea4-ctrl-socket"
CONF="/etc/kea/kea-dhcp4.conf"
LEASES="/var/lib/kea/kea-leases4.csv"

if [[ $EUID -ne 0 ]]; then
  echo "Ejecuta con sudo." >&2
  exit 1
fi

mkdir -p "$DIR"

# Ejecuta un comando, guarda la salida en un archivo con encabezado y la muestra en pantalla.
ev() {
  local archivo="$1"; shift
  {
    echo "=================================================="
    echo " Evidencia : $archivo"
    echo " Alumno    : $ALUMNO"
    echo " Host      : $(hostname)"
    echo " Fecha     : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo " Comando   : $*"
    echo "=================================================="
    bash -c "$*" 2>&1
    echo
  } | tee "$DIR/$archivo"
}

ev 01_sistema.txt          "cat /etc/os-release; uname -a; hostnamectl"
ev 02_red_servidor.txt     "ip -br addr; ip route; cat /etc/netplan/*.yaml"
ev 03_paquete.txt          "kea-dhcp4 -V; dpkg -l | grep -i kea"
ev 04_validacion_conf.txt  "kea-dhcp4 -t $CONF && echo 'RESULTADO: configuracion valida'"
ev 05_configuracion.txt    "cat $CONF"
ev 06_servicio.txt         "systemctl is-enabled kea-dhcp4-server; systemctl status kea-dhcp4-server --no-pager"
ev 07_puerto_67.txt        "ss -ulnp | grep ':67'"
ev 08_api_status.txt       "echo '{ \"command\": \"status-get\" }' | socat - UNIX-CONNECT:$SOCK"
ev 09_leases.txt           "column -s, -t $LEASES"
ev 10_logs_journal.txt     "journalctl -u kea-dhcp4-server --since '2 hours ago' --no-pager"
ev 11_logs_asignaciones.txt "grep -E 'DHCP4_LEASE_ALLOC|DHCP4_RESERVED|DHCP4_PACKET_SEND' /var/log/kea/kea-dhcp4.log | tail -n 100"
ev 12_firewall.txt         "ufw status verbose || echo 'UFW no instalado'"

# Captura DORA de 60 s: renueva la IP en el cliente mientras corre.
echo ">>> Capturando tráfico DHCP durante 60 s en $IFACE. Renueva la IP en el cliente AHORA..."
timeout 60 tcpdump -i "$IFACE" -n 'udp port 67 or udp port 68' -w "$DIR/13_dhcp_dora.pcap" 2>/dev/null
ev 13_dhcp_dora_resumen.txt "tcpdump -n -vv -r $DIR/13_dhcp_dora.pcap 2>/dev/null | grep -E 'DHCP-Message|Your-IP|Client-Ethernet|Requested-IP'"

# Integridad y empaquetado
( cd "$DIR" && sha256sum * > SHA256SUMS.txt )
tar -czf "${DIR}.tar.gz" "$DIR"
sha256sum "${DIR}.tar.gz" | tee "${DIR}.tar.gz.sha256"

echo
echo "✅ Evidencias generadas en: $DIR/"
echo "✅ Paquete: ${DIR}.tar.gz"
