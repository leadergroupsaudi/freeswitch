<?php
ob_start();
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../lib/FreeSwitchESL.php';
require_once __DIR__ . '/../../lib/VarsXML.php';
require_once __DIR__ . '/../../lib/Auth.php';

header('Content-Type: application/json');
authenticateRequest();

$method = $_SERVER['REQUEST_METHOD'];
$uri    = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

$varId  = null;
$isBulk = false;

if (preg_match('#/fs-vars/bulk#', $uri)) {
    $isBulk = true;
} elseif (preg_match('#/fs-vars/(\d+)#', $uri, $m)) {
    $varId = (int)$m[1];
}

// ── HELPERS ────────────────────────────────────────────────────────────────

function jsonBody() {
    $data = json_decode(file_get_contents('php://input'), true);
    return is_array($data) ? $data : array();
}

function sendError($code, $message, $details = null) {
    ob_clean();
    http_response_code($code);
    $resp = array('success' => false, 'error' => $message);
    if ($details) $resp['details'] = $details;
    echo json_encode($resp);
    ob_end_flush();
    exit;
}

function sendSuccess($data = array(), $code = 200) {
    ob_clean();
    http_response_code($code);
    echo json_encode(array_merge(array('success' => true), $data));
    ob_end_flush();
    exit;
}

function maskVar($var) {
    if ($var['is_sensitive']) $var['var_value'] = '********';
    $var['is_sensitive'] = (bool)$var['is_sensitive'];
    $var['editable']     = (bool)$var['editable'];
    return $var;
}

function getAllowedCategories() {
    return array(
        'network', 'security', 'sip_ports', 'tls',
        'codecs', 'caller_id', 'general', 'video',
        'provider', 'xmpp', 'ringtones', 'readonly',
    );
}

function getAllowedCmds() {
    return array('set', 'stun-set', 'exec-set', 'load', 'preprocess');
}

function groupByCategory($rows) {
    $order = array(
        'network'   => array(),
        'security'  => array(),
        'sip_ports' => array(),
        'tls'       => array(),
        'codecs'    => array(),
        'caller_id' => array(),
        'general'   => array(),
        'video'     => array(),
        'provider'  => array(),
        'xmpp'      => array(),
        'ringtones' => array(),
        'readonly'  => array(),
    );
    foreach ($rows as $row) {
        $cat = isset($order[$row['category']]) ? $row['category'] : 'general';
        $order[$cat][] = maskVar($row);
    }
    foreach ($order as $k => $v) {
        if (empty($v)) unset($order[$k]);
    }
    return $order;
}

// ── CATEGORY-AWARE RELOAD ──────────────────────────────────────────────────

function reloadByCategories($categories) {
    $categories = array_unique(array_filter($categories, function($c) {
        return $c !== 'readonly';
    }));

    $eslCommands = array();
    $reloadLog   = array();

    $eslCommands[] = array('cmd' => 'api reloadxml', 'label' => 'reloadxml');

    foreach ($categories as $cat) {
        switch ($cat) {
            case 'network':
            case 'sip_ports':
            case 'tls':
                $eslCommands[] = array('cmd' => 'api sofia profile external restart', 'label' => 'sofia profile external restart');
                $eslCommands[] = array('cmd' => 'api sofia profile internal restart', 'label' => 'sofia profile internal restart');
                break;
            case 'codecs':
                $eslCommands[] = array('cmd' => 'api reload mod_sofia', 'label' => 'reload mod_sofia');
                break;
            case 'security':
                $eslCommands[] = array('cmd' => 'api reloadacl',        'label' => 'reloadacl');
                $eslCommands[] = array('cmd' => 'api reload mod_sofia', 'label' => 'reload mod_sofia');
                break;
        }
    }

    $seen = array(); $uniqueCmds = array();
    foreach ($eslCommands as $c) {
        if (!in_array($c['cmd'], $seen)) {
            $seen[] = $c['cmd']; $uniqueCmds[] = $c;
        }
    }

    try {
        $esl = new FreeSwitchESL();
        if (!$esl->connect()) {
            writeLog('WARN', "ESL failed — no reload triggered");
            return array('success' => false, 'error' => 'ESL connection failed', 'commands' => array());
        }
        foreach ($uniqueCmds as $c) {
            $response    = $esl->sendCommand($c['cmd']);
            $reloadLog[] = array(
                'command'  => $c['label'],
                'response' => trim($response),
                'success'  => (strpos($response, '+OK')        !== false ||
                               strpos($response, 'Reloading')  !== false ||
                               strpos($response, 'Restarting') !== false),
            );
            writeLog('INFO', "ESL: {$c['label']} | " . trim($response));
            usleep(300000);
        }
        $esl->disconnect();
        return array('success' => true, 'commands' => $reloadLog);
    } catch (Exception $e) {
        writeLog('WARN', "ESL exception: " . $e->getMessage());
        return array('success' => false, 'error' => $e->getMessage(), 'commands' => $reloadLog);
    }
}

