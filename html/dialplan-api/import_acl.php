<?php
require_once __DIR__ . '/config/db.php';


//$aclFile = '/usr/local/freeswitch/conf/autoload_configs/acl.conf.xml';
$aclFile = '/usr/local/freeswitch-automax-instance/etc/freeswitch/autoload_configs/acl.conf.xml';
if (!file_exists($aclFile)) {
    die("ACL file not found: {$aclFile}\n");
}

$db      = getDB();
$content = file_get_contents($aclFile);

libxml_use_internal_errors(true);
$xml = simplexml_load_string($content);
if (!$xml) {
    die("Failed to parse ACL XML\n");
}

$imported = 0;
$skipped  = 0;

foreach ($xml->{'network-lists'}->list as $list) {
    $name    = (string)$list['name'];
    $default = (string)$list['default'];

    // Skip if already exists
    $dup = $db->prepare("SELECT COUNT(*) FROM acl_lists WHERE name = ?");
    $dup->execute(array($name));
    if ((int)$dup->fetchColumn() > 0) {
        echo "[SKIP] List already exists: '{$name}'\n";
        $skipped++;
        continue;
    }

    $s = $db->prepare("INSERT INTO acl_lists (name, default_policy) VALUES (:name, :dp)");
    $s->execute(array(':name' => $name, ':dp' => $default));
    $listId = (int)$db->lastInsertId();

    echo "[OK] Imported list: '{$name}' (default:{$default}) ID:{$listId}\n";

    foreach ($list->node as $node) {
        $type   = (string)$node['type'];
        $cidr   = isset($node['cidr'])   ? (string)$node['cidr']   : null;
        $domain = isset($node['domain']) ? (string)$node['domain'] : null;

        $e = $db->prepare("INSERT INTO acl_entries (list_id, type, cidr, domain)
                           VALUES (:lid, :type, :cidr, :domain)");
        $e->execute(array(
            ':lid'    => $listId,
            ':type'   => $type,
            ':cidr'   => $cidr,
            ':domain' => $domain,
        ));
        $val = $cidr ? $cidr : $domain;
        echo "  [OK] Entry: type:{$type} value:{$val}\n";
        $imported++;
    }
}

echo "\nImport done — lists skipped:{$skipped} entries imported:{$imported}\n";

