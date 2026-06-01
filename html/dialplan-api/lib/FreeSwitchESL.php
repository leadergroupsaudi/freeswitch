<?php
class FreeSwitchESL {

    private $socket    = null;
    private $host;
    private $port;
    private $password;
    private $connected = false;
    private $lastError = '';

    public function __construct($host = '127.0.0.1', $port = 8022, $password = 'ClueCon') {
        $this->host     = $host;
        $this->port     = $port;
        $this->password = $password;
    }

    // ── CONNECTION ─────────────────────────────────────────────────────────

    public function connect() {
        $errno  = 0;
        $errstr = '';

        $this->socket = @fsockopen($this->host, $this->port, $errno, $errstr, 5);

        if (!$this->socket) {
            $this->lastError = "Cannot connect to {$this->host}:{$this->port}"
                             . " — errno:{$errno} errstr:{$errstr}";
            $this->connected = false;
            writeLog('WARN', "ESL connect failed: " . $this->lastError);
            return false;
        }

        // Read auth banner
        $banner = $this->read();
        writeLog('DEBUG', "ESL banner: " . trim($banner));

        // Send password
        $this->send("auth {$this->password}");
        $response = $this->read();
        writeLog('DEBUG', "ESL auth response: " . trim($response));

        if (strpos($response, '+OK accepted') !== false) {
            $this->connected = true;
            writeLog('INFO', "ESL connected to {$this->host}:{$this->port}");
            return true;
        }

        $this->lastError = "Auth failed — response: " . trim($response);
        writeLog('WARN', "ESL auth failed: " . $this->lastError);
        fclose($this->socket);
        $this->socket    = null;
        $this->connected = false;
        return false;
    }

    public function disconnect() {
        if ($this->socket) {
            try { $this->send("exit"); } catch (Exception $e) {}
            fclose($this->socket);
            $this->socket    = null;
            $this->connected = false;
        }
    }

    public function isConnected() { return $this->connected; }
    public function getLastError() { return $this->lastError; }

    // ── RAW COMMAND ────────────────────────────────────────────────────────

    public function sendCommand($cmd) {
        $this->send($cmd);
        return $this->read();
    }

    // ── DIALPLAN ───────────────────────────────────────────────────────────

    public function reloadDialplan() {
        $r = $this->sendCommand("api reloadxml");
        return array('success' => strpos($r,'+OK')!==false, 'response'=>trim($r), 'command'=>'reloadxml');
    }

    // ── ACL ────────────────────────────────────────────────────────────────

    public function reloadACL() {
        $r = $this->sendCommand("api reloadacl");
        return array('success' => strpos($r,'+OK')!==false, 'response'=>trim($r), 'command'=>'reloadacl');
    }

    // ── SOFIA PROFILE ──────────────────────────────────────────────────────

    public function sofiaProfileRestart($name) {
        $r = $this->sendCommand("api sofia profile {$name} restart");
        return array(
            'success'  => (strpos($r,'+OK')!==false || strpos($r,'Restarting')!==false),
            'response' => trim($r),
            'command'  => "sofia profile {$name} restart",
        );
    }

    public function sofiaProfileRescan($name) {
        $r = $this->sendCommand("api sofia profile {$name} rescan");
        return array(
            'success'  => (strpos($r,'+OK')!==false || strpos($r,'Restarting')!==false),
            'response' => trim($r),
            'command'  => "sofia profile {$name} rescan",
        );
    }

    public function sofiaProfileStart($name) {
        $r = $this->sendCommand("api sofia profile {$name} start");
        return array('success'=>strpos($r,'+OK')!==false,'response'=>trim($r),'command'=>"sofia profile {$name} start");
    }

    public function sofiaProfileStop($name) {
        $r = $this->sendCommand("api sofia profile {$name} stop");
        return array('success'=>strpos($r,'+OK')!==false,'response'=>trim($r),'command'=>"sofia profile {$name} stop");
    }

    public function sofiaProfileStatus($name) {
        $r       = $this->sendCommand("api sofia status profile {$name}");
        $raw     = trim($r);
        $running = (strpos($raw,'RUNNING') !== false);
        return array(
            'success' => true,
            'running' => $running,
            'status'  => $running ? 'running' : 'stopped',
            'raw'     => $raw,
            'command' => "sofia status profile {$name}",
        );
    }

    public function sofiaStatus() {
        $r = $this->sendCommand("api sofia status");
        return array('success'=>true,'response'=>trim($r),'command'=>'sofia status');
    }

    // ── GATEWAY ────────────────────────────────────────────────────────────

    public function gatewayStart($name) {
        $r = $this->sendCommand("api sofia profile external startgw {$name}");
        return array('success'=>strpos($r,'+OK')!==false,'response'=>trim($r),'command'=>"startgw {$name}");
    }

    public function gatewayKill($name) {
        $r = $this->sendCommand("api sofia profile external killgw {$name}");
        return array('success'=>strpos($r,'+OK')!==false,'response'=>trim($r),'command'=>"killgw {$name}");
    }

