<?php
class AclXML {

    private static function getFilePath() {
        // Update this path to match your FreeSWITCH install

        return '/usr/local/freeswitch-automax-instance/etc/freeswitch/autoload_configs/acl.conf.xml';
        //return '/usr/local/freeswitch/conf/autoload_configs/acl.conf.xml';
    }

    public static function write($lists) {
        $filePath = self::getFilePath();

        if (!file_exists($filePath))
            return array('success' => false, 'error' => "ACL file not found: {$filePath}");

        if (!is_writable($filePath))
            return array('success' => false, 'error' => "ACL file not writable: {$filePath}");

        $xml  = '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
        $xml .= '<configuration name="acl.conf" description="Network Lists">' . "\n";
        $xml .= "  <network-lists>\n";

        foreach ($lists as $list) {
            $name    = htmlspecialchars($list['name'],           ENT_XML1 | ENT_COMPAT, 'UTF-8');
            $default = htmlspecialchars($list['default_policy'], ENT_XML1 | ENT_COMPAT, 'UTF-8');
            $xml    .= "    <list name=\"{$name}\" default=\"{$default}\">\n";

            if (!empty($list['entries'])) {
                foreach ($list['entries'] as $entry) {
                    $type = htmlspecialchars($entry['type'], ENT_XML1 | ENT_COMPAT, 'UTF-8');
                    if (!empty($entry['domain'])) {
                        $domain = htmlspecialchars($entry['domain'], ENT_XML1 | ENT_COMPAT, 'UTF-8');
                        $xml   .= "      <node type=\"{$type}\" domain=\"{$domain}\"/>\n";
                    } elseif (!empty($entry['cidr'])) {
                        $cidr = htmlspecialchars($entry['cidr'], ENT_XML1 | ENT_COMPAT, 'UTF-8');
                        $xml .= "      <node type=\"{$type}\" cidr=\"{$cidr}\"/>\n";
                    }
                }
            }
            $xml .= "    </list>\n";
        }

        $xml .= "  </network-lists>\n";
        $xml .= "</configuration>\n";

        if (file_put_contents($filePath, $xml) === false)
            return array('success' => false, 'error' => "Failed to write ACL file");

        return array('success' => true);
    }

    public static function reload() {
        $esl = new FreeSwitchESL();
        if ($esl->connect()) {
            // Reload ACL module
            $esl->sendCommand("api reloadacl");
            $esl->disconnect();
            return array('success' => true);
        }
        return array('success' => false, 'error' => 'FreeSWITCH ESL connection failed');
    }
}

