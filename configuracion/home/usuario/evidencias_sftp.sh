#!/usr/bin/env bash
# Recolector de evidencias - Servidor SFTP OpenSSH 10.2 (Ubuntu 26.04.1 LTS)
# Uso: sudo ./evidencias_sftp.sh <dominio> <octeto> "<Nombre del alumno>"

set -uo pipefail

DOMINIO="${1:-leonel.mx}"
OCT="${2:-50}"
ALUMNO="${3:-Sin nombre}"
IFACE="${IFACE:-enp0s9}"
USUARIO="${USUARIO:-webmaster}"
IP="192.168.${OCT}.1"
CA="/etc/ssl/lab/ca-${DOMINIO}.crt"
SITIO="/var/www/${DOMINIO}"
FECHA="$(date +%Y%m%d_%H%M%S)"
DIR="evidencias_sftp_${FECHA}"

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

ev 01_sistema.txt         "cat /etc/os-release; uname -a; hostnamectl"
ev 02_version.txt         "ssh -V; dpkg -l | grep -E 'openssh-(server|client|sftp)'"
ev 03_servicio.txt        "systemctl status ssh.socket ssh --no-pager | grep -E 'Loaded|Active|Listen'"
ev 04_puerto_22.txt       "ss -tlnp | grep ':22 '"
ev 05_validacion.txt      "sshd -t && echo 'RESULTADO: configuracion valida'"
ev 06_config_grupo.txt    "cat /etc/ssh/sshd_config.d/60-sftp-web.conf"
ev 07_config_efectiva.txt "sshd -T -C user=${USUARIO},host=cliente,addr=192.168.${OCT}.100 | grep -E '^(chrootdirectory|forcecommand|authorizedkeysfile|authenticationmethods|passwordauthentication|permittty|allowtcpforwarding|allowagentforwarding|permittunnel|x11forwarding)'"
ev 08_usuario.txt         "id ${USUARIO}; getent passwd ${USUARIO}; passwd -S ${USUARIO}"
ev 09_permisos_chroot.txt "namei -l ${SITIO}/public; ls -la ${SITIO} ${SITIO}/public; findmnt ${SITIO}/dev/log"
ev 10_llaves.txt          "echo '--- Llaves autorizadas'; ssh-keygen -lf /etc/ssh/authorized_keys/${USUARIO}; echo '--- Huellas del servidor'; for f in /etc/ssh/ssh_host_*_key.pub; do ssh-keygen -lf \$f; done"
ev 11_publicacion_web.txt "for u in /practica4.html /hora.php; do printf '%-16s ' \$u; curl -s -o /dev/null -w '%{http_code}\n' --cacert ${CA} --resolve www.${DOMINIO}:443:${IP} https://www.${DOMINIO}\$u; done; curl -s --cacert ${CA} --resolve www.${DOMINIO}:443:${IP} https://www.${DOMINIO}/hora.php"
ev 12_base_datos.txt      "mysql -e 'SELECT practica, servicio, software, estado FROM laboratorio.servicios;'"
ev 13_bitacora_sftp.txt   "journalctl -u ssh --since '3 hours ago' --no-pager | grep -E 'Accepted|Failed|session opened|open \"|close \"|remove|rename|mkdir|sftp' | tail -n 100"
ev 14_sshfp.txt           "dig @${IP} srv-dhcp.${DOMINIO} SSHFP +short || echo 'Extra SSHFP no realizado'"

echo ">>> Capturando tráfico SSH durante 60 s en $IFACE. Sube un archivo desde el cliente AHORA..."
timeout 60 tcpdump -i "$IFACE" -n 'tcp port 22' -w "$DIR/15_ssh.pcap" 2>/dev/null
ev 15_ssh_resumen.txt     "tcpdump -n -r $DIR/15_ssh.pcap 2>/dev/null | head -n 30; echo '--- Texto legible en la captura:'; tcpdump -n -A -r $DIR/15_ssh.pcap 2>/dev/null | grep -oE 'SSH-2.0-[[:print:]]+' | sort -u"

# Integridad y empaquetado
( cd "$DIR" && sha256sum * > SHA256SUMS.txt )
tar -czf "${DIR}.tar.gz" "$DIR"
sha256sum "${DIR}.tar.gz" | tee "${DIR}.tar.gz.sha256"

echo
echo "✅ Evidencias generadas en: $DIR/"
echo "✅ Paquete: ${DIR}.tar.gz"
