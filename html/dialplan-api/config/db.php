<?php
define('DB_HOST', '127.0.0.1');
define('DB_NAME', 'pbx_user');
define('DB_USER', 'phpuser');
define('DB_PASS', 'php123');

// FreeSWITCH dialplan file paths — update these to match your install

//define('FS_DIALPLAN_PATH', '/usr/local/freeswitch/conf/dialplan');
define('FS_DIALPLAN_PATH', '/usr/local/freeswitch-automax-instance/etc/freeswitch/dialplan');
define('FS_DIALPLAN_FILES', [
    'public'   => FS_DIALPLAN_PATH . '/public.xml',
    'internal' => FS_DIALPLAN_PATH . '/default.xml',
    'features' => FS_DIALPLAN_PATH . '/features.xml',
]);

function getDB(): PDO {
    static $pdo = null;
    if ($pdo === null) {
        $pdo = new PDO(
            "mysql:host=".DB_HOST.";dbname=".DB_NAME.";charset=utf8mb4",
            DB_USER, DB_PASS,
            [PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
             PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
        );
    }
    return $pdo;
}
