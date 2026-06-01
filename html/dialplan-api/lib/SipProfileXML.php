<?php
class SipProfileXML {

    private static function getBasePath() {
        return '/usr/local/freeswitch-automax-instance/etc/freeswitch';
    }

    public static function getProfilePath($filename) {
        return self::getBasePath() . '/' . $filename;
    }

    // -- READ ------------------------------------------------------------------

    public static function read($filename) {
        $filePath = self::getProfilePath($filename);

        if (!file_exists($filePath))
            return ['success' => false, 'error' => "Profile file not found: {$filePath}"];

        $content = file_get_contents($filePath);
        if ($content === false)
            return ['success' => false, 'error' => "Cannot read file: {$filePath}"];

        libxml_use_internal_errors(true);
        $xml = simplexml_load_string($content);
        if (!$xml) {
            libxml_clear_errors();
            return ['success' => false, 'error' => "Invalid XML in: {$filePath}"];
        }
        libxml_clear_errors();

        $params = [];

        if ($xml->getName() === 'profile') {
            $profile = $xml;
        } elseif (isset($xml->profile)) {
            $profile = $xml->profile;
        } elseif (isset($xml->settings)) {
            $profile = $xml;
        } else {
            $profile = null;
        }

        if ($profile) {
            foreach ($profile->settings->param as $param) {
                $name  = (string)$param['name'];
                $value = (string)$param['value'];
                if ($name) $params[$name] = $value;
            }
        }

        return ['success' => true, 'params' => $params, 'file' => $filePath];
    }

    // -- WRITE -----------------------------------------------------------------

    public static function write($filename, $updates) {
        $filePath = self::getProfilePath($filename);

        if (!file_exists($filePath))
            return ['success' => false, 'error' => "Profile file not found: {$filePath}"];
        if (!is_writable($filePath))
            return ['success' => false, 'error' => "Profile file not writable: {$filePath}"];

        $content = file_get_contents($filePath);
        if ($content === false)
            return ['success' => false, 'error' => "Cannot read file: {$filePath}"];

        $updated  = [];
        $appended = [];

        foreach ($updates as $paramName => $paramValue) {
            $safeValue   = htmlspecialchars($paramValue, ENT_XML1 | ENT_COMPAT, 'UTF-8');
            $escapedName = preg_quote($paramName, '/');

            $pattern     = '/(<param\s+name="' . $escapedName . '"\s+value=")[^"]*(")/i';
            $replacement = '${1}' . $safeValue . '${2}';
            $newContent  = preg_replace($pattern, $replacement, $content, -1, $count);

            if ($count > 0) {
                $content   = $newContent;
                $updated[] = $paramName;
            } else {
                $newLine    = '      <param name="' . $paramName . '" value="' . $safeValue . '"/>';
                $content    = str_replace('</settings>', $newLine . "\n    </settings>", $content);
                $appended[] = $paramName;
                $updated[]  = $paramName;
            }
        }

        if (file_put_contents($filePath, $content) === false)
            return ['success' => false, 'error' => "Failed to write: {$filePath}"];

        return ['success' => true, 'updated' => $updated, 'appended' => $appended, 'file' => $filePath];
    }

    // -- CREATE ----------------------------------------------------------------
    // NOTE: if the XML file already exists (orphan from a previous failed attempt)
    // it is overwritten — the DB-level duplicate check in the handler is the
    // authoritative guard against true duplicates.

    public static function create($profileName, $params) {
        $filename = 'sip_profiles/' . $profileName . '.xml';
        $filePath = self::getProfilePath($filename);
        $dir      = dirname($filePath);

        if (!is_dir($dir))
            return ['success' => false, 'error' => "Profile directory not found: {$dir}"];

        if (!is_writable($dir))
            return ['success' => false, 'error' => "Profile directory not writable: {$dir}"];

        // If file exists already (orphan from prior failed attempt), remove it
        // so we get a clean write — the handler already verified no DB record exists.
        if (file_exists($filePath)) {
            if (!unlink($filePath))
                return ['success' => false, 'error' => "Orphan XML exists and could not be removed: {$filePath}"];
        }

        $xml  = '<include>' . "\n";
        $xml .= '  <profile name="' . htmlspecialchars($profileName, ENT_XML1 | ENT_COMPAT) . '">' . "\n";
        $xml .= '    <settings>' . "\n";
        foreach ($params as $name => $value) {
            $xml .= '      <param name="'
                  . htmlspecialchars($name,  ENT_XML1 | ENT_COMPAT)
                  . '" value="'
                  . htmlspecialchars($value, ENT_XML1 | ENT_COMPAT)
                  . '"/>' . "\n";
        }
        $xml .= '    </settings>' . "\n";
        $xml .= '  </profile>' . "\n";
        $xml .= '</include>' . "\n";

        if (file_put_contents($filePath, $xml) === false)
            return ['success' => false, 'error' => "Failed to create: {$filePath}"];

        // Verify it actually landed
        if (!file_exists($filePath))
            return ['success' => false, 'error' => "File not found after write — check disk space: {$filePath}"];

        return ['success' => true, 'file' => $filePath, 'filename' => $filename];
    }

