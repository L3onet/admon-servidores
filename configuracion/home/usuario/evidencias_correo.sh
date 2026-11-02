#!/usr/bin/env bash
# Recolector de evidencias - Correo: Postfix 3.10 + Dovecot 2.4 + Roundcube 1.6 (Ubuntu 26.04.1 LTS)
# Uso: sudo ./evidencias_correo.sh <dominio> <octeto> "<Nombre del alumno>"

set -uo pipefail

DOMINIO="${1:-leonel.mx}"
OCT="${2:-50}"
ALUMNO="${3:-Sin nombre}"
IFACE="${IFACE:-enp0s9}"
IP="192.168.${OCT}.1"
CA="/etc/ssl/lab/ca-${DOMINIO}.crt"
FECHA="$(date +%Y%m%d_%H%M%S)"
DIR="evidencias_correo_${FECHA}"

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
ev 02_versiones.txt        "postconf -h mail_version; dovecot --version; grep -m1 RCMAIL_VERSION /var/www/roundcube/program/include/iniset.php; dpkg -l postfix dovecot-core dovecot-imapd dovecot-lmtpd | grep '^ii'; dpkg -l 'roundcube*' 2>/dev/null | grep '^ii' || echo 'Paquete roundcube de Ubuntu: no instalado (correcto)'"
ev 03_servicios.txt        "systemctl is-active postfix dovecot nginx php8.5-fpm mysql"
ev 04_puertos.txt          "ss -tlnp | grep -E ':(25|587|143|993|443) '"
ev 05_postfix_main.txt     "postfix check && echo 'postfix check: OK'; postconf -n"
ev 06_postfix_submission.txt "postconf -M submission/inet; postconf -P submission/inet; cat /etc/postfix/login_maps.regexp"
ev 07_dovecot.txt          "doveconf -n"
ev 08_sockets.txt          "ls -l /var/spool/postfix/private/ | grep -E 'auth|dovecot-lmtp'"
ev 09_dns.txt              "dig @${IP} ${DOMINIO} MX +short; dig @${IP} mail.${DOMINIO} +short; dig @${IP} ${DOMINIO} TXT +short"
ev 10_tls.txt              "for p in 587 143; do echo \"--- STARTTLS \$p\"; openssl s_client -starttls \$( [ \$p = 587 ] && echo smtp || echo imap ) -connect ${IP}:\$p -servername mail.${DOMINIO} -CAfile ${CA} </dev/null 2>/dev/null | grep -E 'subject=|issuer=|Protocol|Verify return code'; done; echo '--- IMAPS 993'; openssl s_client -connect ${IP}:993 -servername mail.${DOMINIO} -CAfile ${CA} </dev/null 2>/dev/null | grep -E 'subject=|Protocol|Verify return code'"
ev 11_relay_abierto.txt    "printf 'Subject: spam\n\nspam\n' | curl -s --url smtp://${IP}:25 --mail-from spammer@ejemplo.com --mail-rcpt victima@gmail.com --upload-file - -v 2>&1 | grep -E '^< (220|250|454|554)|RCPT failed'"
ev 12_buzones.txt          "for u in ana luis; do echo \"--- \$u\"; ls -la /home/\$u/Maildir/ /home/\$u/Maildir/new/ 2>/dev/null; done"
ev 13_bitacora_correo.txt  "journalctl --since '3 hours ago' --no-pager | grep -E 'postfix/|dovecot' | grep -E 'sasl_username|status=sent|Saved|Relay access denied|not owned by user|imap-login|lmtp' | tail -n 80"
ev 14_roundcube.txt        "grep -E \"imap_host|smtp_host|mail_domain|product_name|enable_installer\" /var/www/roundcube/config/config.inc.php; ls -ld /var/www/roundcube/installer 2>&1; tail -n 20 /var/www/roundcube/logs/userlogins.log; curl -s --cacert ${CA} --resolve mail.${DOMINIO}:443:${IP} https://mail.${DOMINIO}/ | grep -oE '<title>[^<]*'"
ev 15_tabla_servicios.txt  "mysql -e 'SELECT practica, servicio, software, estado FROM laboratorio.servicios;'"

echo ">>> Capturando tráfico de correo durante 60 s en $IFACE. Envía y lee un correo desde el cliente AHORA..."
timeout 60 tcpdump -i "$IFACE" -n 'tcp port 25 or tcp port 587 or tcp port 143 or tcp port 993' -w "$DIR/16_correo.pcap" 2>/dev/null
ev 16_correo_resumen.txt   "tcpdump -n -r $DIR/16_correo.pcap 2>/dev/null | head -n 30; echo '--- Texto legible:'; tcpdump -n -A -r $DIR/16_correo.pcap 2>/dev/null | grep -aoE '(220 [[:print:]]+|EHLO [[:print:]]+|STARTTLS|\\* OK [[:print:]]+)' | sort -u"

# Integridad y empaquetado
( cd "$DIR" && sha256sum * > SHA256SUMS.txt )
tar -czf "${DIR}.tar.gz" "$DIR"
sha256sum "${DIR}.tar.gz" | tee "${DIR}.tar.gz.sha256"

echo
echo "✅ Evidencias generadas en: $DIR/"
echo "✅ Paquete: ${DIR}.tar.gz"
