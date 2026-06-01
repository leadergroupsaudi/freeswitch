<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../lib/FreeSwitchESL.php';
require_once __DIR__ . '/../../lib/DialplanXML.php';
require_once __DIR__ . '/../../lib/Auth.php';

header('Content-Type: application/json');
authenticateRequest();

$method = $_SERVER['REQUEST_METHOD'];
$uri    = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

// ── helpers ────────────────────────────────────────────────────────────────

function jsonBody(): array {
    return json_decode(file_get_contents('php://input'), true) ?? [];
}

function rebuildAndReload(PDO $db, string $context): void {
    $s = $db->prepare(
        "SELECT * FROM dialplan_rules WHERE context=? ORDER BY priority ASC, id ASC"
    );
    $s->execute([$context]);
    DialplanXML::write($context, $s->fetchAll());

    $esl = new FreeSwitchESL();
    if ($esl->connect()) {
        $esl->reloadDialplan();
        $esl->disconnect();
        writeLog('INFO', "FreeSWITCH reloadxml triggered successfully");
    } else {
        writeLog('ERROR', "FreeSWITCH ESL connection failed — reloadxml not triggered");
    }
}

function extractId(string $uri): ?int {
    return preg_match('#/public/(\d+)$#', $uri, $m) ? (int)$m[1] : null;
}

// ── VALIDATION ─────────────────────────────────────────────────────────────

function validatePayload(array $body): array {
    $errors = [];

    foreach (['name', 'extension', 'conditions', 'actions'] as $f) {
        if (!isset($body[$f]) || $body[$f] === '' || $body[$f] === [] || $body[$f] === null) {
            $errors[] = "Missing required field: {$f}";
        }
    }
    if (!empty($errors)) return $errors;

    if (!preg_match('/^[\w\s\-\.]+$/', $body['name']))
        $errors[] = "name: only letters, numbers, spaces, hyphens and dots allowed";

    if (@preg_match('/' . $body['extension'] . '/', '') === false)
        $errors[] = "extension: invalid regular expression";

    if (!is_array($body['conditions']) || empty($body['conditions'])) {
        $errors[] = "conditions: must be a non-empty array";
    } else {
        $allowedFields = [
            'destination_number', 'caller_id_number', 'caller_id_name',
            'network_addr', 'rdnis', 'ani', 'ani2', 'uuid', 'source',
            'transfer_source', 'dialplan', 'context', 'hostname',
            'sip_from_uri', 'sip_to_uri', 'channel_name'
        ];
        foreach ($body['conditions'] as $i => $cond) {
            if (!is_array($cond)) { $errors[] = "conditions[{$i}]: must be an object"; continue; }
            if (empty($cond['field']))      $errors[] = "conditions[{$i}]: missing 'field'";
            if (empty($cond['expression'])) $errors[] = "conditions[{$i}]: missing 'expression'";
            if (isset($cond['expression']) && @preg_match('/' . $cond['expression'] . '/', '') === false)
                $errors[] = "conditions[{$i}]: expression is not a valid regex";
            if (isset($cond['field']) && !in_array($cond['field'], $allowedFields))
                $errors[] = "conditions[{$i}]: unknown field '{$cond['field']}'";
        }
    }

    if (!is_array($body['actions']) || empty($body['actions'])) {
        $errors[] = "actions: must be a non-empty array";
    } else {
        $knownApps = [
            'answer', 'hangup', 'bridge', 'transfer', 'set', 'export',
            'unset', 'log', 'info', 'sleep', 'playback', 'play_and_get_digits',
            'speak', 'say', 'record', 'record_session', 'echo', 'park',
            'hold', 'intercept', 'eavesdrop', 'three_way', 'conference',
            'ivr', 'menu', 'voicemail', 'lua', 'javascript', 'python',
            'socket', 'hash', 'limit', 'db', 'group', 'ring_ready',
            'pre_answer', 'redirect', 'deflect', 'respond', 'rxfax', 'txfax',
            'tone_detect', 'bind_meta_app', 'unbind_meta_app', 'detect_speech',
            'gentones', 'send_dtmf', 'queue', 'fifo', 'att_xfer', 'blind_xfer',
            'start_dtmf', 'stop_dtmf', 'read', 'flite', 'phrase',
            'execute_extension', 'sched_hangup', 'sched_transfer', 'strftime',
            'regex', 'curl', 'system', 'multiset', 'media_reset', 'session_loglevel'
        ];
        foreach ($body['actions'] as $i => $act) {
            if (!is_array($act)) { $errors[] = "actions[{$i}]: must be an object"; continue; }
            if (empty($act['application'])) { $errors[] = "actions[{$i}]: missing 'application'"; continue; }
            if (!in_array($act['application'], $knownApps))
                $errors[] = "actions[{$i}]: unknown application '{$act['application']}'";
            if ($act['application'] === 'bridge' && isset($act['data']))
                if (!preg_match('/(sofia\/|user\/|loopback\/|freetdm\/)/', $act['data']))
                    $errors[] = "actions[{$i}]: bridge data must contain a valid endpoint";
        }
    }

    if (isset($body['priority']) && !is_int($body['priority']))
        $errors[] = "priority: must be an integer";

    if (isset($body['enabled']) && !is_bool($body['enabled']))
        $errors[] = "enabled: must be true or false";

    return $errors;
}

