<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../lib/FreeSwitchESL.php';
require_once __DIR__ . '/../../lib/DialplanXML.php';
require_once __DIR__ . '/../../lib/Auth.php';

header('Content-Type: application/json');
authenticateRequest();

$method = $_SERVER['REQUEST_METHOD'];
$uri    = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

preg_match('#/api/admin/dialplan/([^/]+)#', $uri, $ctxMatch);
$context = $ctxMatch[1] ?? '';

$allowedContexts = ['public', 'internal', 'features'];
if (!in_array($context, $allowedContexts)) {
    writeLog('WARN', "Invalid context: '{$context}'");
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error'   => 'Invalid context',
        'allowed' => $allowedContexts
    ]);
    exit;
}

// ── HELPERS ────────────────────────────────────────────────────────────────

function jsonBody(): array {
    return json_decode(file_get_contents('php://input'), true) ?? [];
}

function extractId(string $uri): ?int {
    return preg_match('#/(\d+)$#', $uri, $m) ? (int)$m[1] : null;
}

// ── SANITIZE ───────────────────────────────────────────────────────────────

function sanitizeBody(array $body): array {
    $allowedKeys = ['name', 'extension', 'conditions', 'actions', 'priority', 'enabled'];

    $unknownKeys = array_keys(array_diff_key($body, array_flip($allowedKeys)));
    if (!empty($unknownKeys))
        writeLog('WARN', "Sanitize — stripped unknown keys: [" . implode(', ', $unknownKeys) . "]");

    $clean = array_intersect_key($body, array_flip($allowedKeys));

    if (isset($clean['name']))
        $clean['name'] = trim(strip_tags($clean['name']));

    if (isset($clean['extension']))
        $clean['extension'] = trim(strip_tags($clean['extension']));

    if (isset($clean['conditions']) && is_array($clean['conditions'])) {
        $allowedConditionKeys = [
            'field', 'expression', 'year', 'mon', 'mday', 'wday',
            'hour', 'minute', 'minute-of-day', 'week', 'date-time',
            'time-of-day', 'day-of-week', 'break'
        ];
        foreach ($clean['conditions'] as $i => $cond) {
            if (!is_array($cond)) continue;
            $unknownCond = array_keys(array_diff_key($cond, array_flip($allowedConditionKeys)));
            if (!empty($unknownCond))
                writeLog('WARN', "Sanitize — conditions[{$i}] stripped: [" . implode(', ', $unknownCond) . "]");
            $clean['conditions'][$i] = array_intersect_key($cond, array_flip($allowedConditionKeys));
            foreach ($clean['conditions'][$i] as $k => $v)
                $clean['conditions'][$i][$k] = trim(strip_tags((string)$v));
        }
    }

    if (isset($clean['actions']) && is_array($clean['actions'])) {
        $allowedActionKeys = ['_type', 'application', 'data'];
        foreach ($clean['actions'] as $i => $act) {
            if (!is_array($act)) continue;
            $unknownAct = array_keys(array_diff_key($act, array_flip($allowedActionKeys)));
            if (!empty($unknownAct))
                writeLog('WARN', "Sanitize — actions[{$i}] stripped: [" . implode(', ', $unknownAct) . "]");
            $clean['actions'][$i] = array_intersect_key($act, array_flip($allowedActionKeys));
            foreach ($clean['actions'][$i] as $k => $v)
                $clean['actions'][$i][$k] = trim((string)$v);
            if (!isset($clean['actions'][$i]['_type']))
                $clean['actions'][$i]['_type'] = 'action';
        }
    }

    if (isset($clean['priority']))
        $clean['priority'] = (int)$clean['priority'];

    if (isset($clean['enabled']))
        $clean['enabled'] = filter_var($clean['enabled'], FILTER_VALIDATE_BOOLEAN);

    return $clean;
}

// ── VALIDATE ───────────────────────────────────────────────────────────────