// ── FREESWITCH FULL RESTART ────────────────────────────────────────────────
// X-PRE-PROCESS vars are only read at startup.
// A full restart is REQUIRED after DELETE for removal to take effect.

function restartFreeSwitch() {
    $log = array();

    // ── Method 1: Graceful ESL restart ────────────────────────────────────
    try {
        $esl = new FreeSwitchESL();
        if ($esl->connect()) {

            // "elegant" waits for active calls to finish before restarting
            $response = $esl->sendCommand('api fsctl shutdown restart elegant');
            $log[]    = array(
                'command'  => 'fsctl shutdown restart elegant',
                'response' => trim($response),
                'success'  => (strpos($response, '+OK') !== false),
            );
            writeLog('INFO', "ESL: fsctl shutdown restart elegant | " . trim($response));
            $esl->disconnect();

            // Wait up to 20 seconds for FreeSWITCH to come back up
            $waited = 0;
            while ($waited < 20) {
                sleep(2);
                $waited += 2;
                try {
                    $check = new FreeSwitchESL();
                    if ($check->connect()) {
                        $check->disconnect();
                        $log[] = array(
                            'command'  => 'health_check',
                            'response' => "FreeSWITCH back online after {$waited}s",
                            'success'  => true,
                        );
                        writeLog('INFO', "FreeSWITCH restarted successfully after {$waited}s");
                        return array(
                            'success'  => true,
                            'method'   => 'esl_elegant_restart',
                            'commands' => $log,
                        );
                    }
                } catch (Exception $ignore) {
                    // Still restarting — keep waiting
                }
            }

            // Restart was issued but health check timed out — still likely ok
            $log[] = array(
                'command'  => 'health_check',
                'response' => 'Timed out waiting for FreeSWITCH — it may still be starting up',
                'success'  => false,
            );
            return array(
                'success'  => true,
                'method'   => 'esl_elegant_restart',
                'commands' => $log,
                'note'     => 'Restart issued but health check timed out. FreeSWITCH may still be coming up.',
            );
        }
    } catch (Exception $e) {
        writeLog('WARN', "ESL restart failed, falling back to systemctl | " . $e->getMessage());
        $log[] = array(
            'command'  => 'fsctl shutdown restart elegant',
            'response' => 'ESL unavailable: ' . $e->getMessage(),
            'success'  => false,
        );
    }

    // ── Method 2: systemctl restart ───────────────────────────────────────
    $output   = array();
    $exitCode = 0;
    exec('sudo systemctl restart freeswitch 2>&1', $output, $exitCode);
    $log[] = array(
        'command'  => 'systemctl restart freeswitch',
        'response' => implode("\n", $output),
        'success'  => ($exitCode === 0),
    );

    if ($exitCode === 0) {
        writeLog('INFO', "FreeSWITCH restarted via systemctl");
        return array('success' => true, 'method' => 'systemctl', 'commands' => $log);
    }

    // ── Method 3: service restart (last resort) ────────────────────────────
    $output2   = array();
    $exitCode2 = 0;
    exec('sudo service freeswitch restart 2>&1', $output2, $exitCode2);
    $log[] = array(
        'command'  => 'service freeswitch restart',
        'response' => implode("\n", $output2),
        'success'  => ($exitCode2 === 0),
    );

    writeLog($exitCode2 === 0 ? 'INFO' : 'ERROR',
        "FreeSWITCH service restart | exit:{$exitCode2}");

    return array(
        'success'  => ($exitCode2 === 0),
        'method'   => 'service',
        'commands' => $log,
    );
}

