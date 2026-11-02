<?php
// AVISO: reemplaza ${DB_PASS} por la contraseña real del usuario MySQL 'webapp'.
// Credenciales de la base de datos. Este archivo NO está dentro de public/
return [
    'dsn'  => 'mysql:host=localhost;dbname=laboratorio;charset=utf8mb4',
    'user' => 'webapp',
    'pass' => '${DB_PASS}',
];
