<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../lib/Auth.php';

header('Content-Type: application/json');

authenticateRequest();

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    writeLog('WARN', "Method not allowed: {$_SERVER['REQUEST_METHOD']}");
    http_response_code(405);
    echo json_encode(['error' => 'Method Not Allowed']);
    exit;
}

try {
    $stmt = getDB()->prepare(
        "SELECT * FROM dialplan_rules
         WHERE context = 'internal'
         ORDER BY priority ASC, id ASC"
    );
    $stmt->execute();
    $rules = $stmt->fetchAll();

    foreach ($rules as &$r) {
        $r['conditions'] = json_decode($r['conditions'], true);
        $r['actions']    = json_decode($r['actions'],    true);
        $r['enabled']    = (bool)$r['enabled'];
    }

    writeLog('INFO', "Returned " . count($rules) . " internal rules");
    echo json_encode($rules);

} catch (Throwable $e) {
    writeLog('ERROR', "DB error: " . $e->getMessage());
    http_response_code(500);
    echo json_encode(['error' => $e->getMessage()]);
}