function validatePayload(array $body): array {
    $errors = [];

    foreach (['name', 'extension', 'conditions', 'actions'] as $f) {
        if (!isset($body[$f]) || $body[$f] === '' || $body[$f] === [] || $body[$f] === null)
            $errors[] = "Missing required field: {$f}";
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
            'ani', 'ani2', 'rdnis', 'network_addr', 'network_port',
            'sip_from_uri', 'sip_from_user', 'sip_from_host',
            'sip_to_uri', 'sip_to_user', 'sip_to_host',
            'sip_contact_user', 'sip_contact_host', 'uuid', 'source',
            'transfer_source', 'dialplan', 'context', 'hostname',
            'channel_name', 'call_direction', 'date-time', 'time-of-day',
            'day-of-week', 'date', 'time', 'year', 'mon', 'mday', 'wday',
            'hour', 'minute', 'minute-of-day', 'week', 'acl', 'url',
            'lan-addr', 'strftime', 'xml_list', 'exists',
        ];
        foreach ($body['conditions'] as $i => $cond) {
            if (!is_array($cond)) {
                $errors[] = "conditions[{$i}]: must be an object"; continue;
            }
            if (empty($cond['field']))
                $errors[] = "conditions[{$i}]: missing 'field'";
            if (empty($cond['expression']))
                $errors[] = "conditions[{$i}]: missing 'expression'";
            if (isset($cond['expression']) &&
                @preg_match('/' . $cond['expression'] . '/', '') === false)
                $errors[] = "conditions[{$i}]: invalid regex expression";
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
            'regex', 'curl', 'system', 'multiset', 'media_reset',
            'session_loglevel', 'presence', 'check_acl',
        ];
        $hasAction     = false;
        $hasAntiAction = false;
        foreach ($body['actions'] as $i => $act) {
            if (!is_array($act)) {
                $errors[] = "actions[{$i}]: must be an object"; continue;
            }
            $type = $act['_type'] ?? 'action';
            if (!in_array($type, ['action', 'anti-action']))
                $errors[] = "actions[{$i}]: _type must be 'action' or 'anti-action'";
            if ($type === 'action')      $hasAction     = true;
            if ($type === 'anti-action') $hasAntiAction = true;
            if (empty($act['application'])) {
                $errors[] = "actions[{$i}]: missing 'application'"; continue;
            }
            if (!in_array($act['application'], $knownApps))
                $errors[] = "actions[{$i}]: unknown application '{$act['application']}'";
            if ($act['application'] === 'bridge' && isset($act['data']))
                if (!preg_match('/(sofia\/|user\/|loopback\/|freetdm\/)/', $act['data']))
                    $errors[] = "actions[{$i}]: bridge must contain valid endpoint (sofia/, user/, loopback/, freetdm/)";
        }
        if ($hasAntiAction && !$hasAction)
            $errors[] = "actions: has anti-action(s) but no regular action";
    }

    if (isset($body['priority']) && !is_int($body['priority']))
        $errors[] = "priority: must be an integer";

    if (isset($body['enabled']) && !is_bool($body['enabled']))
        $errors[] = "enabled: must be true or false";

    return $errors;
}

// ── DUPLICATE CHECK — extension  + context ─────────────────────
function checkDuplicate($db, $extension, $context, $excludeId = null) {
    $sql    = "SELECT COUNT(*) FROM dialplan_rules
               WHERE extension = ? AND context = ?";
    $params = array($extension, $context);
    if ($excludeId !== null) {
        $sql     .= " AND id != ?";
        $params[] = $excludeId;
    }
    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    return (int)$stmt->fetchColumn() > 0;
}

// ── RELOAD XML FROM DB ─────────────────────────────────────────────────────

function getXmlRules(PDO $db, string $context): array {
    $s = $db->prepare(
        "SELECT * FROM dialplan_rules WHERE context = ? ORDER BY priority ASC, id ASC"
    );
    $s->execute([$context]);
    return $s->fetchAll();
}

// ── RELOAD FREESWITCH ──────────────────────────────────────────────────────

function reloadFreeSWITCH(string $context): void {
    $esl = new FreeSwitchESL();
    if ($esl->connect()) {
        $esl->reloadDialplan();
        $esl->disconnect();
        writeLog('INFO', "FreeSWITCH reloadxml success | context:{$context}");
    } else {
        writeLog('WARN', "FreeSWITCH ESL failed — XML saved but reloadxml not triggered");
    }
}