// ── DUPLICATE CHECK ────────────────────────────────────────────────────────

function checkDuplicate(PDO $db, string $name, string $extension,
                        string $context, ?int $excludeId = null): bool {
    $sql    = "SELECT COUNT(*) FROM dialplan_rules
               WHERE (name = ? OR extension = ?) AND context = ?";
    $params = [$name, $extension, $context];
    if ($excludeId !== null) { $sql .= " AND id != ?"; $params[] = $excludeId; }
    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    return (int)$stmt->fetchColumn() > 0;
}

// ── ROUTING ────────────────────────────────────────────────────────────────

try {
    $db = getDB();

    // ── POST /reorder ──────────────────────────────────────────────────────
    if ($method === 'POST' && str_ends_with($uri, '/reorder')) {
        $body = jsonBody();

        if (empty($body['orderedIds']) || !is_array($body['orderedIds'])) {
            writeLog('WARN', "Reorder failed — orderedIds missing or invalid");
            writeSeparator();
            http_response_code(400);
            echo json_encode(['error' => 'orderedIds array required']);
            exit;
        }

        $db->beginTransaction();
        $s = $db->prepare(
            "UPDATE dialplan_rules SET priority=? WHERE id=? AND context='public'"
        );
        foreach ($body['orderedIds'] as $i => $id)
            $s->execute([$i + 1, (int)$id]);
        $db->commit();

        writeLog('INFO', "Reorder applied — " . count($body['orderedIds'])
            . " rules reordered. New order IDs: [" . implode(', ', $body['orderedIds']) . "]");
        rebuildAndReload($db, 'public');
        writeSeparator();
        echo json_encode(['success' => true]);
        exit;
    }

    // ── POST /public — create ──────────────────────────────────────────────
    if ($method === 'POST') {
        $body   = jsonBody();
        $errors = validatePayload($body);

        if (!empty($errors)) {
            writeLog('WARN', "Validation failed — name:'" . ($body['name'] ?? 'N/A')
                . "' ext:'" . ($body['extension'] ?? 'N/A') . "'"
                . " | Errors: " . implode(' | ', $errors));
            writeSeparator();
            http_response_code(422);
            echo json_encode(['error' => 'Validation failed', 'details' => $errors]);
            exit;
        }

        if (checkDuplicate($db, $body['name'], $body['extension'], 'public')) {
            writeLog('WARN', "Duplicate rejected — name:'{$body['name']}'"
                . " ext:'{$body['extension']}' context:public");
            writeSeparator();
            http_response_code(409);
            echo json_encode([
                'error'  => 'Duplicate entry',
                'detail' => 'A rule with the same name or extension already exists in public context'
            ]);
            exit;
        }

        $s = $db->prepare("INSERT INTO dialplan_rules
            (name, extension, conditions, actions, priority, enabled, context)
            VALUES (:name, :ext, :cond, :act, :pri, :en, 'public')");
        $s->execute([
            ':name' => $body['name'],
            ':ext'  => $body['extension'],
            ':cond' => json_encode($body['conditions']),
            ':act'  => json_encode($body['actions']),
            ':pri'  => $body['priority'] ?? 10,
            ':en'   => isset($body['enabled']) ? (int)$body['enabled'] : 1,
        ]);
        $newId = (int)$db->lastInsertId();

        writeLog('INFO', "Rule CREATED"
            . " | ID:{$newId}"
            . " | name:'{$body['name']}'"
            . " | extension:'{$body['extension']}'"
            . " | priority:" . ($body['priority'] ?? 10)
            . " | enabled:" . ($body['enabled'] ? 'true' : 'false')
            . " | conditions:" . count($body['conditions'])
            . " | actions:" . count($body['actions']));

        rebuildAndReload($db, 'public');
        writeSeparator();
        http_response_code(201);
        echo json_encode(['success' => true, 'id' => $newId]);
        exit;
    }

    // ── PUT /public/:id — update ───────────────────────────────────────────
    if ($method === 'PUT') {
        $id = extractId($uri);
        if (!$id) {
            writeLog('WARN', "Update failed — no rule ID in URI: {$uri}");
            writeSeparator();
            http_response_code(400);
            echo json_encode(['error' => 'Rule ID required']);
            exit;
        }

        $body   = jsonBody();
        $errors = validatePayload($body);

        if (!empty($errors)) {
            writeLog('WARN', "Validation failed on UPDATE — ID:{$id}"
                . " name:'" . ($body['name'] ?? 'N/A') . "'"
                . " | Errors: " . implode(' | ', $errors));
            writeSeparator();
            http_response_code(422);
            echo json_encode(['error' => 'Validation failed', 'details' => $errors]);
            exit;
        }

        if (checkDuplicate($db, $body['name'], $body['extension'], 'public', $id)) {
            writeLog('WARN', "Duplicate rejected on UPDATE — ID:{$id}"
                . " name:'{$body['name']}' ext:'{$body['extension']}'");
            writeSeparator();
            http_response_code(409);
            echo json_encode([
                'error'  => 'Duplicate entry',
                'detail' => 'Another rule with the same name or extension already exists'
            ]);
            exit;
        }

        $s = $db->prepare("UPDATE dialplan_rules SET
            name=:name, extension=:ext, conditions=:cond, actions=:act,
            priority=:pri, enabled=:en
            WHERE id=:id AND context='public'");
        $s->execute([
            ':name' => $body['name'],
            ':ext'  => $body['extension'],
            ':cond' => json_encode($body['conditions']),
            ':act'  => json_encode($body['actions']),
            ':pri'  => $body['priority'] ?? 10,
            ':en'   => isset($body['enabled']) ? (int)$body['enabled'] : 1,
            ':id'   => $id,
        ]);

        if ($s->rowCount() === 0) {
            writeLog('WARN', "Update failed — rule ID:{$id} not found in public context");
            writeSeparator();
            http_response_code(404);
            echo json_encode(['error' => 'Rule not found']);
            exit;
        }

        writeLog('INFO', "Rule UPDATED"
            . " | ID:{$id}"
            . " | name:'{$body['name']}'"
            . " | extension:'{$body['extension']}'"
            . " | priority:" . ($body['priority'] ?? 10)
            . " | enabled:" . ($body['enabled'] ? 'true' : 'false')
            . " | conditions:" . count($body['conditions'])
            . " | actions:" . count($body['actions']));

        rebuildAndReload($db, 'public');
        writeSeparator();
        echo json_encode(['success' => true]);
        exit;
    }

    // ── DELETE /public/:id ─────────────────────────────────────────────────
    if ($method === 'DELETE') {
        $id = extractId($uri);
        if (!$id) {
            writeLog('WARN', "Delete failed — no rule ID in URI: {$uri}");
            writeSeparator();
            http_response_code(400);
            echo json_encode(['error' => 'Rule ID required']);
            exit;
        }

        // Fetch rule details before deleting for the log
        $fetch = $db->prepare("SELECT name, extension FROM dialplan_rules WHERE id=? AND context='public'");
        $fetch->execute([$id]);
        $existing = $fetch->fetch();

        if (!$existing) {
            writeLog('WARN', "Delete failed — rule ID:{$id} not found in public context");
            writeSeparator();
            http_response_code(404);
            echo json_encode(['error' => 'Rule not found']);
            exit;
        }

        $s = $db->prepare("DELETE FROM dialplan_rules WHERE id=? AND context='public'");
        $s->execute([$id]);

        writeLog('INFO', "Rule DELETED"
            . " | ID:{$id}"
            . " | name:'{$existing['name']}'"
            . " | extension:'{$existing['extension']}'");

        rebuildAndReload($db, 'public');
        writeSeparator();
        echo json_encode(['success' => true]);
        exit;
    }

    writeLog('WARN', "Method not allowed: {$method} on {$uri}");
    writeSeparator();
    http_response_code(405);
    echo json_encode(['error' => 'Method Not Allowed']);

} catch (Throwable $e) {
    writeLog('ERROR', "Unhandled exception: " . $e->getMessage()
        . " in " . $e->getFile() . " line " . $e->getLine());
    writeSeparator();
    http_response_code(500);
    echo json_encode(['error' => $e->getMessage()]);
}
