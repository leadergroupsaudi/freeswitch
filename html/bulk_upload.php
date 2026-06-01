<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

header('Content-Type: application/json');

// ============================================
// LOG FILE SETUP
// ============================================
$log_file = fopen('account.txt', 'a');

function writeLog($fp, $level, $message) {
    $timestamp = date('Y-m-d H:i:s');
    $log_line  = "[$timestamp] [$level] $message" . PHP_EOL;
    fwrite($fp, $log_line);
}

function writeSeparator($fp) {
    fwrite($fp, str_repeat("=", 80) . PHP_EOL);
}

function writeSectionHeader($fp, $title) {
    fwrite($fp, str_repeat("-", 80) . PHP_EOL);
    fwrite($fp, "  $title" . PHP_EOL);
    fwrite($fp, str_repeat("-", 80) . PHP_EOL);
}

// Start log session
writeSeparator($log_file);
writeLog($log_file, "INFO", "====== BULK EXTENSION UPLOAD STARTED ======");
writeLog($log_file, "INFO", "Request IP     : " . ($_SERVER['REMOTE_ADDR'] ?? 'unknown'));
writeLog($log_file, "INFO", "Request Time   : " . date('Y-m-d H:i:s'));
writeSeparator($log_file);

// ============================================
// API KEY CHECK
// ============================================
$valid_api_key   = 'LeaderFS@Axionic#2026';
$request_api_key = $_SERVER['HTTP_X_API_KEY'] ?? '';

if ($request_api_key !== $valid_api_key) {
    writeLog($log_file, "ERROR", "UNAUTHORIZED — Invalid or missing API key from IP: " . ($_SERVER['REMOTE_ADDR'] ?? 'unknown'));
    writeSeparator($log_file);
    fclose($log_file);
    http_response_code(401);
    echo json_encode(['http_code' => 401, 'success' => false, 'message' => 'Unauthorized - Invalid or missing API key']);
    exit;
}

writeLog($log_file, "INFO", "API Key        : Validated successfully");

// ============================================
// DB CONNECTION
// ============================================
$conn = new mysqli("localhost", "phpuser", "php123", "pbx_user");
if ($conn->connect_error) {
    writeLog($log_file, "ERROR", "DATABASE — Connection failed: " . $conn->connect_error);
    writeSeparator($log_file);
    fclose($log_file);
    http_response_code(500);
    echo json_encode(['http_code' => 500, 'success' => false, 'message' => 'Database connection failed']);
    exit;
}

writeLog($log_file, "INFO", "Database       : Connected successfully");

// ============================================
// FILE CHECK
// ============================================
if (!isset($_FILES['csv_file']) || $_FILES['csv_file']['error'] !== UPLOAD_ERR_OK) {
    writeLog($log_file, "ERROR", "FILE — No CSV file uploaded or upload error");
    writeSeparator($log_file);
    fclose($log_file);
    http_response_code(400);
    echo json_encode(['http_code' => 400, 'success' => false, 'message' => 'CSV file not uploaded']);
    exit;
}

$file_name = $_FILES['csv_file']['name'];
$file_size = round($_FILES['csv_file']['size'] / 1024, 2);
$file_ext  = strtolower(pathinfo($file_name, PATHINFO_EXTENSION));

writeLog($log_file, "INFO", "File Uploaded  : $file_name");
writeLog($log_file, "INFO", "File Size      : {$file_size}KB");
writeLog($log_file, "INFO", "File Extension : $file_ext");

if ($file_ext !== 'csv') {
    writeLog($log_file, "ERROR", "FILE — Invalid extension '$file_ext'. Only .csv allowed");
    writeSeparator($log_file);
    fclose($log_file);
    http_response_code(400);
    echo json_encode([
        'http_code' => 400,
        'success'   => false,
        'message'   => 'Only .csv files allowed',
        'uploaded'  => $file_name
    ]);
    exit;
}

if ($_FILES['csv_file']['size'] > 5 * 1024 * 1024) {
    writeLog($log_file, "ERROR", "FILE — File size {$file_size}KB exceeds 5MB limit");
    writeSeparator($log_file);
    fclose($log_file);
    http_response_code(400);
    echo json_encode([
        'http_code' => 400,
        'success'   => false,
        'message'   => 'File size must be less than 5MB',
        'file_size' => round($_FILES['csv_file']['size'] / 1024 / 1024, 2) . 'MB'
    ]);
    exit;
}

$file = fopen($_FILES['csv_file']['tmp_name'], 'r');
if (!$file) {
    writeLog($log_file, "ERROR", "FILE — Cannot open uploaded CSV file");
    writeSeparator($log_file);
    fclose($log_file);
    http_response_code(400);
    echo json_encode(['http_code' => 400, 'success' => false, 'message' => 'Cannot open CSV file']);
    exit;
}

