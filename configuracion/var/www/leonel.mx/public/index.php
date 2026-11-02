<?php
// AVISO: dominio de ejemplo leonel.mx.
declare(strict_types=1);

$config  = require __DIR__ . '/../config.php';
$dominio = $_SERVER['SERVER_NAME'] ?? 'localhost';
$https   = ($_SERVER['HTTPS'] ?? '') === 'on';

function e(string $s): string
{
    return htmlspecialchars($s, ENT_QUOTES, 'UTF-8');
}

try {
    $pdo = new PDO($config['dsn'], $config['user'], $config['pass'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ]);
    $mysql     = (string) $pdo->query('SELECT VERSION()')->fetchColumn();
    $servicios = $pdo->query(
        'SELECT practica, servicio, software, nombre_dns, estado FROM servicios ORDER BY practica'
    )->fetchAll(PDO::FETCH_ASSOC);
    $error = false;
} catch (PDOException $ex) {
    error_log('Error de MySQL: ' . $ex->getMessage());   // El detalle va al log, no al visitante
    $mysql     = 'sin conexión';
    $servicios = [];
    $error     = true;
}
?>
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><?= e($dominio) ?> · Laboratorio</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 860px; margin: 2rem auto; padding: 0 1rem; color: #1f2933; }
    .ok { color: #137333; } .no { color: #b3261e; }
    table { border-collapse: collapse; width: 100%; margin-top: 1rem; }
    th, td { border: 1px solid #d0d7de; padding: .45rem .6rem; text-align: left; }
    th { background: #f3f4f6; }
    code { background: #f3f4f6; padding: .1rem .3rem; border-radius: 4px; }
  </style>
</head>
<body>
  <h1><?= e($dominio) ?></h1>
  <p>Servidor web del laboratorio de Administración de servidores.</p>
  <ul>
    <li>Conexión:
      <?= $https ? '<span class="ok">HTTPS 🔒</span>' : '<span class="no">HTTP sin cifrar</span>' ?>
      · <?= e($_SERVER['SERVER_PROTOCOL'] ?? '') ?></li>
    <li>Tu IP (entregada por Kea): <code><?= e($_SERVER['REMOTE_ADDR'] ?? '') ?></code></li>
    <li>Servidor: <code><?= e(gethostname() ?: '') ?></code>
      · PHP <code><?= e(PHP_VERSION) ?></code>
      · MySQL <code><?= e($mysql) ?></code></li>
  </ul>

  <?php if ($error): ?>
    <p class="no">No fue posible conectar con la base de datos. Revisa el log del servidor.</p>
  <?php endif; ?>

  <h2>Servicios del laboratorio</h2>
  <table>
    <tr><th>#</th><th>Servicio</th><th>Software</th><th>Nombre DNS</th><th>Estado</th></tr>
    <?php foreach ($servicios as $s): ?>
      <tr>
        <td><?= (int) $s['practica'] ?></td>
        <td><?= e($s['servicio']) ?></td>
        <td><?= e($s['software']) ?></td>
        <td><code><?= e($s['nombre_dns'] . '.' . $dominio) ?></code></td>
        <td class="<?= $s['estado'] === 'Instalado' ? 'ok' : 'no' ?>"><?= e($s['estado']) ?></td>
      </tr>
    <?php endforeach; ?>
  </table>
</body>
</html>
