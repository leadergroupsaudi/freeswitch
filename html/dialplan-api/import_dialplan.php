<?php
require_once __DIR__ . '/config/db.php';

// ── CONFIG ─────────────────────────────────────────────────────────────────

$files = [
    'public'   => '/usr/local/freeswitch/conf/dialplan/public.xml',
    'internal' => '/usr/local/freeswitch/conf/dialplan/default.xml',
    'features' => '/usr/local/freeswitch/conf/dialplan/features.xml',
];

$db = getDB();
$imported = 0;
$skipped  = 0;
$errors   = [];

// ── PARSER ─────────────────────────────────────────────────────────────────

function parseExtensions(string $filePath, string $context): array {
    if (!file_exists($filePath)) {
        echo "[WARN] File not found: {$filePath}\n";
        return [];
    }

    $content = file_get_contents($filePath);

    // Remove DB_GENERATED block — we don't want to re-import what we wrote
    $content = preg_replace(
        '/<!-- DB_GENERATED_START -->.*?<!-- DB_GENERATED_END -->/s',
        '',
        $content
    );

    // Suppress XML warnings and load
    libxml_use_internal_errors(true);
    $xml = simplexml_load_string($content);
    if (!$xml) {
        $errs = libxml_get_errors();
        echo "[ERROR] Failed to parse {$filePath}:\n";
        foreach ($errs as $e) echo "  Line {$e->line}: {$e->message}";
        libxml_clear_errors();
        return [];
    }

    $rules = [];

    // Handle both <context> wrapper and flat <extension> lists
    $extensions = [];
    if (isset($xml->context->extension)) {
        $extensions = $xml->context->extension;
    } elseif (isset($xml->extension)) {
        $extensions = $xml->extension;
    } else {
        // Search deeper — some files have include > context > extension
        foreach ($xml->children() as $child) {
            if ($child->getName() === 'context') {
                foreach ($child->extension as $ext) {
                    $extensions[] = $ext;
                }
            }
        }
    }

    $priority = 1;
    foreach ($extensions as $ext) {
        $name      = (string)($ext['name'] ?? 'unnamed_' . $priority);
        $conditions = [];
        $actions    = [];
        $extension  = '';

        foreach ($ext->condition as $cond) {
            $condData = [];

            // Capture all XML attributes of <condition>
            foreach ($cond->attributes() as $attr => $val) {
                $condData[$attr] = (string)$val;
            }

            // Get extension regex from field=destination_number
            if (isset($condData['field']) &&
                $condData['field'] === 'destination_number' &&
                isset($condData['expression'])) {
                $extension = $condData['expression'];
            }

            $conditions[] = $condData;

            // Capture <action> elements inside this condition
            foreach ($cond->action as $action) {
                $actData = [
                    'application' => (string)($action['application'] ?? ''),
                ];
                if (isset($action['data']) && (string)$action['data'] !== '') {
                    $actData['data'] = (string)$action['data'];
                }
                if (!empty($actData['application'])) {
                    $actions[] = $actData;
                }
            }

            // Also capture <anti-action> elements
            foreach ($cond->{'anti-action'} as $antiAction) {
                $actData = [
                    'application' => (string)($antiAction['application'] ?? ''),
                    '_type'       => 'anti-action',
                ];
                if (isset($antiAction['data']) && (string)$antiAction['data'] !== '') {
                    $actData['data'] = (string)$antiAction['data'];
                }
                if (!empty($actData['application'])) {
                    $actions[] = $actData;
                }
            }
        }

        // Fallback: if no destination_number condition found, use first expression
        if (empty($extension) && !empty($conditions)) {
            $extension = $conditions[0]['expression'] ?? '.*';
        }

        if (empty($actions)) {
            echo "[SKIP] Extension '{$name}' has no actions — skipping\n";
            continue;
        }

        $rules[] = [
            'name'       => $name,
            'extension'  => $extension ?: '.*',
            'conditions' => $conditions,
            'actions'    => $actions,
            'priority'   => $priority++,
            'enabled'    => true,
            'context'    => $context,
        ];
    }

    return $rules;
}

// ── IMPORT ─────────────────────────────────────────────────────────────────

$insertStmt = $db->prepare("
    INSERT INTO dialplan_rules
        (name, extension, conditions, actions, priority, enabled, context)
    VALUES
        (:name, :ext, :cond, :act, :pri, :en, :ctx)
");

$checkStmt = $db->prepare("
    SELECT COUNT(*) FROM dialplan_rules
    WHERE name = ? AND context = ?
");

echo "\n========================================\n";
echo "  FreeSWITCH Dialplan XML → DB Import\n";
echo "========================================\n\n";

foreach ($files as $context => $filePath) {
    echo "── Context: {$context} ──────────────────\n";
    echo "   File: {$filePath}\n";

    if (!file_exists($filePath)) {
        echo "   [SKIP] File not found\n\n";
        continue;
    }

    $rules = parseExtensions($filePath, $context);
    echo "   Found " . count($rules) . " extension(s)\n\n";

    foreach ($rules as $rule) {
        // Skip if already in DB (by name + context)
        $checkStmt->execute([$rule['name'], $context]);
        if ((int)$checkStmt->fetchColumn() > 0) {
            echo "   [SKIP] Already exists: '{$rule['name']}'\n";
            $skipped++;
            continue;
        }

        try {
            $insertStmt->execute([
                ':name' => $rule['name'],
                ':ext'  => $rule['extension'],
                ':cond' => json_encode($rule['conditions']),
                ':act'  => json_encode($rule['actions']),
                ':pri'  => $rule['priority'],
                ':en'   => 1,
                ':ctx'  => $context,
            ]);
            echo "   [OK]   Imported: '{$rule['name']}'"
               . " | ext: '{$rule['extension']}'"
               . " | actions: " . count($rule['actions']) . "\n";
            $imported++;
        } catch (Throwable $e) {
            echo "   [ERROR] '{$rule['name']}': " . $e->getMessage() . "\n";
            $errors[] = $rule['name'] . ': ' . $e->getMessage();
        }
    }
    echo "\n";
}

// ── SUMMARY ────────────────────────────────────────────────────────────────

echo "========================================\n";
echo "  Import Summary\n";
echo "========================================\n";
echo "  Imported : {$imported}\n";
echo "  Skipped  : {$skipped}\n";
echo "  Errors   : " . count($errors) . "\n";
if (!empty($errors)) {
    echo "\n  Error details:\n";
    foreach ($errors as $e) echo "    - {$e}\n";
}
echo "========================================\n\n";

// Show DB counts per context
echo "  DB counts after import:\n";
foreach (['public', 'internal', 'features'] as $ctx) {
    $count = $db->query(
        "SELECT COUNT(*) FROM dialplan_rules WHERE context='{$ctx}'"
    )->fetchColumn();
    echo "    {$ctx}: {$count} rules\n";
}
echo "========================================\n\n";