// ============================================
// VALIDATE HEADER ROW
// ============================================
$header           = fgetcsv($file);
$header           = array_map('trim', array_map('strtolower', $header));
$required_headers = ['extension', 'password', 'caller_id_name', 'has_ip_phone'];
$missing_headers  = array_diff($required_headers, $header);
$extra_headers    = array_diff($header, $required_headers);

writeLog($log_file, "INFO", "CSV Headers    : " . implode(', ', $header));

if (!empty($missing_headers)) {
    writeLog($log_file, "ERROR", "HEADER — Missing required columns: " . implode(', ', $missing_headers));
    fclose($file);
    writeSeparator($log_file);
    fclose($log_file);
    http_response_code(400);
    echo json_encode([
        'http_code'       => 400,
        'success'         => false,
        'message'         => 'Invalid CSV headers — missing required columns',
        'missing_headers' => array_values($missing_headers),
        'expected'        => $required_headers,
        'got'             => $header
    ]);
    exit;
}

if (!empty($extra_headers)) {
    writeLog($log_file, "ERROR", "HEADER — Extra columns not allowed: " . implode(', ', $extra_headers));
    fclose($file);
    writeSeparator($log_file);
    fclose($log_file);
    http_response_code(400);
    echo json_encode([
        'http_code'       => 400,
        'success'         => false,
        'message'         => 'CSV contains extra headers that are not allowed',
        'extra_headers'   => array_values($extra_headers),
        'allowed_headers' => $required_headers
    ]);
    exit;
}

writeLog($log_file, "INFO", "CSV Headers    : Validated successfully");

// ============================================
// VALIDATE ALL ROWS FIRST
// ============================================
writeSectionHeader($log_file, "VALIDATION PHASE");

$validation_errors = [];
$rows              = [];
$line_number       = 1;

while (($data = fgetcsv($file)) !== false) {
    $line_number++;

    if (empty(array_filter($data))) continue;

    if (count($data) < 4) {
        $msg = "Line $line_number: Expected 4 columns, got " . count($data);
        $validation_errors[] = $msg;
        writeLog($log_file, "WARN", "VALIDATION — $msg");
        continue;
    }

    $extension      = trim($data[0] ?? '');
    $password       = trim($data[1] ?? '');
    $caller_id_name = trim($data[2] ?? '');
    $ip_flag        = strtolower(trim($data[3] ?? ''));

    writeLog($log_file, "INFO", "Validating     : Line $line_number | Extension=$extension | Name=$caller_id_name | has_ip_phone=$ip_flag");

    // Extension
    if (empty($extension)) {
        $msg = "Line $line_number: Extension is empty";
        $validation_errors[] = $msg;
        writeLog($log_file, "WARN", "VALIDATION — $msg");
        continue;
    }
    if (!preg_match('/^\d+$/', $extension)) {
        $msg = "Line $line_number: Extension '$extension' must be numeric only";
        $validation_errors[] = $msg;
        writeLog($log_file, "WARN", "VALIDATION — $msg");
        continue;
    }
    if (strlen($extension) > 12) {
        $msg = "Line $line_number: Extension '$extension' too long (max 12 digits)";
        $validation_errors[] = $msg;
        writeLog($log_file, "WARN", "VALIDATION — $msg");
        continue;
    }

    // Password
//    if (empty($password)) {
//        $msg = "Line $line_number: Password is empty for extension $extension";
//        $validation_errors[] = $msg;
//        writeLog($log_file, "WARN", "VALIDATION — $msg");
//        continue;
 //   }
 //   if (strlen($password) < 4) {
 //       $msg = "Line $line_number: Password too short for extension $extension (min 4 chars)";
 //       $validation_errors[] = $msg;
 //       writeLog($log_file, "WARN", "VALIDATION — $msg");
 //       continue;
 //   }
 //   if (strlen($password) > 12) {
 //       $msg = "Line $line_number: Password too long for extension $extension (max 12 chars)";
 //       $validation_errors[] = $msg;
 //       writeLog($log_file, "WARN", "VALIDATION — $msg");
 //       continue;
 //   }

    // caller_id_name
    if (empty($caller_id_name)) {
        $msg = "Line $line_number: caller_id_name is empty for extension $extension";
        $validation_errors[] = $msg;
        writeLog($log_file, "WARN", "VALIDATION — $msg");
        continue;
    }
    if (strlen($caller_id_name) > 100) {
        $msg = "Line $line_number: caller_id_name too long for extension $extension (max 100 chars)";
        $validation_errors[] = $msg;
        writeLog($log_file, "WARN", "VALIDATION — $msg");
        continue;
    }

    // has_ip_phone
    if (!in_array($ip_flag, ['true', 'false', '1', '0', 'yes', 'no'])) {
        $msg = "Line $line_number: has_ip_phone '$ip_flag' invalid for extension $extension. Use: true/false/1/0/yes/no";
        $validation_errors[] = $msg;
        writeLog($log_file, "WARN", "VALIDATION — $msg");
        continue;
    }

    // Duplicate in CSV
    foreach ($rows as $existing_row) {
        if ($existing_row['extension'] === $extension) {
            $msg = "Line $line_number: Duplicate extension $extension found in CSV";
            $validation_errors[] = $msg;
            writeLog($log_file, "WARN", "DUPLICATE (CSV) — $msg");
            continue 2;
        }
    }

    // Duplicate in DB
    $stmt = $conn->prepare("SELECT id FROM extensions WHERE extension = ?");
    $stmt->bind_param("s", $extension);
    $stmt->execute();
    $stmt->store_result();
    if ($stmt->num_rows > 0) {
        $msg = "Line $line_number: Extension $extension already exists in DB";
        $validation_errors[] = $msg;
        writeLog($log_file, "WARN", "DUPLICATE (DB) — Extension $extension already exists in database — skipped");
        $stmt->close();
        continue;
    }
    $stmt->close();

    writeLog($log_file, "INFO", "VALID          : Extension $extension | $caller_id_name — passed all checks");

    $rows[] = [
        'extension'      => $extension,
        'password'       => $password,
        'caller_id_name' => $caller_id_name,
        'has_ip_phone'   => in_array($ip_flag, ['true', '1', 'yes']) ? 1 : 0,
        'line'           => $line_number
    ];
}

