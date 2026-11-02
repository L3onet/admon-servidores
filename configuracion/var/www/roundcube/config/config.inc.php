<?php
// AVISO: reemplaza CLAVE_BD (contraseña MySQL de 'roundcube') y LLAVE_DES (24 caracteres aleatorios); dominio de ejemplo leonel.mx.
// Roundcube · Práctica 5 · Laboratorio leonel.mx
$config = [];

// Base de datos (MySQL de la práctica Web)
$config['db_dsnw'] = 'mysql://roundcube:CLAVE_BD@localhost/roundcube';

// Servidores de correo: el nombre coincide con el certificado de la CA
$config['imap_host'] = 'tls://mail.leonel.mx:143';
$config['smtp_host'] = 'tls://mail.leonel.mx:587';
$config['smtp_user'] = '%u';
$config['smtp_pass'] = '%p';
$config['mail_domain'] = 'leonel.mx';

// Interfaz
$config['product_name'] = 'Webmail leonel.mx';
$config['skin'] = 'elastic';
$config['language'] = 'es_ES';
$config['plugins'] = ['archive', 'zipdownload'];

// Seguridad
$config['des_key'] = 'LLAVE_DES';
$config['enable_installer'] = false;
$config['log_logins'] = true;
$config['session_lifetime'] = 30;
$config['ip_check'] = true;
$config['support_url'] = '';
