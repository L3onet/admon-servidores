#!/usr/bin/env bash
# Recolector de evidencias - Servidor Web Nginx + PHP 8.5 + MySQL 8.4 (Ubuntu 26.04.1 LTS)
# Uso: sudo ./evidencias_web.sh <dominio> <octeto> "<Nombre del alumno>"

set -uo pipefail

DOMINIO="${1:-leonel.mx}"
OCT="${2:-50}"
ALUMNO="${3:-Sin nombre}"
IFACE="${IFACE:-enp0s9}"
IP="192.168.${OCT}.1"
CA="/etc/ssl/lab/ca-${DOMINIO}.crt"
CRT="/etc/ssl/lab/www.${DOMINIO}.crt"
FECHA="$(date +%Y%m%d_%H%M%S)"
DIR="evidencias_web_${FECHA}"

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

ev 01_sistema.txt          "cat /etc/os-release; uname -a; hostnamectl"
ev 02_versiones.txt        "nginx -v; php -v | head -n 1; mysqld --version; openssl version; dpkg -l | grep -E 'nginx|php8.5|mysql-server'"
ev 03_servicios.txt        "systemctl is-active nginx php8.5-fpm mysql; systemctl status nginx php8.5-fpm mysql --no-pager | grep -E 'Active|Loaded'"
ev 04_puertos.txt          "ss -tlnp | grep -E ':(80|443|3306) '"
ev 05_nginx_validacion.txt "nginx -t"
ev 06_nginx_sitio.txt      "cat /etc/nginx/sites-available/${DOMINIO}; ls -l /etc/nginx/sites-enabled/"
ev 07_certificados.txt     "ls -l /etc/ssl/lab/; openssl verify -CAfile ${CA} ${CRT}; openssl x509 -in ${CRT} -noout -subject -issuer -dates -ext subjectAltName; openssl x509 -in ${CA} -noout -subject -fingerprint -sha256"
ev 08_tls.txt              "openssl s_client -connect ${IP}:443 -servername www.${DOMINIO} -CAfile ${CA} </dev/null 2>/dev/null | grep -E 'subject=|issuer=|Protocol|Cipher is|Verify return code'"
ev 09_redireccion_http.txt "curl -sI --resolve www.${DOMINIO}:80:${IP} http://www.${DOMINIO}/ | grep -iE '^HTTP|^location'"
ev 10_https_encabezados.txt "curl -sI --cacert ${CA} --resolve www.${DOMINIO}:443:${IP} https://www.${DOMINIO}/"
ev 11_https_pagina.txt     "curl -s --cacert ${CA} --resolve www.${DOMINIO}:443:${IP} https://www.${DOMINIO}/ | sed -e 's/<[^>]*>/ /g' | tr -s ' ' | grep -v '^ *$' | head -n 40"
ev 12_mysql.txt            "mysql -e \"SELECT * FROM laboratorio.servicios; SHOW GRANTS FOR 'webapp'@'localhost';\""
ev 13_archivos_protegidos.txt "for u in /config.php /.env /index.php; do printf '%-12s ' \$u; curl -s -o /dev/null -w '%{http_code}\n' --cacert ${CA} --resolve www.${DOMINIO}:443:${IP} https://www.${DOMINIO}\$u; done"
ev 14_permisos.txt         "ls -la /var/www/${DOMINIO} /var/www/${DOMINIO}/public; grep '^expose_php' /etc/php/8.5/fpm/php.ini"
ev 15_access_log.txt       "tail -n 50 /var/log/nginx/${DOMINIO}.access.log"

echo ">>> Capturando el handshake TLS durante 60 s en $IFACE. Abre https://www.${DOMINIO} en el cliente AHORA..."
timeout 60 tcpdump -i "$IFACE" -n 'tcp port 80 or tcp port 443' -w "$DIR/16_web.pcap" 2>/dev/null
ev 16_web_resumen.txt      "tcpdump -n -r $DIR/16_web.pcap 2>/dev/null | head -n 40"

# Integridad y empaquetado
( cd "$DIR" && sha256sum * > SHA256SUMS.txt )
tar -czf "${DIR}.tar.gz" "$DIR"
sha256sum "${DIR}.tar.gz" | tee "${DIR}.tar.gz.sha256"

echo
echo "✅ Evidencias generadas en: $DIR/"
echo "✅ Paquete: ${DIR}.tar.gz"