fclose($file);

writeLog($log_file, "INFO", "Total Rows     : " . ($line_number - 1));
writeLog($log_file, "INFO", "Valid Rows     : " . count($rows));
writeLog($log_file, "INFO", "Invalid Rows   : " . count($validation_errors));

// ============================================
// STOP IF VALIDATION ERRORS
// ============================================
if (!empty($validation_errors)) {
    writeSectionHeader($log_file, "VALIDATION FAILED — NO RECORDS INSERTED");
    foreach ($validation_errors as $err) {
        writeLog($log_file, "ERROR", $err);
    }
    writeSeparator($log_file);
    writeLog($log_file, "INFO", "====== UPLOAD ABORTED — FIX ERRORS AND RETRY ======");
    writeSeparator($log_file);
    fclose($log_file);

    http_response_code(400);
    echo json_encode([
        'http_code'         => 400,
        'success'           => false,
        'message'           => 'CSV validation failed. No records inserted.',
        'total_errors'      => count($validation_errors),
        'validation_errors' => $validation_errors
    ]);
    exit;
}

if (empty($rows)) {
    writeLog($log_file, "ERROR", "No valid rows found in CSV");
    writeSeparator($log_file);
    fclose($log_file);
    http_response_code(400);
    echo json_encode(['http_code' => 400, 'success' => false, 'message' => 'No valid rows found in CSV']);
    exit;
}

// ============================================
// ALL VALID — INSERT
// ============================================
writeSectionHeader($log_file, "INSERT PHASE");

$errors   = [];
$inserted = 0;

//$fs_dir   = "/usr/local/freeswitch/conf/directory/default/";
$fs_dir   =  "/usr/local/freeswitch-automax-instance/etc/freeswitch/directory/leaderfs.axionic.io/"; 

