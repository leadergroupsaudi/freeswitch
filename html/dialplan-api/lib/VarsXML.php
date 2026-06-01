<?php
class VarsXML {

    private static function getFilePath() {
	     return '/usr/local/freeswitch-automax-instance/etc/freeswitch/vars.xml';
	    #return '/usr/local/freeswitch/conf/vars.xml';
    }

    public static function read() {
        $filePath = self::getFilePath();
        if (!file_exists($filePath))
            return array('success' => false, 'error' => "vars.xml not found: {$filePath}");

        $content = file_get_contents($filePath);
        if ($content === false)
            return array('success' => false, 'error' => "Failed to read vars.xml");

        $vars = array();
        if (preg_match_all(
            '/<X-PRE-PROCESS\s+cmd="(set|stun-set|exec-set)"\s+data="([^=]+)=([^"]*)"[^\/]*\/>/i',
            $content, $matches, PREG_SET_ORDER
        )) {
            foreach ($matches as $m) {
                $vars[trim($m[2])] = array('value' => $m[3], 'cmd' => $m[1]);
            }
        }
        return array('success' => true, 'vars' => $vars);
    }

    public static function write($updates) {
        $filePath = self::getFilePath();

        if (!file_exists($filePath))
            return array('success' => false, 'error' => "vars.xml not found: {$filePath}");
        if (!is_writable($filePath))
            return array('success' => false, 'error' => "vars.xml not writable: {$filePath}");

        $content = file_get_contents($filePath);
        if ($content === false)
            return array('success' => false, 'error' => "Failed to read vars.xml");

        $updated  = array();
        $appended = array();

        foreach ($updates as $varName => $info) {
            $newValue  = is_array($info) ? $info['value'] : $info;
            $cmd       = is_array($info) ? (isset($info['cmd']) ? $info['cmd'] : 'set') : 'set';
            $safeValue = str_replace('"', '&quot;', $newValue);
            $escaped   = preg_quote($varName, '/');

            // Replace existing — match any cmd
            $pattern     = '/(<X-PRE-PROCESS\s+cmd="(?:set|stun-set|exec-set)"\s+data="'
                         . $escaped . '=)[^"]*(")/i';
            $replacement = '${1}' . $safeValue . '${2}';
            $newContent  = preg_replace($pattern, $replacement, $content, -1, $count);

            if ($count > 0) {
                $content   = $newContent;
                $updated[] = $varName;
            } else {
                // Append before </include>
                $newLine   = '  <X-PRE-PROCESS cmd="' . $cmd . '" data="'
                           . $varName . '=' . $safeValue . '"/>';
                $content   = str_replace('</include>', $newLine . "\n</include>", $content);
                $appended[] = $varName;
                $updated[]  = $varName;
            }
        }

        if (file_put_contents($filePath, $content) === false)
            return array('success' => false, 'error' => "Failed to write vars.xml");

        return array('success' => true, 'updated' => $updated, 'appended' => $appended);
    }

    /**
     * Delete a variable line from vars.xml
     */
    public static function delete($varName) {
        $filePath = self::getFilePath();

        if (!file_exists($filePath))
            return array('success' => false, 'error' => "vars.xml not found: {$filePath}");
        if (!is_writable($filePath))
            return array('success' => false, 'error' => "vars.xml not writable: {$filePath}");

        $content = file_get_contents($filePath);
        if ($content === false)
            return array('success' => false, 'error' => "Failed to read vars.xml");

        $escaped = preg_quote($varName, '/');

        // Remove the entire line containing this variable
        $pattern    = '/\s*<X-PRE-PROCESS\s+cmd="(?:set|stun-set|exec-set)"\s+data="'
                    . $escaped . '=[^"]*"[^\/]*\/>\s*\n?/i';
        $newContent = preg_replace($pattern, "\n", $content, -1, $count);

        if ($count === 0)
            return array('success' => false, 'error' => "Variable '{$varName}' not found in vars.xml");

        if (file_put_contents($filePath, $newContent) === false)
            return array('success' => false, 'error' => "Failed to write vars.xml");

        return array('success' => true, 'deleted' => $varName);
    }
}