    public function gatewayStatus($name) {
        $r   = $this->sendCommand("api sofia status gateway {$name}");
        $raw = trim($r);
        if      (strpos($raw,'REGED')     !== false) $s = 'registered';
        elseif  (strpos($raw,'FAILED')    !== false) $s = 'failed';
        elseif  (strpos($raw,'TRYING')    !== false) $s = 'trying';
        elseif  (strpos($raw,'EXPIRE')    !== false) $s = 'expired';
        elseif  (strpos($raw,'NOREG')     !== false) $s = 'not_registered';
        elseif  (strpos($raw,'not found') !== false) $s = 'not_found';
        else                                          $s = 'unknown';
        return array('success'=>true,'status'=>$s,'raw'=>$raw,'command'=>"sofia status gateway {$name}");
    }

    public function externalProfileRescan() {
        $r = $this->sendCommand("api sofia profile external rescan");
        return array('success'=>strpos($r,'+OK')!==false,'response'=>trim($r),'command'=>'sofia profile external rescan');
    }

    // ── MODULE RELOAD ──────────────────────────────────────────────────────

    public function reloadModule($module) {
        $r = $this->sendCommand("api reload {$module}");
        return array(
            'success'  => (strpos($r,'+OK')!==false || strpos($r,'Reloading')!==false),
            'response' => trim($r),
            'command'  => "reload {$module}",
        );
    }

    public function reloadSofia() { return $this->reloadModule('mod_sofia'); }

    // ── GLOBAL VARS ────────────────────────────────────────────────────────

    public function globalGetVar($var) {
        $r = $this->sendCommand("api global_getvar {$var}");
        return array('success'=>true,'value'=>trim($r),'command'=>"global_getvar {$var}");
    }

    public function globalSetVar($var, $val) {
        $r = $this->sendCommand("api global_setvar {$var}={$val}");
        return array('success'=>strpos($r,'+OK')!==false,'response'=>trim($r));
    }

    // ── CALL CONTROL ───────────────────────────────────────────────────────

    public function showCalls()    { return array('success'=>true,'response'=>trim($this->sendCommand("api show calls"))); }
    public function showChannels() { return array('success'=>true,'response'=>trim($this->sendCommand("api show channels"))); }
    public function status()       { return array('success'=>true,'response'=>trim($this->sendCommand("api status"))); }
    public function version()      { return array('success'=>true,'version' =>trim($this->sendCommand("api version"))); }

    public function hangupCall($uuid) {
        $r = $this->sendCommand("api uuid_kill {$uuid}");
        return array('success'=>strpos($r,'+OK')!==false,'response'=>trim($r));
    }

    // ── PRIVATE ────────────────────────────────────────────────────────────

    private function send($cmd) {
        if ($this->socket)
            fwrite($this->socket, $cmd . "\n\n");
    }

    private function read() {
        $data = '';
        $start = time();
        while ($this->socket && !feof($this->socket)) {
            if (time() - $start > 10) break; // 10s timeout safety
            $line  = fgets($this->socket, 4096);
            if ($line === false) break;
            $data .= $line;
            if (trim($line) === '') break;
        }
        if (preg_match('/Content-Length: (\d+)/i', $data, $m))
            $data .= fread($this->socket, (int)$m[1]);
        return $data;
    }

    // ── STATIC HELPERS ─────────────────────────────────────────────────────

    public static function run($callback) {
        $esl = new self();
        if (!$esl->connect()) {
            return array(
                'success'  => false,
                'error'    => $esl->getLastError() ?: 'ESL connection failed',
                'response' => '',
            );
        }
        try {
            $result = $callback($esl);
            $esl->disconnect();
            return $result;
        } catch (Exception $e) {
            $esl->disconnect();
            return array('success'=>false,'error'=>$e->getMessage(),'response'=>'');
        }
    }

    public static function batch($commands) {
        $esl = new self();
        if (!$esl->connect()) {
            return array(
                'success' => false,
                'error'   => $esl->getLastError() ?: 'ESL connection failed',
                'results' => array(),
            );
        }
        $results = array();
        $allOk   = true;
        try {
            foreach ($commands as $cmd) {
                $r         = $esl->sendCommand($cmd['cmd']);
                $ok        = (strpos($r,'+OK')!==false || strpos($r,'Reloading')!==false || strpos($r,'Restarting')!==false);
                $results[] = array(
                    'command'  => isset($cmd['label']) ? $cmd['label'] : $cmd['cmd'],
                    'response' => trim($r),
                    'success'  => $ok,
                );
                if (!$ok) $allOk = false;
                usleep(200000);
            }
        } catch (Exception $e) {
            $esl->disconnect();
            return array('success'=>false,'error'=>$e->getMessage(),'results'=>$results);
        }
        $esl->disconnect();
        return array('success'=>$allOk,'results'=>$results);
    }

    // ── DIAGNOSTIC — test connection and return details ────────────────────

    public static function diagnose() {
        $esl    = new self();
        $result = array(
            'host'      => $esl->host,
            'port'      => $esl->port,
            'connected' => false,
            'auth'      => false,
            'version'   => null,
            'error'     => null,
        );

        if (!$esl->connect()) {
            $result['error'] = $esl->getLastError();
            return $result;
        }

        $result['connected'] = true;
        $result['auth']      = true;

        $v = $esl->version();
        $result['version'] = $v['version'];

        $s = $esl->sofiaStatus();
        $result['sofia_status'] = substr($s['response'], 0, 200);

        $esl->disconnect();
        return $result;
    }
}
