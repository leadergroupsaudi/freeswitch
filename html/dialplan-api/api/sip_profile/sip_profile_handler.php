<?php
// Prevent any output buffering issues
while (ob_get_level()) ob_end_clean();

// Error handling — log don't display
ini_set('display_errors', '0');
ini_set('log_errors',     '1');
error_reporting(E_ALL);

require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../lib/FreeSwitchESL.php';
require_once __DIR__ . '/../../lib/SipProfileXML.php';
require_once __DIR__ . '/../../lib/Auth.php';

header('Content-Type: application/json');
header('Cache-Control: no-cache');

// ── AUTH ───────────────────────────────────────────────────────────────────
authenticateRequest();

// ── RESPONSE HELPERS ───────────────────────────────────────────────────────

function respond($code, $data) {
    http_response_code($code);
    echo json_encode($data);
    exit;
}

function ok($data = array(), $code = 200) {
    respond($code, array_merge(array('success' => true), $data));
}

function fail($code, $msg, $details = null) {
    $r = array('success' => false, 'error' => $msg);
    if ($details) $r['details'] = $details;
    respond($code, $r);
}

// ── REQUEST ────────────────────────────────────────────────────────────────

$method = $_SERVER['REQUEST_METHOD'];
$uri    = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

function jbody() {
    $d = json_decode(file_get_contents('php://input'), true);
    return is_array($d) ? $d : array();
}

// ── ROUTE MATCHING ─────────────────────────────────────────────────────────

$profileId = null;
$paramId   = null;
$action    = null; // params | restart | status | bulk

if (preg_match('#/sip-profiles/(\d+)/params/bulk$#', $uri, $m)) {
    $profileId = (int)$m[1]; $action = 'bulk';
} elseif (preg_match('#/sip-profiles/(\d+)/params/(\d+)$#', $uri, $m)) {
    $profileId = (int)$m[1]; $paramId = (int)$m[2]; $action = 'params';
} elseif (preg_match('#/sip-profiles/(\d+)/params$#', $uri, $m)) {
    $profileId = (int)$m[1]; $action = 'params';
} elseif (preg_match('#/sip-profiles/(\d+)/restart$#', $uri, $m)) {
    $profileId = (int)$m[1]; $action = 'restart';
} elseif (preg_match('#/sip-profiles/(\d+)/status$#', $uri, $m)) {
    $profileId = (int)$m[1]; $action = 'status';
} elseif (preg_match('#/sip-profiles/(\d+)$#', $uri, $m)) {
    $profileId = (int)$m[1]; $action = 'profile';
} elseif (preg_match('#/sip-profiles$#', $uri)) {
    $action = 'list';
}

writeLog('INFO', "SIP-PROFILE | method:{$method} uri:{$uri}"
    . " | action:{$action} profile_id:" . ($profileId ?? 'null'));

// ── HELPERS ────────────────────────────────────────────────────────────────

function getAllowedCategories() {
    return array('network','codecs','tls','registration','session','dtmf','srtp','general');
}

function maskParam($p) {
    if ($p['is_sensitive']) $p['param_value'] = '********';
    $p['is_sensitive'] = (bool)$p['is_sensitive'];
    $p['editable']     = (bool)$p['editable'];
    return $p;
}

function groupParams($rows) {
    $out = array(
        'network'      => array(),
        'codecs'       => array(),
        'tls'          => array(),
        'registration' => array(),
        'session'      => array(),
        'dtmf'         => array(),
        'srtp'         => array(),
        'general'      => array(),
    );
    foreach ($rows as $p) {
        $cat = isset($out[$p['category']]) ? $p['category'] : 'general';
        $out[$cat][] = maskParam($p);
    }
    foreach ($out as $k => $v) { if (empty($v)) unset($out[$k]); }
    return $out;
}

function getProfile($db, $id) {
    $s = $db->prepare("SELECT * FROM sip_profiles WHERE id=?");
    $s->execute(array($id));
    return $s->fetch();
}

