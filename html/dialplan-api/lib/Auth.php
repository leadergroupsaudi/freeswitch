<?php
define('API_KEY',   'LeaderFS@Axionic#2026');
define('LOG_FILE',  '/var/log/dialplan-api.log');

function writeLog(string $level, string $message): void {
    $ip   = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
    $time = date('Y-m-d H:i:s');
    $line = "[{$time}] [{$level}] [IP:{$ip}] {$message}" . PHP_EOL;
    file_put_contents(LOG_FILE, $line, FILE_APPEND | LOCK_EX);
}

function writeSeparator(): void {
    file_put_contents(LOG_FILE, str_repeat('-', 80) . PHP_EOL, FILE_APPEND | LOCK_EX);
}

function authenticateRequest(): void {

    // ── DEBUG BLOCK — remove after fix ────────────────────────────────────
    $httpHeaders = [];
    foreach ($_SERVER as $k => $v) {
        if (str_starts_with($k, 'HTTP_')) {
            $httpHeaders[$k] = $v;
        }
    }
    writeLog('DEBUG', "All HTTP headers received: " . json_encode($httpHeaders));
    writeLog('DEBUG', "HTTP_X_API_KEY  => [" . ($_SERVER['HTTP_X_API_KEY']  ?? 'MISSING') . "]");
    writeLog('DEBUG', "HTTP_X_Api_Key  => [" . ($_SERVER['HTTP_X_Api_Key']  ?? 'MISSING') . "]");
    writeLog('DEBUG', "Expected        => [" . API_KEY . "]");
    // ── END DEBUG BLOCK ───────────────────────────────────────────────────

    // Try both common header casings PHP might produce
    $requestKey = $_SERVER['HTTP_X_API_KEY']
               ?? $_SERVER['HTTP_X_Api_Key']
               ?? '';

    // Trim to catch invisible spaces from Postman
    $requestKey = trim($requestKey);

    writeLog('DEBUG', "Key after trim: [" . $requestKey . "] len:" . strlen($requestKey)
        . " | Expected len:" . strlen(API_KEY)
        . " | Match:" . ($requestKey === API_KEY ? 'YES' : 'NO'));

    if ($requestKey !== API_KEY) {
        $ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
        writeLog('ERROR', "UNAUTHORIZED — Invalid or missing API key from IP: {$ip}");
        writeSeparator();
        http_response_code(401);
        echo json_encode([
            'http_code' => 401,
            'success'   => false,
            'message'   => 'Unauthorized - Invalid or missing API key'
        ]);
        exit;
    }

    writeLog('INFO', "Authorized request — Method: {$_SERVER['REQUEST_METHOD']} URI: {$_SERVER['REQUEST_URI']}");
}