// ── ATOMIC SAVE ────────────────────────────────────────────────────────────
// Flow: DB save → XML write → FS reload
// If XML write fails → undo DB change → return error

function atomicSave(PDO $db, string $context, string $operation,
                    callable $dbWork): array {
    // ── STEP 1: Save to DB ─────────────────────────────────────────────────
    try {
        $db->beginTransaction();
        $dbResult = $dbWork();
        if (!$dbResult['success']) {
            $db->rollBack();
            return $dbResult;
        }
        $db->commit();
        writeLog('INFO', "DB {$operation} success | context:{$context}");
    } catch (Throwable $e) {
        if ($db->inTransaction()) $db->rollBack();
        writeLog('ERROR', "DB {$operation} failed | context:{$context} | " . $e->getMessage());
        return ['success' => false, 'error' => 'Database error: ' . $e->getMessage()];
    }

    // ── STEP 2: Write XML ──────────────────────────────────────────────────
    $rules     = getXmlRules($db, $context);
    $xmlResult = DialplanXML::write($context, $rules);

    if (!$xmlResult['success']) {
        writeLog('ERROR', "XML write failed | context:{$context} | {$xmlResult['error']} | undoing DB change");

        // Undo DB change based on operation type
        try {
            if ($operation === 'INSERT' && isset($dbResult['id'])) {
                // Delete the record we just inserted
                $db->prepare("DELETE FROM dialplan_rules WHERE id = ?")
                   ->execute([$dbResult['id']]);
                writeLog('INFO', "DB rollback — removed inserted ID:{$dbResult['id']}");

            } elseif ($operation === 'UPDATE' && isset($dbResult['snapshot'])) {
                // Restore old values
                $snap = $dbResult['snapshot'];
                $db->prepare("UPDATE dialplan_rules SET
                    name=:name, extension=:ext, conditions=:cond,
                    actions=:act, priority=:pri, enabled=:en
                    WHERE id=:id")
                   ->execute([
                       ':name' => $snap['name'],       ':ext'  => $snap['extension'],
                       ':cond' => $snap['conditions'],  ':act'  => $snap['actions'],
                       ':pri'  => $snap['priority'],    ':en'   => $snap['enabled'],
                       ':id'   => $snap['id'],
                   ]);
                writeLog('INFO', "DB rollback — restored old values for ID:{$snap['id']}");

                // Rewrite XML with restored data
                $rules = getXmlRules($db, $context);
                DialplanXML::write($context, $rules);

            } elseif ($operation === 'DELETE' && isset($dbResult['deleted'])) {
                // Re-insert the deleted record
                $del = $dbResult['deleted'];
                $db->prepare("INSERT INTO dialplan_rules
                    (id, name, extension, conditions, actions, priority, enabled, context)
                    VALUES (:id,:name,:ext,:cond,:act,:pri,:en,:ctx)")
                   ->execute([
                       ':id'   => $del['id'],           ':name' => $del['name'],
                       ':ext'  => $del['extension'],    ':cond' => $del['conditions'],
                       ':act'  => $del['actions'],      ':pri'  => $del['priority'],
                       ':en'   => $del['enabled'],      ':ctx'  => $del['context'],
                   ]);
                writeLog('INFO', "DB rollback — re-inserted deleted ID:{$del['id']}");

                // Rewrite XML with restored data
                $rules = getXmlRules($db, $context);
                DialplanXML::write($context, $rules);

            } elseif ($operation === 'REORDER') {
                // Reorder is low risk — just log
                writeLog('WARN', "DB rollback skipped for REORDER — XML write failed");
            }
        } catch (Throwable $re) {
            writeLog('ERROR', "DB rollback failed: " . $re->getMessage());
        }

        return [
            'success' => false,
            'error'   => 'Failed to update dialplan file',
            'detail'  => $xmlResult['error']
        ];
    }

    writeLog('INFO', "XML write success | context:{$context}");

    // ── STEP 3: Reload FreeSWITCH ─────────────────────────────────────────
    reloadFreeSWITCH($context);

    return array_merge(['success' => true], $dbResult);
}

// ── ROUTING ────────────────────────────────────────────────────────────────

try {
    $db = getDB();

    // ── GET ALL ────────────────────────────────────────────────────────────
    if ($method === 'GET' && !preg_match('#/\d+$#', $uri)) {
        $params = [$context];
        $where  = "context = ?";
        if (isset($_GET['enabled'])) { $where .= " AND enabled = ?"; $params[] = (int)$_GET['enabled']; }
        if (isset($_GET['name']))    { $where .= " AND name LIKE ?"; $params[] = '%' . $_GET['name'] . '%'; }

        $stmt = $db->prepare(
            "SELECT * FROM dialplan_rules WHERE {$where} ORDER BY priority ASC, id ASC"
        );
        $stmt->execute($params);
        $rules = $stmt->fetchAll();

        foreach ($rules as &$r) {
            $r['conditions'] = json_decode($r['conditions'], true);
            $r['actions']    = json_decode($r['actions'],    true);
            $r['enabled']    = (bool)$r['enabled'];
        }

        writeLog('INFO', "GET ALL | context:{$context} | returned:" . count($rules) . " rules");
        writeSeparator();
        echo json_encode($rules);
        exit;
    }

    // ── GET SINGLE ─────────────────────────────────────────────────────────
    if ($method === 'GET' && preg_match('#/(\d+)$#', $uri)) {
        $id   = extractId($uri);
        $stmt = $db->prepare("SELECT * FROM dialplan_rules WHERE id = ? AND context = ?");
        $stmt->execute([$id, $context]);
        $rule = $stmt->fetch();

        if (!$rule) {
            writeLog('WARN', "GET | ID:{$id} not found | context:{$context}");
            writeSeparator();
            http_response_code(404);
            echo json_encode(['success' => false, 'error' => 'Rule not found']);
            exit;
        }

        $rule['conditions'] = json_decode($rule['conditions'], true);
        $rule['actions']    = json_decode($rule['actions'],    true);
        $rule['enabled']    = (bool)$rule['enabled'];

        writeLog('INFO', "GET single | ID:{$id} | context:{$context} | name:'{$rule['name']}'");
        writeSeparator();
        echo json_encode($rule);
        exit;
    }

    // ── POST REORDER ───────────────────────────────────────────────────────
    if ($method === 'POST' && str_ends_with($uri, '/reorder')) {
        $body = jsonBody();

        if (empty($body['orderedIds']) || !is_array($body['orderedIds'])) {
            writeLog('WARN', "Reorder failed — orderedIds missing | context:{$context}");
            writeSeparator();
            http_response_code(400);
            echo json_encode(['success' => false, 'error' => 'orderedIds array required']);
            exit;
        }

        $result = atomicSave($db, $context, 'REORDER', function() use ($db, $body, $context) {
            $s = $db->prepare(
                "UPDATE dialplan_rules SET priority = ? WHERE id = ? AND context = ?"
            );
            foreach ($body['orderedIds'] as $i => $id)
                $s->execute([$i + 1, (int)$id, $context]);
            return ['success' => true];
        });

        if (!$result['success']) {
            http_response_code(500);
            echo json_encode($result);
            exit;
        }

        writeLog('INFO', "REORDER success | context:{$context} | IDs:[" . implode(',', $body['orderedIds']) . "]");
        writeSeparator();
        echo json_encode(['success' => true]);
        exit;
    }

    // ── POST CREATE ────────────────────────────────────────────────────────
    if ($method === 'POST') {
        $body   = sanitizeBody(jsonBody());
        $errors = validatePayload($body);

        if (!empty($errors)) {
            writeLog('WARN', "Validation failed | context:{$context}"
                . " | name:'" . ($body['name'] ?? 'N/A') . "'"
                . " | errors: " . implode(' | ', $errors));
            writeSeparator();
            http_response_code(422);
            echo json_encode(['success' => false, 'error' => 'Validation failed', 'details' => $errors]);
            exit;
        }

        // if (checkDuplicate($db, $body['extension'], $body['conditions'], $context)) {
        if (checkDuplicate($db, $body['extension'], $context)) {
       	writeLog('WARN', "Duplicate rejected | context:{$context} | ext:'{$body['extension']}'");
            writeSeparator();
            http_response_code(409);
            echo json_encode([
                'success' => false,
                'error'   => 'Duplicate entry',
                'detail'  => "A rule with the same extension and conditions already exists in '{$context}' context"
            ]);
            exit;
        }


        $newId  = null;
        $result = atomicSave($db, $context, 'INSERT', function() use ($db, $body, $context, &$newId) {
            $s = $db->prepare("
                INSERT INTO dialplan_rules
                    (name, extension, conditions, actions, priority, enabled, context)
                VALUES
                    (:name, :ext, :cond, :act, :pri, :en, :ctx)
            ");
            $s->execute([
                ':name' => $body['name'],
                ':ext'  => $body['extension'],
                ':cond' => json_encode($body['conditions']),
                ':act'  => json_encode($body['actions']),
                ':pri'  => $body['priority'] ?? 10,
                ':en'   => isset($body['enabled']) ? (int)$body['enabled'] : 1,
                ':ctx'  => $context,
            ]);
            $newId = (int)$db->lastInsertId();
            return ['success' => true, 'id' => $newId];
        });

        if (!$result['success']) {
            writeLog('ERROR', "CREATE failed | context:{$context} | name:'{$body['name']}' | {$result['error']}");
            writeSeparator();
            http_response_code(500);
            echo json_encode($result);
            exit;
        }

        $ac = count(array_filter($body['actions'], fn($a) => ($a['_type'] ?? 'action') === 'action'));
        $aa = count(array_filter($body['actions'], fn($a) => ($a['_type'] ?? 'action') === 'anti-action'));

        writeLog('INFO', "Rule CREATED | context:{$context} | ID:{$newId}"
            . " | name:'{$body['name']}' | ext:'{$body['extension']}'"
            . " | priority:" . ($body['priority'] ?? 10)
            . " | enabled:" . ($body['enabled'] ? 'true' : 'false')
            . " | conditions:" . count($body['conditions'])
            . " | actions:{$ac} | anti-actions:{$aa}"
            . " | DB:saved | XML:updated | FS:reloaded");
        writeSeparator();
        http_response_code(201);
        echo json_encode(['success' => true, 'id' => $newId]);
        exit;
    }

    // ── PUT UPDATE ─────────────────────────────────────────────────────────
    if ($method === 'PUT') {
        $id = extractId($uri);
        if (!$id) {
            writeLog('WARN', "Update failed — no ID | context:{$context}");
            writeSeparator();
            http_response_code(400);
            echo json_encode(['success' => false, 'error' => 'Rule ID required']);
            exit;
        }

        // Check rule exists
        $check = $db->prepare("SELECT id FROM dialplan_rules WHERE id = ? AND context = ?");
        $check->execute([$id, $context]);
        if (!$check->fetch()) {
            writeLog('WARN', "Update failed — ID:{$id} not found | context:{$context}");
            writeSeparator();
            http_response_code(404);
            echo json_encode(['success' => false, 'error' => 'Rule not found']);
            exit;
        }

        $body   = sanitizeBody(jsonBody());
        $errors = validatePayload($body);

        if (!empty($errors)) {
            writeLog('WARN', "Validation failed on UPDATE | context:{$context} | ID:{$id}"
                . " | errors: " . implode(' | ', $errors));
            writeSeparator();
            http_response_code(422);
            echo json_encode(['success' => false, 'error' => 'Validation failed', 'details' => $errors]);
            exit;
        }
/*
        if (checkDuplicate($db, $body['extension'], $body['conditions'], $context, $id)) {
            writeLog('WARN', "Duplicate on UPDATE | context:{$context} | ID:{$id} | ext:'{$body['extension']}'");
            writeSeparator();
            http_response_code(409);
            echo json_encode([
                'success' => false,
                'error'   => 'Duplicate entry',
                'detail'  => "Another rule with the same extension and conditions already exists in '{$context}' context"
            ]);
            exit;
        }
 */
        $result = atomicSave($db, $context, 'UPDATE', function() use ($db, $body, $id, $context) {
            // Fetch current record for rollback snapshot
            $snap = $db->prepare("SELECT * FROM dialplan_rules WHERE id = ? AND context = ?");
            $snap->execute([$id, $context]);
            $snapshot = $snap->fetch();

            $s = $db->prepare("
                UPDATE dialplan_rules SET
                    name       = :name,
                    extension  = :ext,
                    conditions = :cond,
                    actions    = :act,
                    priority   = :pri,
                    enabled    = :en
                WHERE id = :id AND context = :ctx
            ");
            $s->execute([
                ':name' => $body['name'],
                ':ext'  => $body['extension'],
                ':cond' => json_encode($body['conditions']),
                ':act'  => json_encode($body['actions']),
                ':pri'  => $body['priority'] ?? 10,
                ':en'   => isset($body['enabled']) ? (int)$body['enabled'] : 1,
                ':id'   => $id,
                ':ctx'  => $context,
            ]);
            return ['success' => true, 'snapshot' => $snapshot];
        });

        if (!$result['success']) {
            writeLog('ERROR', "UPDATE failed | context:{$context} | ID:{$id} | {$result['error']}");
            writeSeparator();
            http_response_code(500);
            echo json_encode($result);
            exit;
        }

        $ac = count(array_filter($body['actions'], fn($a) => ($a['_type'] ?? 'action') === 'action'));
        $aa = count(array_filter($body['actions'], fn($a) => ($a['_type'] ?? 'action') === 'anti-action'));

        writeLog('INFO', "Rule UPDATED | context:{$context} | ID:{$id}"
            . " | name:'{$body['name']}' | ext:'{$body['extension']}'"
            . " | priority:" . ($body['priority'] ?? 10)
            . " | enabled:" . ($body['enabled'] ? 'true' : 'false')
            . " | conditions:" . count($body['conditions'])
            . " | actions:{$ac} | anti-actions:{$aa}"
            . " | DB:saved | XML:updated | FS:reloaded");
        writeSeparator();
        echo json_encode(['success' => true]);
        exit;
    }

    // ── DELETE ─────────────────────────────────────────────────────────────
    if ($method === 'DELETE') {
        $id = extractId($uri);
        if (!$id) {
            writeLog('WARN', "Delete failed — no ID | context:{$context}");
            writeSeparator();
            http_response_code(400);
            echo json_encode(['success' => false, 'error' => 'Rule ID required']);
            exit;
        }

        $fetch = $db->prepare("SELECT * FROM dialplan_rules WHERE id = ? AND context = ?");
        $fetch->execute([$id, $context]);
        $existing = $fetch->fetch();

        if (!$existing) {
            writeLog('WARN', "Delete failed — ID:{$id} not found | context:{$context}");
            writeSeparator();
            http_response_code(404);
            echo json_encode(['success' => false, 'error' => 'Rule not found']);
            exit;
        }

        $result = atomicSave($db, $context, 'DELETE', function() use ($db, $id, $context, $existing) {
            $db->prepare("DELETE FROM dialplan_rules WHERE id = ? AND context = ?")
               ->execute([$id, $context]);
            return ['success' => true, 'deleted' => $existing];
        });

        if (!$result['success']) {
            writeLog('ERROR', "DELETE failed | context:{$context} | ID:{$id} | {$result['error']}");
            writeSeparator();
            http_response_code(500);
            echo json_encode($result);
            exit;
        }

        writeLog('INFO', "Rule DELETED | context:{$context} | ID:{$id}"
            . " | name:'{$existing['name']}' | ext:'{$existing['extension']}'"
            . " | DB:deleted | XML:updated | FS:reloaded");
        writeSeparator();
        echo json_encode(['success' => true]);
        exit;
    }

    writeLog('WARN', "Method not allowed: {$method} | context:{$context}");
    writeSeparator();
    http_response_code(405);
    echo json_encode(['success' => false, 'error' => 'Method Not Allowed']);

} catch (Throwable $e) {
    writeLog('ERROR', "Exception: " . $e->getMessage()
        . " | file:" . $e->getFile()
        . " | line:" . $e->getLine());
    writeSeparator();
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => $e->getMessage()]);
}