function getProfileParams($db, $profileId, $category = null) {
    $where  = "profile_id=?";
    $params = array($profileId);
    if ($category && in_array($category, getAllowedCategories())) {
        $where   .= " AND category=?";
        $params[] = $category;
    }
    $s = $db->prepare(
        "SELECT * FROM sip_profile_params WHERE {$where} ORDER BY category, id ASC"
    );
    $s->execute($params);
    return $s->fetchAll();
}

function safeReload($profileName) {
    try {
        $r = FreeSwitchESL::run(function($esl) use ($profileName) {
            return $esl->sofiaProfileRescan($profileName);
        });
        writeLog('INFO', "sofia rescan {$profileName}: "
            . (isset($r['response']) ? $r['response'] : 'no response'));
        return $r;
    } catch (Exception $e) {
        writeLog('WARN', "ESL reload failed: " . $e->getMessage());
        return array(
            'success' => false,
            'warning' => 'DB+XML saved. ESL failed: ' . $e->getMessage(),
        );
    }
}

function getDefaultParams($overrides = array()) {
    $d = array(
        'network' => array(
            'sip-ip'               => '$${local_ip_v4}',
            'sip-port'             => '5090',
            'rtp-ip'               => '$${local_ip_v4}',
            'ext-rtp-ip'           => '$${external_rtp_ip}',
            'ext-sip-ip'           => '$${external_sip_ip}',
            'rtp-timeout-sec'      => '300',
            'rtp-hold-timeout-sec' => '1800',
            'local-network-acl'    => 'localnet.auto',
            'apply-nat-acl'        => 'nat.auto',
            'ws-binding'           => ':5066',
            'wss-binding'          => ':7443',
        ),
        'codecs' => array(
            'inbound-codec-prefs'       => 'PCMU,PCMA,G722,G729',
            'outbound-codec-prefs'      => 'PCMU,PCMA,G722,G729',
            'inbound-codec-negotiation' => 'generous',
            'codec-prefs'               => 'PCMU,PCMA,G722,G729',
            'inbound-late-negotiation'  => 'true',
        ),
        'tls' => array(
            'tls'               => 'false',
            'tls-only'          => 'false',
            'tls-bind-params'   => 'transport=tls',
            'tls-sip-port'      => '5091',
            'tls-cert-dir'      => '$${certs_dir}',
            'tls-ca-cert'       => '$${certs_dir}/cafile.pem',
            'tls-cert'          => '$${certs_dir}/agent.pem',
            'tls-version'       => 'tlsv1.2',
            'tls-ciphers'       => 'ALL:!ADH:!LOW:!EXP:!MD5:@STRENGTH',
            'tls-verify-date'   => 'true',
            'tls-verify-policy' => 'none',
        ),
        'registration' => array(
            'max-registrations-per-extension' => '1',
            'accept-blind-reg'                => 'false',
            'accept-blind-auth'               => 'false',
            'auth-calls'                      => 'false',
            'auth-all-packets'                => 'false',
            'log-auth-failures'               => 'true',
            'force-register-domain'           => '$${domain}',
            'force-register-db-domain'        => '$${domain}',
            'force-subscription-domain'       => '$${domain}',
            'nonce-ttl'                       => '60',
            'challenge-realm'                 => 'auto_from',
        ),
        'session' => array(
            'enable-timer'            => 'false',
            'session-timeout'         => '1800',
            'min-session-expires'     => '120',
            'minimum-session-expires' => '120',
        ),
        'dtmf' => array(
            'dtmf-duration' => '2000',
            'rfc2833-pt'    => '101',
            'dtmf-type'     => 'rfc2833',
        ),
        'srtp' => array(
            'rtp-secure-media'          => 'optional',
            'rtp-secure-media-inbound'  => 'optional',
            'rtp-secure-media-outbound' => 'optional',
        ),
        'general' => array(
            'context'           => 'public',
            'dialplan'          => 'XML',
            'hold-music'        => '$${hold_music}',
            'apply-inbound-acl' => 'domains',
            'record-path'       => '$${recordings_dir}',
            'debug'             => '0',
            'sip-trace'         => 'no',
            'manage-presence'   => 'false',
            'pass-rfc2833'      => 'true',
            'user-agent-string' => 'FreeSWITCH',
        ),
    );
    foreach ($overrides as $cat => $vals) {
        if (isset($d[$cat]) && is_array($vals))
            foreach ($vals as $k => $v) $d[$cat][$k] = $v;
    }
    return $d;
}

