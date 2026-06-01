<?php
// health.php

header('Content-Type: application/json');

// ============================================
// LOG FILE SETUP
// ============================================
$log_file = __DIR__ . '/health.txt';

function write_log($message) {
    global $log_file;
    $time = date('Y-m-d H:i:s');
    file_put_contents($log_file, "[$time] $message\n", FILE_APPEND);
}

// ============================================
// API KEY CHECK
// ============================================
$valid_api_key   = 'LeaderFS@Axionic#2026';
$request_api_key = $_SERVER['HTTP_X_API_KEY'] ?? '';

if ($request_api_key !== $valid_api_key) {
    write_log("Unauthorized access attempt. API Key: ".$request_api_key);

    http_response_code(401);
    echo json_encode([
        'http_code' => 401,
        'success'   => false,
        'message'   => 'Unauthorized - Invalid or missing API key'
    ]);
    exit;
}

// ============================================
// CHECK DB
// ============================================
$db_status = 'connected';
$db_error  = null;

$conn = @new mysqli("localhost", "phpuser", "php123", "pbx_user");
if ($conn->connect_error) {
    $db_status = 'disconnected';
    $db_error  = $conn->connect_error;

    write_log("DB Connection Failed: ".$db_error);
} else {
    $conn->close();
}

// ============================================
// CHECK FREESWITCH DIRECTORY
// ============================================

$fs_dir      = "/usr/local/freeswitch-automax-instance/etc/freeswitch/directory/leaderfs.axionic.io/";
//$fs_dir      = "/usr/local/freeswitch/conf/directory/default/";
$fs_exists   = is_dir($fs_dir) ? 'exists' : 'not found';
$fs_writable = is_writable($fs_dir) ? 'writable' : 'not writable';

if ($fs_exists !== 'exists') {
    write_log("FS Directory not found: ".$fs_dir);
}
if ($fs_writable !== 'writable') {
    write_log("FS Directory not writable: ".$fs_dir);
}

// ============================================
// CHECK FREESWITCH RUNNING
// ============================================
$fs_status = 'unknown';

//$fs_output = @shell_exec("/usr/local/freeswitch/bin/fs_cli -x 'status' 2>&1");
$fs_output = shell_exec("/bin/fs_cli_automax --port 8022 -x 'status' 2>&1");
if ($fs_output === null) {
    $fs_status = 'not running';
    write_log("FreeSWITCH command failed (shell_exec issue or permission)");
} elseif (strpos($fs_output, 'UP') !== false) {
    $fs_status = 'running';
} else {
    $fs_status = 'not running';
    write_log("FreeSWITCH not running. Output: ".trim($fs_output));
}

// ============================================
// OVERALL STATUS
// ============================================
$overall = 'ok';

if ($db_status !== 'connected') $overall = 'degraded';
if ($fs_writable !== 'writable') $overall = 'degraded';
if ($fs_status !== 'running') $overall = 'degraded';

if ($db_status !== 'connected' && $fs_status !== 'running') {
    $overall = 'down';
}

// Log only if not OK
if ($overall !== 'ok') {
    write_log("Health check status: ".$overall);
}

// ============================================
// HTTP CODE
// ============================================
if ($overall === 'ok') {
    http_response_code(200);
} elseif ($overall === 'degraded') {
    http_response_code(207);
} else {
    http_response_code(503);
}

// ============================================
// RESPONSE
// ============================================
echo json_encode([
    'http_code'  => http_response_code(),
    'status'     => $overall,
    'timestamp'  => date('Y-m-d H:i:s'),
    'checks'     => [
        'database'  => [
            'status' => $db_status,
            'error'  => $db_error
        ],
        'freeswitch' => [
            'status' => $fs_status,
            'output' => trim($fs_output)
        ],
        'fs_directory' => [
            'path'     => $fs_dir,
            'exists'   => $fs_exists,
            'writable' => $fs_writable
        ]
    ]
]);