// ── SYNC FROM XML ──────────────────────────────────────────────────────────

function syncFromXML($db, &$rows) {
    $xmlRead = VarsXML::read();
    if (!$xmlRead['success']) return;
    $xmlVars = $xmlRead['vars'];
    foreach ($rows as &$row) {
        if (isset($xmlVars[$row['var_name']]) && $row['editable']) {
            $xmlVal = $xmlVars[$row['var_name']]['value'];
            if ($row['var_value'] !== $xmlVal) {
                $db->prepare("UPDATE freeswitch_vars SET var_value=? WHERE id=?")
                   ->execute(array($xmlVal, $row['id']));
                $row['var_value'] = $xmlVal;
            }
        }
    }
    unset($row);
}

function validateVarName($name) {
    return preg_match('/^[a-zA-Z_][a-zA-Z0-9_\-\.]*$/', $name);
}

// ══════════════════════════════════════════════════════════════════════════
//  ROUTING
// ══════════════════════════════════════════════════════════════════════════

try {
    $db = getDB();

    // ── GET /api/admin/fs-vars ─────────────────────────────────────────────
    if ($method === 'GET' && !$varId && !$isBulk) {
        $stmt = $db->query("SELECT * FROM freeswitch_vars ORDER BY category ASC, id ASC");
        $rows = $stmt->fetchAll();
        syncFromXML($db, $rows);

        $grouped = groupByCategory($rows);
        $totals  = array();
        foreach ($grouped as $cat => $items) $totals[$cat] = count($items);

        writeLog('INFO', "FS-VARS GET ALL — " . count($rows) . " variables");
        writeSeparator();
        sendSuccess(array(
            'total'      => count($rows),
            'categories' => array_keys($grouped),
            'totals'     => $totals,
            'grouped'    => $grouped,
        ));
    }

    // ── GET /api/admin/fs-vars/:id ─────────────────────────────────────────
    if ($method === 'GET' && $varId && !$isBulk) {
        $stmt = $db->prepare("SELECT * FROM freeswitch_vars WHERE id = ?");
        $stmt->execute(array($varId));
        $row = $stmt->fetch();
        if (!$row) sendError(404, 'Variable not found');

        $xmlRead = VarsXML::read();
        if ($xmlRead['success'] && isset($xmlRead['vars'][$row['var_name']]) && $row['editable']) {
            $xmlVal = $xmlRead['vars'][$row['var_name']]['value'];
            if ($row['var_value'] !== $xmlVal) {
                $db->prepare("UPDATE freeswitch_vars SET var_value=? WHERE id=?")
                   ->execute(array($xmlVal, $row['id']));
                $row['var_value'] = $xmlVal;
            }
        }

        writeLog('INFO', "FS-VAR GET | ID:{$varId} | name:'{$row['var_name']}'");
        writeSeparator();
        sendSuccess(array('data' => maskVar($row)));
    }

    // ── POST /api/admin/fs-vars ── create ──────────────────────────────────
    if ($method === 'POST' && !$varId && !$isBulk) {
        $body   = jsonBody();
        $errors = array();

        if (empty($body['var_name']))   $errors[] = "var_name is required";
        if (!isset($body['var_value'])) $errors[] = "var_value is required";

        if (!empty($body['var_name']) && !validateVarName($body['var_name']))
            $errors[] = "var_name: only letters, numbers, underscores, hyphens, dots — must start with letter or underscore";

        if (!empty($body['cmd']) && !in_array($body['cmd'], getAllowedCmds()))
            $errors[] = "cmd: must be one of " . implode(', ', getAllowedCmds());

        if (!empty($body['category']) && !in_array($body['category'], getAllowedCategories()))
            $errors[] = "category: must be one of " . implode(', ', getAllowedCategories());

        if (!empty($body['category']) && $body['category'] === 'readonly')
            $errors[] = "category: cannot create variables in 'readonly' category";

        if (!empty($errors)) sendError(422, 'Validation failed', $errors);

        $dup = $db->prepare("SELECT COUNT(*) FROM freeswitch_vars WHERE var_name = ?");
        $dup->execute(array($body['var_name']));
        if ((int)$dup->fetchColumn() > 0)
            sendError(409, 'Duplicate entry', array("Variable '{$body['var_name']}' already exists"));

        $varName     = $body['var_name'];
        $varValue    = $body['var_value'];
        $cmd         = isset($body['cmd'])          ? $body['cmd']               : 'set';
        $description = isset($body['description'])  ? $body['description']       : '';
        $isSensitive = isset($body['is_sensitive'])  ? (int)$body['is_sensitive'] : 0;
        $editable    = isset($body['editable'])      ? (int)$body['editable']     : 1;
        $category    = isset($body['category'])      ? $body['category']          : 'general';
        $updatedBy   = isset($body['updated_by'])    ? $body['updated_by']        : 'admin';

        $newId = null;
        try {
            $s = $db->prepare("INSERT INTO freeswitch_vars
                (var_name, var_value, cmd, description, is_sensitive, editable, category, updated_by)
                VALUES (:name,:val,:cmd,:desc,:sens,:edit,:cat,:by)");
            $s->execute(array(
                ':name' => $varName,     ':val'  => $varValue,
                ':cmd'  => $cmd,         ':desc' => $description,
                ':sens' => $isSensitive, ':edit' => $editable,
                ':cat'  => $category,    ':by'   => $updatedBy,
            ));
            $newId = (int)$db->lastInsertId();
        } catch (Exception $e) {
            sendError(500, 'Database error: ' . $e->getMessage());
        }

        $xmlResult = VarsXML::write(array($varName => array('value' => $varValue, 'cmd' => $cmd)));
        if (!$xmlResult['success']) {
            $db->prepare("DELETE FROM freeswitch_vars WHERE id = ?")->execute(array($newId));
            writeLog('ERROR', "FS-VAR CREATE XML failed — rolled back | {$varName}");
            sendError(500, 'Failed to write vars.xml — DB rolled back', array($xmlResult['error']));
        }

        $reloadResult = reloadByCategories(array($category));

        writeLog('INFO', "FS-VAR CREATED | ID:{$newId} | name:'{$varName}' | category:'{$category}'");
        writeSeparator();

        sendSuccess(array(
            'id'       => $newId,
            'var_name' => $varName,
            'category' => $category,
            'reload'   => $reloadResult,
        ), 201);
    }

    // ── PUT /api/admin/fs-vars/:id ── update ───────────────────────────────
    if ($method === 'PUT' && $varId && !$isBulk) {
        $stmt = $db->prepare("SELECT * FROM freeswitch_vars WHERE id = ?");
        $stmt->execute(array($varId));
        $existing = $stmt->fetch();
        if (!$existing) sendError(404, 'Variable not found');

        if (!$existing['editable'])
            sendError(403, 'Variable is read-only',
                array("'{$existing['var_name']}' is auto-calculated by FreeSWITCH"));

        $body   = jsonBody();
        $errors = array();

        if (!isset($body['var_value'])) $errors[] = "var_value is required";

        if (!empty($body['cmd']) && !in_array($body['cmd'], getAllowedCmds()))
            $errors[] = "cmd: must be one of " . implode(', ', getAllowedCmds());

        if (!empty($body['category']) && !in_array($body['category'], getAllowedCategories()))
            $errors[] = "category: must be one of " . implode(', ', getAllowedCategories());

        if (!empty($body['category']) && $body['category'] === 'readonly')
            $errors[] = "category: cannot move variable to 'readonly' category";

        if (!empty($errors)) sendError(422, 'Validation failed', $errors);

        $newValue     = $body['var_value'];
        $newCmd       = isset($body['cmd'])          ? $body['cmd']               : $existing['cmd'];
        $newDesc      = isset($body['description'])  ? $body['description']       : $existing['description'];
        $newSensitive = isset($body['is_sensitive'])  ? (int)$body['is_sensitive'] : $existing['is_sensitive'];
        $newCategory  = isset($body['category'])      ? $body['category']          : $existing['category'];
        $updatedBy    = isset($body['updated_by'])    ? $body['updated_by']        : 'admin';

        try {
            $db->prepare("UPDATE freeswitch_vars SET
                var_value=:val, cmd=:cmd, description=:desc,
                is_sensitive=:sens, category=:cat, updated_by=:by WHERE id=:id")
               ->execute(array(
                   ':val'  => $newValue,    ':cmd'  => $newCmd,
                   ':desc' => $newDesc,     ':sens' => $newSensitive,
                   ':cat'  => $newCategory, ':by'   => $updatedBy,
                   ':id'   => $varId,
               ));
        } catch (Exception $e) {
            sendError(500, 'Database error: ' . $e->getMessage());
        }

        $xmlResult = VarsXML::write(array(
            $existing['var_name'] => array('value' => $newValue, 'cmd' => $newCmd)
        ));
        if (!$xmlResult['success']) {
            $db->prepare("UPDATE freeswitch_vars SET
                var_value=:val, cmd=:cmd, description=:desc,
                is_sensitive=:sens, category=:cat WHERE id=:id")
               ->execute(array(
                   ':val'  => $existing['var_value'],   ':cmd'  => $existing['cmd'],
                   ':desc' => $existing['description'], ':sens' => $existing['is_sensitive'],
                   ':cat'  => $existing['category'],    ':id'   => $varId,
               ));
            writeLog('ERROR', "FS-VAR XML failed — rolled back | {$existing['var_name']}");
            sendError(500, 'Failed to write vars.xml — DB rolled back', array($xmlResult['error']));
        }

        $reloadResult = reloadByCategories(array_unique(array($existing['category'], $newCategory)));

        writeLog('INFO', "FS-VAR UPDATED | ID:{$varId} | name:'{$existing['var_name']}' | category:'{$newCategory}'");
        writeSeparator();

        sendSuccess(array(
            'id'       => $varId,
            'var_name' => $existing['var_name'],
            'category' => $newCategory,
            'reload'   => $reloadResult,
        ));
    }

    // ── DELETE /api/admin/fs-vars/:id ── delete + restart ──────────────────
    if ($method === 'DELETE' && $varId && !$isBulk) {
        $stmt = $db->prepare("SELECT * FROM freeswitch_vars WHERE id = ?");
        $stmt->execute(array($varId));
        $existing = $stmt->fetch();
        if (!$existing) sendError(404, 'Variable not found');

        if (!$existing['editable'])
            sendError(403, 'Cannot delete read-only variable',
                array("'{$existing['var_name']}' is a system variable and cannot be deleted"));

        // STEP 1: Remove from vars.xml FIRST (before DB delete for safety)
        $xmlResult = VarsXML::delete($existing['var_name']);
        if (!$xmlResult['success']) {
            // Non-fatal — var may already be absent from XML
            writeLog('WARN', "vars.xml delete skipped for '{$existing['var_name']}': " . $xmlResult['error']);
        } else {
            writeLog('INFO', "vars.xml: removed '{$existing['var_name']}'");
        }

        // STEP 2: Delete from DB
        try {
            $db->prepare("DELETE FROM freeswitch_vars WHERE id = ?")->execute(array($varId));
        } catch (Exception $e) {
            sendError(500, 'Database error: ' . $e->getMessage());
        }

        // STEP 3: Full FreeSWITCH restart
        // ─────────────────────────────────────────────────────────────────
        // WHY FULL RESTART?
        // X-PRE-PROCESS directives in vars.xml are evaluated ONLY at startup.
        // reloadxml does NOT re-evaluate X-PRE-PROCESS lines.
        // The variable will remain active in memory until FreeSWITCH restarts.
        // ─────────────────────────────────────────────────────────────────
        writeLog('INFO', "DELETE triggered full restart | var:'{$existing['var_name']}'");
        $restartResult = restartFreeSwitch();

        writeLog('INFO', "FS-VAR DELETE COMPLETE | ID:{$varId}"
            . " | name:'{$existing['var_name']}'"
            . " | restart_method:'" . (isset($restartResult['method']) ? $restartResult['method'] : 'unknown') . "'"
            . " | restart_success:" . ($restartResult['success'] ? 'true' : 'false'));
        writeSeparator();

        sendSuccess(array(
            'id'       => $varId,
            'var_name' => $existing['var_name'],
            'category' => $existing['category'],
            'xml'      => $xmlResult,
            'restart'  => $restartResult,
            'note'     => 'FreeSWITCH was restarted. X-PRE-PROCESS variables require a full restart to be removed from memory.',
        ));
    }

    // ── POST /api/admin/fs-vars/bulk ── update multiple ────────────────────
    if ($method === 'POST' && $isBulk) {
        $body = jsonBody();

        if (empty($body['updates']) || !is_array($body['updates']))
            sendError(422, 'Validation failed', array("updates array is required"));

        $updatedBy     = isset($body['updated_by']) ? $body['updated_by'] : 'admin';
        $errors        = array();
        $toUpdate      = array();
        $dbUpdates     = array();
        $categoriesHit = array();

        foreach ($body['updates'] as $i => $item) {
            if (empty($item['id']))         { $errors[] = "updates[{$i}]: id is required";        continue; }
            if (!isset($item['var_value'])) { $errors[] = "updates[{$i}]: var_value is required"; continue; }

            $stmt = $db->prepare("SELECT * FROM freeswitch_vars WHERE id = ?");
            $stmt->execute(array((int)$item['id']));
            $var = $stmt->fetch();

            if (!$var)             { $errors[] = "updates[{$i}]: ID:{$item['id']} not found";       continue; }
            if (!$var['editable']) { $errors[] = "updates[{$i}]: '{$var['var_name']}' is read-only"; continue; }

            $newCmd = isset($item['cmd']) ? $item['cmd'] : $var['cmd'];
            $toUpdate[$var['var_name']] = array('value' => $item['var_value'], 'cmd' => $newCmd);
            $dbUpdates[(int)$item['id']] = array(
                'name'      => $var['var_name'],
                'old'       => $var['var_value'],
                'new'       => $item['var_value'],
                'cmd'       => $newCmd,
                'sensitive' => $var['is_sensitive'],
                'category'  => $var['category'],
            );
            $categoriesHit[] = $var['category'];
        }

        if (!empty($errors)) sendError(422, 'Validation failed', $errors);
        if (empty($toUpdate)) sendError(422, 'No valid updates provided');

        try {
            $db->beginTransaction();
            $s = $db->prepare("UPDATE freeswitch_vars SET var_value=:val, updated_by=:by WHERE id=:id");
            foreach ($dbUpdates as $id => $info)
                $s->execute(array(':val' => $info['new'], ':by' => $updatedBy, ':id' => $id));
            $db->commit();
        } catch (Exception $e) {
            if ($db->inTransaction()) $db->rollBack();
            sendError(500, 'Database error: ' . $e->getMessage());
        }

        $xmlResult = VarsXML::write($toUpdate);
        if (!$xmlResult['success']) {
            try {
                $db->beginTransaction();
                $s = $db->prepare("UPDATE freeswitch_vars SET var_value=:val WHERE id=:id");
                foreach ($dbUpdates as $id => $info)
                    $s->execute(array(':val' => $info['old'], ':id' => $id));
                $db->commit();
            } catch (Exception $re) {
                writeLog('ERROR', "Bulk rollback failed: " . $re->getMessage());
            }
            sendError(500, 'Failed to write vars.xml — DB rolled back', array($xmlResult['error']));
        }

        $uniqueCategories = array_values(array_unique($categoriesHit));
        $reloadResult     = reloadByCategories($uniqueCategories);

        $summary = array();
        foreach ($dbUpdates as $id => $info) {
            $summary[] = array(
                'id'        => $id,
                'var_name'  => $info['name'],
                'category'  => $info['category'],
                'cmd'       => $info['cmd'],
                'in_xml'    => in_array($info['name'], $xmlResult['updated']),
                'new_value' => $info['sensitive'] ? '********' : $info['new'],
            );
        }

        writeLog('INFO', "FS-VARS BULK | vars:" . count($dbUpdates)
            . " | categories:[" . implode(',', $uniqueCategories) . "]");
        writeSeparator();

        sendSuccess(array(
            'updated_count'  => count($dbUpdates),
            'categories_hit' => $uniqueCategories,
            'xml_updated'    => $xmlResult['updated'],
            'xml_appended'   => isset($xmlResult['appended']) ? $xmlResult['appended'] : array(),
            'reload'         => $reloadResult,
            'summary'        => $summary,
        ));
    }

    sendError(405, 'Method Not Allowed');

} catch (Exception $e) {
    writeLog('ERROR', "FS-VARS Exception: " . $e->getMessage()
        . " | file:" . $e->getFile() . " | line:" . $e->getLine());
    writeSeparator();
    sendError(500, $e->getMessage());
}