foreach ($rows as $row) {
    $extension      = $row['extension'];
    $password       = $row['password'];
    $caller_id_name = $row['caller_id_name'];
    $has_ip_phone   = $row['has_ip_phone'];
    $fs_path        = $fs_dir . $extension . ".xml";

    writeLog($log_file, "INFO", "Processing     : Extension $extension | $caller_id_name | has_ip_phone=" . ($has_ip_phone ? 'true' : 'false'));

    // Insert to DB
    $stmt = $conn->prepare("INSERT INTO extensions (extension, password, name, has_ip_phone) VALUES (?, ?, ?, ?)");
    $stmt->bind_param("sssi", $extension, $password, $caller_id_name, $has_ip_phone);

    if (!$stmt->execute()) {
        $err_msg = "DB insert failed for extension $extension: " . $stmt->error;
        $errors[] = $err_msg;
        writeLog($log_file, "ERROR", "DB INSERT FAILED — Extension $extension — " . $stmt->error);
        $stmt->close();
        continue;
    }
    $stmt->close();

    writeLog($log_file, "INFO", "DB INSERT OK   : Extension $extension inserted into database");

    // Write XML
    $xml_content = "<include>
<user id=\"" . htmlspecialchars($extension, ENT_QUOTES) . "\">
<params>
<param name=\"password\" value=\"" . htmlspecialchars($password, ENT_QUOTES) . "\"/>
<param name=\"vm-password\" value=\"" . htmlspecialchars($password, ENT_QUOTES) . "\"/>
</params>
<variables>
<variable name=\"toll_allow\" value=\"domestic,international,local\"/>
<variable name=\"accountcode\" value=\"" . htmlspecialchars($extension, ENT_QUOTES) . "\"/>
<variable name=\"effective_caller_id_name\" value=\"" . htmlspecialchars($caller_id_name, ENT_QUOTES) . "\"/>
<variable name=\"effective_caller_id_number\" value=\"" . htmlspecialchars($extension, ENT_QUOTES) . "\"/>
<variable name=\"outbound_caller_id_name\" value=\"" . htmlspecialchars($caller_id_name, ENT_QUOTES) . "\"/>
<variable name=\"outbound_caller_id_number\" value=\"" . htmlspecialchars($extension, ENT_QUOTES) . "\"/>
<variable name=\"has_ip_phone\" value=\"" . htmlspecialchars($has_ip_phone, ENT_QUOTES) . "\"/>
</variables>
</user>
</include>";

    if (!is_dir($fs_dir)) mkdir($fs_dir, 0755, true);

    if (file_put_contents($fs_path, $xml_content) === false) {
        // Rollback DB
        $rollback = $conn->prepare("DELETE FROM extensions WHERE extension = ?");
        $rollback->bind_param("s", $extension);
        $rollback->execute();
        $rollback->close();
        $errors[] = "XML write failed for extension $extension — DB rolled back";
        writeLog($log_file, "ERROR", "XML WRITE FAILED — Extension $extension — File: $fs_path — DB entry rolled back");
        continue;
    }

    writeLog($log_file, "INFO", "XML CREATED    : Extension $extension — File: $fs_path");
    $inserted++;
    writeLog($log_file, "INFO", "SUCCESS        : Extension $extension created successfully");
}

// ============================================
// RELOAD FREESWITCH
// ============================================
writeSectionHeader($log_file, "FREESWITCH RELOAD");
$fs_reload = shell_exec("/bin/fs_cli_automax --port 8022 -x 'reloadxml' 2>&1");

//$fs_reload = shell_exec("/usr/local/freeswitch/bin/fs_cli -x 'reloadxml' 2>&1");
writeLog($log_file, "INFO", "ReloadXML      : " . trim($fs_reload));

if (strpos($fs_reload, '+OK') === false) {
    writeLog($log_file, "ERROR", "FREESWITCH RELOAD FAILED — Extensions saved to DB and XML but FreeSWITCH not updated");
    writeSeparator($log_file);
    writeLog($log_file, "INFO", "====== UPLOAD COMPLETED WITH RELOAD ERROR ======");
    writeSeparator($log_file);
    fclose($log_file);

    http_response_code(503);
    echo json_encode([
        'http_code'  => 503,
        'success'    => false,
        'message'    => "Extensions saved but FreeSWITCH reloadxml failed",
        'inserted'   => $inserted,
        'freeswitch' => trim($fs_reload)
    ]);
    exit;
}

writeLog($log_file, "INFO", "FREESWITCH OK  : reloadxml completed successfully");

// ============================================
// SUMMARY LOG
// ============================================
writeSectionHeader($log_file, "UPLOAD SUMMARY");
writeLog($log_file, "INFO", "Total Rows     : " . count($rows));
writeLog($log_file, "INFO", "Inserted       : $inserted");
writeLog($log_file, "INFO", "Failed         : " . count($errors));

if (!empty($errors)) {
    writeLog($log_file, "WARN", "Failed Details :");
    foreach ($errors as $err) {
        writeLog($log_file, "ERROR", "  → $err");
    }
}

writeSeparator($log_file);
writeLog($log_file, "INFO", "====== BULK EXTENSION UPLOAD COMPLETED ======");
writeSeparator($log_file);
fclose($log_file);

// ============================================
// FINAL RESPONSE
// ============================================
if ($inserted > 0 && empty($errors)) {
    http_response_code(200);
    $code = 200;
} elseif ($inserted > 0 && !empty($errors)) {
    http_response_code(207);
    $code = 207;
} else {
    http_response_code(400);
    $code = 400;
}

echo json_encode([
    'http_code'  => $code,
    'success'    => ($inserted > 0),
    'inserted'   => $inserted,
    'total_rows' => count($rows),
    'errors'     => $errors,
    'freeswitch' => trim($fs_reload)
]);

