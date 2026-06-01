<?php
class DialplanXML {

    public static function write(string $context, array $rules): array {
        $files = FS_DIALPLAN_FILES;

        if (!isset($files[$context])) {
            return ['success' => false, 'error' => "Unknown context '{$context}'"];
        }

        $filePath = $files[$context];

        if (!file_exists($filePath)) {
            return ['success' => false, 'error' => "Dialplan file not found: {$filePath}"];
        }

        if (!is_writable($filePath)) {
            return ['success' => false, 'error' => "Dialplan file not writable: {$filePath}"];
        }

        $existing = file_get_contents($filePath);
        if ($existing === false) {
            return ['success' => false, 'error' => "Failed to read dialplan file: {$filePath}"];
        }

        // Remove previous DB block
        $cleaned = preg_replace(
            '/<!-- DB_GENERATED_START -->.*?<!-- DB_GENERATED_END -->\s*/s',
            '',
            $existing
        );

        if (!str_contains($cleaned, '</context>')) {
            return ['success' => false, 'error' => "Dialplan file missing </context> tag"];
        }

        // Build new block
        $block = "<!-- DB_GENERATED_START -->\n";
        foreach ($rules as $rule) {
            if (!$rule['enabled']) continue;

            $conditions = is_string($rule['conditions'])
                ? json_decode($rule['conditions'], true) : $rule['conditions'];
            $actions    = is_string($rule['actions'])
                ? json_decode($rule['actions'], true) : $rule['actions'];

            $extName = htmlspecialchars($rule['name'], ENT_XML1 | ENT_COMPAT, 'UTF-8');
            $block  .= "  <extension name=\"{$extName}\">\n";

            foreach ($conditions as $cond) {
                $attrs = '';
                foreach ($cond as $k => $v) {
                    if (str_starts_with($k, '_')) continue;
                    $safeVal = htmlspecialchars((string)$v, ENT_XML1 | ENT_COMPAT, 'UTF-8');
                    $attrs  .= " {$k}=\"{$safeVal}\"";
                }
                $block .= "    <condition{$attrs}>\n";

                foreach ($actions as $act) {
                    $tag     = (isset($act['_type']) && $act['_type'] === 'anti-action')
                               ? 'anti-action' : 'action';
                    $appName = htmlspecialchars($act['application'], ENT_XML1 | ENT_COMPAT, 'UTF-8');
                    if (!empty($act['data'])) {
                        $data   = htmlspecialchars($act['data'], ENT_XML1 | ENT_COMPAT, 'UTF-8');
                        $block .= "      <{$tag} application=\"{$appName}\" data=\"{$data}\"/>\n";
                    } else {
                        $block .= "      <{$tag} application=\"{$appName}\"/>\n";
                    }
                }
                $block .= "    </condition>\n";
            }
            $block .= "  </extension>\n";
        }
        $block .= "<!-- DB_GENERATED_END -->\n";

        // Validate ONLY the generated block — not the full file
        // FreeSWITCH uses $${var} and ${var} which are not valid XML entities
        // so we only validate our own generated XML block in isolation
        $testXml = '<?xml version="1.0" encoding="UTF-8"?><root>' . $block . '</root>';
        libxml_use_internal_errors(true);
        $test = simplexml_load_string($testXml);
        if (!$test) {
            $xmlErrors = libxml_get_errors();
            libxml_clear_errors();
            $msg = implode(' | ', array_map(fn($e) => trim($e->message), $xmlErrors));
            return ['success' => false, 'error' => "Generated block is invalid XML: {$msg}"];
        }
        libxml_clear_errors();

        // Inject block before </context>
        $final = str_replace('</context>', $block . '</context>', $cleaned);

        // Write to disk
        if (file_put_contents($filePath, $final) === false) {
            return ['success' => false, 'error' => "Failed to write to: {$filePath}"];
        }

        return ['success' => true];
    }
}