// ══════════════════════════════════════════════════════════════════════════
//  ROUTES
// ══════════════════════════════════════════════════════════════════════════

try {
    $db = getDB();

    // ── LIST profiles ──────────────────────────────────────────────────────
    if ($action === 'list' && $method === 'GET') {
        $rows = $db->query(
            "SELECT * FROM sip_profiles ORDER BY is_custom ASC, id ASC"
        )->fetchAll();
        foreach ($rows as &$r) {
            $c = $db->prepare("SELECT COUNT(*) FROM sip_profile_params WHERE profile_id=?");
            $c->execute(array($r['id']));
            $r['param_count'] = (int)$c->fetchColumn();
            $r['enabled']     = (bool)$r['enabled'];
            $r['is_custom']   = (bool)$r['is_custom'];
        }
        unset($r);
        writeLog('INFO', "SIP-PROFILES GET ALL — " . count($rows));
        writeSeparator();
        ok(array('data' => $rows, 'total' => count($rows)));
    }

    // ── GET single profile ─────────────────────────────────────────────────
    if ($action === 'profile' && $method === 'GET') {
        $profile = getProfile($db, $profileId);
        if (!$profile) fail(404, 'SIP profile not found');

        $params = getProfileParams($db, $profileId);
        $profile['params']    = groupParams($params);
        $profile['enabled']   = (bool)$profile['enabled'];
        $profile['is_custom'] = (bool)$profile['is_custom'];

        writeLog('INFO', "SIP-PROFILE GET | ID:{$profileId} | name:{$profile['name']}");
        writeSeparator();
        ok(array('data' => $profile));
    }

    // ── PROFILE STATUS ─────────────────────────────────────────────────────
    if ($action === 'status' && $method === 'GET') {
        $profile = getProfile($db, $profileId);
        if (!$profile) fail(404, 'SIP profile not found');

        $status = safeReload($profile['name']); // just rescan to get status
        $raw    = isset($status['response']) ? $status['response'] : '';

        writeLog('INFO', "SIP-PROFILE STATUS | name:{$profile['name']}");
        writeSeparator();
        ok(array(
            'profile_id'   => $profileId,
            'profile_name' => $profile['name'],
            'status'       => (strpos($raw, 'RUNNING') !== false) ? 'running' : 'unknown',
            'raw'          => $raw,
        ));
    }

    // ── RESTART profile ────────────────────────────────────────────────────
    if ($action === 'restart' && $method === 'POST') {
        $profile = getProfile($db, $profileId);
        if (!$profile) fail(404, 'SIP profile not found');

        $result = safeReload($profile['name']);
        writeLog('INFO', "SIP-PROFILE RESTART | name:{$profile['name']}");
        writeSeparator();
        ok(array(
            'profile_id'   => $profileId,
            'profile_name' => $profile['name'],
            'reload'       => $result,
        ));
    }

    // ── CREATE custom profile ──────────────────────────────────────────────
    if ($action === 'list' && $method === 'POST') {
        $body = jbody();

        if (empty($body['name']))
            fail(422, 'Validation failed', array("name is required"));
        if (!preg_match('/^[\w\-]+$/', $body['name']))
            fail(422, 'Validation failed',
                array("name: only letters, numbers, hyphens, underscores"));

        $dup = $db->prepare("SELECT COUNT(*) FROM sip_profiles WHERE name=?");
        $dup->execute(array($body['name']));
        if ((int)$dup->fetchColumn() > 0)
            fail(409, 'Duplicate', array("Profile '{$body['name']}' already exists"));

        $profileName = $body['name'];
        $filename    = 'sip_profiles/' . $profileName . '.xml';
        $description = isset($body['description']) ? $body['description'] : '';

        // Build params with overrides
        $overrides = array();
        foreach (getAllowedCategories() as $cat) {
            if (!empty($body[$cat]) && is_array($body[$cat]))
                $overrides[$cat] = $body[$cat];
        }
        $allParams  = getDefaultParams($overrides);
        $flatParams = array();
        foreach ($allParams as $catParams)
            foreach ($catParams as $k => $v) $flatParams[$k] = $v;

        // Write XML file
        $xmlResult = SipProfileXML::create($profileName, $flatParams);
        if (!$xmlResult['success'])
            fail(500, 'Failed to create profile XML', array($xmlResult['error']));

        // Save to DB
        $newId = null;
        try {
            $db->beginTransaction();
            $db->prepare("INSERT INTO sip_profiles
                (name,filename,description,is_custom,enabled)
                VALUES (?,?,?,1,1)")
               ->execute(array($profileName, $filename, $description));
            $newId = (int)$db->lastInsertId();

            $sp = $db->prepare("INSERT INTO sip_profile_params
                (profile_id,param_name,param_value,category,is_sensitive,editable)
                VALUES (?,?,?,?,0,1)");
            foreach ($allParams as $cat => $catParams)
                foreach ($catParams as $k => $v)
                    $sp->execute(array($newId, $k, $v, $cat));

            $db->commit();
        } catch (Exception $e) {
            if ($db->inTransaction()) $db->rollBack();
            @unlink(SipProfileXML::getProfilePath($filename));
            fail(500, 'Database error: ' . $e->getMessage());
        }

        // Start profile in FreeSWITCH (non-blocking — don't fail if ESL down)
        $eslResult = array('success' => false, 'message' => 'ESL not attempted');
        try {
            $eslResult = FreeSwitchESL::run(function($esl) use ($profileName) {
                $esl->reloadDialplan();
                usleep(300000);
                return $esl->sofiaProfileStart($profileName);
            });
        } catch (Exception $e) {
            writeLog('WARN', "ESL start profile failed: " . $e->getMessage());
        }

        writeLog('INFO', "SIP-PROFILE CREATED | ID:{$newId} | name:{$profileName}"
            . " | params:" . count($flatParams));
        writeSeparator();

        // Fetch saved params for response
        $savedParams = getProfileParams($db, $newId);
        ok(array(
            'id'          => $newId,
            'name'        => $profileName,
            'filename'    => $filename,
            'description' => $description,
            'params'      => groupParams($savedParams),
            'esl'         => $eslResult,
        ), 201);
    }

    // ── GET params ─────────────────────────────────────────────────────────
    if ($action === 'params' && $method === 'GET' && !$paramId) {
        $profile = getProfile($db, $profileId);
        if (!$profile) fail(404, 'SIP profile not found');

        $cat  = isset($_GET['category']) ? $_GET['category'] : null;
        $rows = getProfileParams($db, $profileId, $cat);

        writeLog('INFO', "SIP-PROFILE GET PARAMS | profile:{$profile['name']}"
            . " | count:" . count($rows));
        writeSeparator();
        ok(array(
            'profile_id'   => $profileId,
            'profile_name' => $profile['name'],
            'total'        => count($rows),
            'grouped'      => groupParams($rows),
        ));
    }

    // ── GET single param ───────────────────────────────────────────────────
    if ($action === 'params' && $method === 'GET' && $paramId) {
        $s = $db->prepare(
            "SELECT * FROM sip_profile_params WHERE id=? AND profile_id=?"
        );
        $s->execute(array($paramId, $profileId));
        $param = $s->fetch();
        if (!$param) fail(404, 'Parameter not found');
        writeSeparator();
        ok(array('data' => maskParam($param)));
    }

    // ── ADD new param ──────────────────────────────────────────────────────
    if ($action === 'params' && $method === 'POST' && !$paramId) {
        $profile = getProfile($db, $profileId);
        if (!$profile) fail(404, 'SIP profile not found');

        $body = jbody();
        if (empty($body['param_name']))   fail(422, 'param_name is required');
        if (!isset($body['param_value'])) fail(422, 'param_value is required');

        $dup = $db->prepare(
            "SELECT COUNT(*) FROM sip_profile_params WHERE profile_id=? AND param_name=?"
        );
        $dup->execute(array($profileId, $body['param_name']));
        if ((int)$dup->fetchColumn() > 0)
            fail(409, 'Duplicate',
                array("'{$body['param_name']}' already exists in this profile"));

        // DB insert
        try {
            $db->prepare("INSERT INTO sip_profile_params
                (profile_id,param_name,param_value,description,category,is_sensitive,editable,updated_by)
                VALUES (?,?,?,?,?,?,1,?)")
               ->execute(array(
                   $profileId,
                   $body['param_name'],
                   $body['param_value'],
                   isset($body['description'])  ? $body['description']       : '',
                   isset($body['category'])     ? $body['category']          : 'general',
                   isset($body['is_sensitive']) ? (int)$body['is_sensitive'] : 0,
                   isset($body['updated_by'])   ? $body['updated_by']        : 'admin',
               ));
            $newParamId = (int)$db->lastInsertId();
        } catch (Exception $e) {
            fail(500, 'Database error: ' . $e->getMessage());
        }

        // Write XML
        $xmlResult = SipProfileXML::write(
            $profile['filename'],
            array($body['param_name'] => $body['param_value'])
        );
        if (!$xmlResult['success']) {
            $db->prepare("DELETE FROM sip_profile_params WHERE id=?")
               ->execute(array($newParamId));
            fail(500, 'XML write failed — rolled back', array($xmlResult['error']));
        }

        $reload = safeReload($profile['name']);
        writeLog('INFO', "PARAM ADDED | profile:{$profile['name']}"
            . " | param:{$body['param_name']}");
        writeSeparator();
        ok(array('id' => $newParamId, 'reload' => $reload), 201);
    }

    // ── UPDATE param ───────────────────────────────────────────────────────
    if ($action === 'params' && $method === 'PUT' && $paramId) {
        $profile = getProfile($db, $profileId);
        if (!$profile) fail(404, 'SIP profile not found');

        $s = $db->prepare(
            "SELECT * FROM sip_profile_params WHERE id=? AND profile_id=?"
        );
        $s->execute(array($paramId, $profileId));
        $existing = $s->fetch();
        if (!$existing) fail(404, 'Parameter not found');
        if (!$existing['editable']) fail(403, 'Parameter is read-only');

        $body = jbody();
        if (!isset($body['param_value'])) fail(422, 'param_value is required');

        $newValue  = $body['param_value'];
        $newDesc   = isset($body['description']) ? $body['description'] : $existing['description'];
        $newCat    = isset($body['category'])    ? $body['category']    : $existing['category'];
        $updatedBy = isset($body['updated_by'])  ? $body['updated_by']  : 'admin';

        // DB update
        try {
            $db->prepare("UPDATE sip_profile_params SET
                param_value=?,description=?,category=?,updated_by=? WHERE id=?")
               ->execute(array($newValue, $newDesc, $newCat, $updatedBy, $paramId));
        } catch (Exception $e) {
            fail(500, 'Database error: ' . $e->getMessage());
        }

        // XML write
        $xmlResult = SipProfileXML::write(
            $profile['filename'],
            array($existing['param_name'] => $newValue)
        );
        if (!$xmlResult['success']) {
            // Rollback
            $db->prepare("UPDATE sip_profile_params SET
                param_value=?,description=?,category=? WHERE id=?")
               ->execute(array(
                   $existing['param_value'],
                   $existing['description'],
                   $existing['category'],
                   $paramId,
               ));
            fail(500, 'XML write failed — DB rolled back', array($xmlResult['error']));
        }

        $reload = safeReload($profile['name']);
        $display = $existing['is_sensitive'] ? '********' : $newValue;
        writeLog('INFO', "PARAM UPDATED | profile:{$profile['name']}"
            . " | param:{$existing['param_name']} | value:{$display}");
        writeSeparator();
        ok(array(
            'param_id'   => $paramId,
            'param_name' => $existing['param_name'],
            'reload'     => $reload,
        ));
    }

    // ── BULK UPDATE params ─────────────────────────────────────────────────
    if ($action === 'bulk' && $method === 'POST') {
        $profile = getProfile($db, $profileId);
        if (!$profile) fail(404, 'SIP profile not found');

        $body = jbody();
        if (empty($body['params']) || !is_array($body['params']))
            fail(422, 'params array is required');

        $updatedBy = isset($body['updated_by']) ? $body['updated_by'] : 'admin';
        $errors    = array();
        $toUpdate  = array();
        $dbUpdates = array();
        $snapshots = array();

        foreach ($body['params'] as $i => $item) {
            if (empty($item['param_name'])) {
                $errors[] = "params[{$i}]: param_name is required"; continue;
            }
            if (!isset($item['param_value'])) {
                $errors[] = "params[{$i}]: param_value is required"; continue;
            }
            $s = $db->prepare(
                "SELECT * FROM sip_profile_params WHERE profile_id=? AND param_name=?"
            );
            $s->execute(array($profileId, $item['param_name']));
            $ex = $s->fetch();
            if (!$ex) {
                $errors[] = "params[{$i}]: '{$item['param_name']}' not found in profile";
                continue;
            }
            if (!$ex['editable']) {
                $errors[] = "params[{$i}]: '{$item['param_name']}' is read-only";
                continue;
            }
            $toUpdate[$item['param_name']] = $item['param_value'];
            $dbUpdates[$ex['id']]          = array(
                'name'      => $item['param_name'],
                'new'       => $item['param_value'],
                'sensitive' => $ex['is_sensitive'],
            );
            $snapshots[] = $ex;
        }

        if (!empty($errors)) fail(422, 'Validation failed', $errors);
        if (empty($toUpdate)) fail(422, 'No valid updates provided');

        // DB update all
        try {
            $db->beginTransaction();
            $s = $db->prepare(
                "UPDATE sip_profile_params SET param_value=?,updated_by=? WHERE id=?"
            );
            foreach ($dbUpdates as $id => $info)
                $s->execute(array($info['new'], $updatedBy, $id));
            $db->commit();
        } catch (Exception $e) {
            if ($db->inTransaction()) $db->rollBack();
            fail(500, 'Database error: ' . $e->getMessage());
        }

        // XML write — one pass
        $xmlResult = SipProfileXML::write($profile['filename'], $toUpdate);
        if (!$xmlResult['success']) {
            // Rollback
            try {
                $db->beginTransaction();
                $s = $db->prepare(
                    "UPDATE sip_profile_params SET param_value=? WHERE id=?"
                );
                foreach ($snapshots as $snap)
                    $s->execute(array($snap['param_value'], $snap['id']));
                $db->commit();
            } catch (Exception $re) {
                writeLog('ERROR', "Bulk rollback failed: " . $re->getMessage());
            }
            fail(500, 'XML write failed — DB rolled back', array($xmlResult['error']));
        }

        $reload  = safeReload($profile['name']);
        $summary = array();
        foreach ($dbUpdates as $id => $info) {
            $summary[] = array(
                'param_name' => $info['name'],
                'new_value'  => $info['sensitive'] ? '********' : $info['new'],
            );
        }

        writeLog('INFO', "BULK UPDATE | profile:{$profile['name']}"
            . " | count:" . count($dbUpdates));
        writeSeparator();
        ok(array(
            'profile_name'  => $profile['name'],
            'updated_count' => count($dbUpdates),
            'summary'       => $summary,
            'reload'        => $reload,
        ));
    }

    fail(405, 'Method Not Allowed');

} catch (Exception $e) {
    writeLog('ERROR', "SIP-PROFILE Exception: " . $e->getMessage()
        . " | " . basename($e->getFile()) . ":" . $e->getLine());
    writeSeparator();
    fail(500, $e->getMessage());
}
