<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

header('Content-Type: application/json');

$valid_api_key   = 'LeaderFS@Axionic#2026';
$request_api_key = $_SERVER['HTTP_X_API_KEY'] ?? '';

if ($request_api_key !== $valid_api_key) {
    http_response_code(401);
    echo json_encode([
        'success' => false,
        'message' => 'Unauthorized'
    ]);
    exit;
}

$directory = '/usr/local/freeswitch-automax-instance/etc/freeswitch/directory/leaderfs.axionic.io/';

$users = [];
$files = glob($directory . '*.xml');

$page  = max(1, (int)($_GET['page'] ?? 1));
$limit = max(1, (int)($_GET['limit'] ?? 10));
$search = trim($_GET['search'] ?? '');

libxml_use_internal_errors(true);

foreach ($files as $file) {
    $xml = simplexml_load_file($file);
    if (!$xml) continue;

    $id = (string)$xml->user['id'];

    if (!preg_match('/^\d+$/', $id)) continue;

    if ($search && strpos($id, $search) === false) continue;

    $users[] = $id;
}

sort($users, SORT_NUMERIC);

$total = count($users);
$offset = ($page - 1) * $limit;
$data = array_slice($users, $offset, $limit);

echo json_encode([
    'success' => true,
    'page' => $page,
    'limit' => $limit,
    'total' => $total,
    'pages' => ceil($total / $limit),
    'data' => $data
]);
