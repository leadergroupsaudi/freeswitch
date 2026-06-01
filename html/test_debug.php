<?php
ini_set('display_errors', 1);
ini_set('log_errors', 1);
error_reporting(E_ALL);

header('Content-Type: application/json');
$result = [];

// 1. PHP info
$result['php'] = [
    'version' => phpversion(),
    'user'    => exec('whoami'),
    'sapi'    => php_sapi_name(),
];

// 2. Check all required files exist
$base  = '/var/www/html/dialplan-api';
$files = [
    'config/db.php'         => $base . '/config/db.php',
    'lib/Auth.php'          => $base . '/lib/Auth.php',
    'lib/FreeSwitchESL.php' => $base . '/lib/FreeSwitchESL.php',
    'lib/DialplanXML.php'   => $base . '/lib/DialplanXML.php',
    'api/handler.php'       => $base . '/api/dialplan/handler.php',
];

foreach ($files as $name => $path) {
    $result['files'][$name] = [
        'exists'   => file_exists($path),
        'readable' => is_readable($path),
    ];
}

// 3. Load each file and catch errors
foreach ($files as $name => $path) {
    if (!file_exists($path)) {
        $result['load'][$name] = 'MISSING';
        continue;
    }
    try {
        require_once $path;
        $result['load'][$name] = 'OK';
    } catch (Throwable $e) {
        $result['load'][$name] = 'ERROR: ' . $e->getMessage() . ' line:' . $e->getLine();
    }
}

// 4. DB connection
try {
    $db    = getDB();
    $count = $db->query("SELECT COUNT(*) FROM dialplan_rules")->fetchColumn();
    $result['database'] = ['status' => 'OK', 'total_rules' => $count];
} catch (Throwable $e) {
    $result['database'] = ['status' => 'FAILED', 'error' => $e->getMessage()];
}

// 5. Dialplan file checks
if (defined('FS_DIALPLAN_FILES')) {
    foreach (FS_DIALPLAN_FILES as $ctx => $path) {
        $result['dialplan'][$ctx] = [
            'path'     => $path,
            'exists'   => file_exists($path),
            'readable' => is_readable($path),
            'writable' => is_writable($path),
        ];
    }
} else {
    $result['dialplan'] = 'FS_DIALPLAN_FILES not defined';
}

// 6. Log file check
$logPath = '/var/log/dialplan-api.log';
$result['log_file'] = [
    'path'     => $logPath,
    'exists'   => file_exists($logPath),
    'writable' => is_writable($logPath),
    'selinux'  => exec("ls -Z {$logPath} 2>/dev/null"),
];

// 7. SELinux status
$result['selinux'] = [
    'status'  => exec('getenforce 2>/dev/null'),
    'denials' => shell_exec('ausearch -m avc -ts recent 2>/dev/null | grep httpd | tail -5'),
];

// 8. Apache modules
$result['apache_modules'] = [
    'rewrite' => exec('httpd -M 2>/dev/null | grep rewrite'),
    'php'     => exec('httpd -M 2>/dev/null | grep php'),
    'proxy'   => exec('httpd -M 2>/dev/null | grep proxy'),
];

echo json_encode($result, JSON_PRETTY_PRINT);
