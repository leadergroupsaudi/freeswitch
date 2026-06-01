<?php
class GatewayXML {

    private static function getSipProfilePath() {

        return '/usr/local/freeswitch-automax-instance/etc/freeswitch/sip_profiles';
        //return '/usr/local/freeswitch/conf/sip_profiles';
    }

    public static function write($gateway, $password) {
        $profileDir = self::getSipProfilePath() . '/external';

        if (!is_dir($profileDir))
            return array('success' => false, 'error' => "SIP profile dir not found: {$profileDir}");

        if (!is_writable($profileDir))
            return array('success' => false, 'error' => "SIP profile dir not writable: {$profileDir}");

        $name = $gateway['gateway_name'];
        $file = $profileDir . '/' . $name . '.xml';

        $e = function($val) {
            return htmlspecialchars((string)$val, ENT_XML1 | ENT_COMPAT, 'UTF-8');
        };

        $xml  = '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
        $xml .= '<include>' . "\n";
        $xml .= '  <gateway name="' . $e($name) . '">' . "\n";

        // Required params
        $xml .= '    <param name="username"           value="' . $e($gateway['username'])  . '"/>' . "\n";
        $xml .= '    <param name="password"           value="' . $e($password)             . '"/>' . "\n";
        $xml .= '    <param name="realm"              value="' . $e($gateway['realm'])     . '"/>' . "\n";

        // Optional params — only write if set
        if (!empty($gateway['proxy']))
            $xml .= '    <param name="proxy"              value="' . $e($gateway['proxy'])              . '"/>' . "\n";

        if (!empty($gateway['register_proxy']))
            $xml .= '    <param name="register-proxy"     value="' . $e($gateway['register_proxy'])     . '"/>' . "\n";

        if (!empty($gateway['apply_inbound_acl']))
            $xml .= '    <param name="apply-inbound-acl"  value="' . $e($gateway['apply_inbound_acl'])  . '"/>' . "\n";

        if (!empty($gateway['from_user']))
            $xml .= '    <param name="from-user"          value="' . $e($gateway['from_user'])          . '"/>' . "\n";

        if (!empty($gateway['from_domain']))
            $xml .= '    <param name="from-domain"        value="' . $e($gateway['from_domain'])        . '"/>' . "\n";

        $xml .= '    <param name="register"           value="' . ($gateway['register'] ? 'true' : 'false') . '"/>' . "\n";

        if (!empty($gateway['register_transport']))
            $xml .= '    <param name="register-transport" value="' . $e($gateway['register_transport']) . '"/>' . "\n";

        $xml .= '    <param name="expire-seconds"     value="' . (int)$gateway['expire_seconds']  . '"/>' . "\n";
        $xml .= '    <param name="retry-seconds"      value="' . (int)$gateway['retry_seconds']   . '"/>' . "\n";
        $xml .= '    <param name="caller-id-in-from"  value="' . ($gateway['caller_id_in_from'] ? 'true' : 'false') . '"/>' . "\n";

        if (!empty($gateway['ping']))
            $xml .= '    <param name="ping"               value="' . $e($gateway['ping'])                . '"/>' . "\n";

        if (!empty($gateway['outbound_caller_id_name']))
            $xml .= '    <param name="outbound-caller-id-name"   value="' . $e($gateway['outbound_caller_id_name'])   . '"/>' . "\n";

        if (!empty($gateway['outbound_caller_id_number']))
            $xml .= '    <param name="outbound-caller-id-number" value="' . $e($gateway['outbound_caller_id_number']) . '"/>' . "\n";

        if (!empty($gateway['codec_prefs']))
            $xml .= '    <param name="codec-prefs"        value="' . $e($gateway['codec_prefs'])        . '"/>' . "\n";

        $xml .= '  </gateway>' . "\n";
        $xml .= '</include>' . "\n";

        if (file_put_contents($file, $xml) === false)
            return array('success' => false, 'error' => "Failed to write: {$file}");

        return array('success' => true, 'file' => $file);
    }

    public static function delete($gatewayName) {
        $file = self::getSipProfilePath() . '/external/' . $gatewayName . '.xml';
        if (file_exists($file) && !unlink($file))
            return array('success' => false, 'error' => "Failed to delete: {$file}");
        return array('success' => true);
    }

    public static function rename($oldName, $newName) {
        $dir = self::getSipProfilePath() . '/external/';
        $old = $dir . $oldName . '.xml';
        $new = $dir . $newName . '.xml';
        if (file_exists($old) && !rename($old, $new))
            return array('success' => false, 'error' => "Failed to rename gateway file");
        return array('success' => true);
    }
}