    // -- DELETE ----------------------------------------------------------------

    public static function delete($filename) {
        $filePath = self::getProfilePath($filename);
        if (!file_exists($filePath))
            return ['success' => true, 'note' => 'File did not exist'];
        if (!unlink($filePath))
            return ['success' => false, 'error' => "Failed to delete: {$filePath}"];
        return ['success' => true, 'file' => $filePath];
    }

    // -- RELOAD ----------------------------------------------------------------

    public static function reload($profileName) {
        try {
            $esl = new FreeSwitchESL();
            if (!$esl->connect())
                return ['success' => false, 'error' => 'ESL connection failed'];

            $esl->sendCommand("api reloadxml");

            $cmd      = "api sofia profile {$profileName} restart";
            $response = trim($esl->sendCommand($cmd));
            $esl->disconnect();

            $success = (stripos($response, '+OK')        !== false ||
                        stripos($response, 'Restarting') !== false ||
                        stripos($response, 'Starting')   !== false ||
                        stripos($response, 'Stopping')   !== false);

            $result = [
                'success'  => $success,
                'response' => $response,
                'command'  => "sofia profile {$profileName} restart",
            ];

            if (!$success && stripos($response, 'Invalid Profile') !== false) {
                $result['warning'] =
                    "Profile saved. Run: sofia profile {$profileName} rescan";
            }

            return $result;

        } catch (Exception $e) {
            return ['success' => false, 'error' => $e->getMessage()];
        }
    }

    // -- RESCAN ----------------------------------------------------------------

    public static function rescan($profileName) {
        try {
            $esl = new FreeSwitchESL();
            if (!$esl->connect())
                return ['success' => false, 'error' => 'ESL connection failed'];

            $esl->sendCommand("api reloadxml");
            $response = trim($esl->sendCommand("api sofia profile {$profileName} rescan"));
            $esl->disconnect();

            return [
                'success'  => stripos($response, '+OK') !== false,
                'response' => $response,
            ];
        } catch (Exception $e) {
            return ['success' => false, 'error' => $e->getMessage()];
        }
    }

    // -- STATUS ----------------------------------------------------------------

    public static function status($profileName) {
        try {
            $esl = new FreeSwitchESL();
            if (!$esl->connect())
                return ['success' => false, 'error' => 'ESL connection failed'];

            $response = trim($esl->sendCommand("api sofia status profile {$profileName}"));
            $esl->disconnect();

            $running = stripos($response, 'RUNNING') !== false;
            return [
                'success' => true,
                'running' => $running,
                'status'  => $running ? 'running' : 'stopped',
                'raw'     => $response,
            ];
        } catch (Exception $e) {
            return ['success' => false, 'error' => $e->getMessage()];
        }
    }

    // -- LIST PROFILES ---------------------------------------------------------

    public static function listProfiles() {
        try {
            $esl = new FreeSwitchESL();
            if (!$esl->connect())
                return ['success' => false, 'error' => 'ESL connection failed'];

            $response = trim($esl->sendCommand("api sofia status"));
            $esl->disconnect();

            $profiles = [];
            foreach (explode("\n", $response) as $line) {
                if (preg_match('/^\s*(\S+)\s+(?:running|stopped)/i', $line, $m)) {
                    $profiles[] = $m[1];
                }
            }

            return ['success' => true, 'profiles' => $profiles, 'raw' => $response];
        } catch (Exception $e) {
            return ['success' => false, 'error' => $e->getMessage()];
        }
    }
}
