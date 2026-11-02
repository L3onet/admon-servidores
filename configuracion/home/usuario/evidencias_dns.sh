#!/usr/bin/env bash
# Recolector de evidencias - Servidor DNS BIND 9 (Ubuntu 26.04.1 LTS)
# Uso: sudo ./evidencias_dns.sh <dominio> <octeto> "<Nombre del alumno>"

set -uo pipefail

DOMINIO="${1:-leonel.mx}"
OCT="${2:-50}"
ALUMNO="${3:-Sin nombre}"
IFACE="${IFACE:-enp0s9}"
IP="192.168.${OCT}.1"
INV="${OCT}.168.192.in-addr.arpa"
FECHA="$(date +%Y%m%d_%H%M%S)"
DIR="evidencias_dns_${FECHA}"

if [[ $EUID -ne 0 ]]; then
  echo "Ejecuta con sudo." >&2
  exit 1
fi

mkdir -p "$DIR"

# Ejecuta un comando, guarda la salida con encabezado y la muestra en pantalla.
ev() {
  local archivo="$1"; shift
  {
    echo "=================================================="
    echo " Evidencia : $archivo"
    echo " Alumno    : $ALUMNO"
    echo " Dominio   : $DOMINIO"
    echo " Host      : $(hostname)"
    echo " Fecha     : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo " Comando   : $*"
    echo "=================================================="
    bash -c "$*" 2>&1
    echo
  } | tee "$DIR/$archivo"
}

rndc querylog on >/dev/null 2>&1

ev 01_sistema.txt           "cat /etc/os-release; uname -a; hostnamectl"
ev 02_red.txt               "ip -br addr; ip route; resolvectl status"
ev 03_paquetes.txt          "named -v; dpkg -l | grep -E 'bind9|kea'"
ev 04_validacion.txt        "named-checkconf -z && echo 'RESULTADO: configuracion valida'"
ev 05_configuracion.txt     "cat /etc/bind/named.conf.options /etc/bind/named.conf.local"
ev 06_zonas.txt             "cat /var/lib/bind/db.${DOMINIO} /var/lib/bind/db.${INV}"
ev 07_servicio.txt          "systemctl is-enabled named; systemctl status named --no-pager; rndc status"
ev 08_puerto_53.txt         "ss -tulnp | grep ':53 '"
ev 09_consultas_directas.txt "for r in ns1 srv-dhcp www ftp mail cliente-fijo; do dig @${IP} \${r}.${DOMINIO} +noall +answer; done"
ev 10_soa_ns_mx.txt         "dig @${IP} ${DOMINIO} SOA +noall +answer; dig @${IP} ${DOMINIO} NS +noall +answer; dig @${IP} ${DOMINIO} MX +noall +answer"
ev 11_consultas_inversas.txt "dig @${IP} -x ${IP} +noall +answer; dig @${IP} -x 192.168.${OCT}.50 +noall +answer"
ev 12_seguridad.txt         "dig @${IP} ${DOMINIO} AXFR; dig @${IP} version.bind CH TXT +short; dig @${IP} google.com +time=2 +tries=1 | grep status"
ev 13_kea_opciones_dns.txt  "grep -nE 'domain-name-servers|domain-name|domain-search' /etc/kea/kea-dhcp4.conf"

echo ">>> Capturando tráfico DNS durante 60 s en $IFACE. Haz consultas desde el cliente AHORA..."
timeout 60 tcpdump -i "$IFACE" -n 'port 53' -w "$DIR/14_dns.pcap" 2>/dev/null
ev 14_dns_resumen.txt       "tcpdump -n -r $DIR/14_dns.pcap 2>/dev/null | head -n 60"
ev 15_registro_consultas.txt "journalctl -u named --since '2 hours ago' --no-pager | grep -E 'query:|loaded serial' | tail -n 100"

# Integridad y empaquetado
( cd "$DIR" && sha256sum * > SHA256SUMS.txt )
tar -czf "${DIR}.tar.gz" "$DIR"
sha256sum "${DIR}.tar.gz" | tee "${DIR}.tar.gz.sha256"

echo
echo "✅ Evidencias generadas en: $DIR/"
echo "✅ Paquete: ${DIR}.tar.gz"
