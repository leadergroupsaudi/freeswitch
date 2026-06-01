<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

header('Content-Type: application/json');

// ============================================
// LOG FILE SETUP
// ============================================
$log_file = fopen('account_delete.txt', 'a');

function writeLog($fp, $level, $message) {
    $timestamp = date('Y-m-d H:i:s');
    fwrite($fp, "[$timestamp] [$level] $message" . PHP_EOL);
}

function writeSeparator($fp) {
    fwrite($fp, str_repeat("=", 80) . PHP_EOL);
}

function writeSectionHeader($fp, $title) {
    fwrite($fp, str_repeat("-", 80) . PHP_EOL);
    fwrite($fp, "  $title" . PHP_EOL);
    fwrite($fp, str_repeat("-", 80) . PHP_EOL);
}

writeSeparator($log_file);
writeLog($log_file, "INFO", "====== BULK EXTENSION DELETE STARTED ======");
writeLog($log_file, "INFO", "Request IP   : " . ($_SERVER['REMOTE_ADDR'] ?? 'unknown'));
writeLog($log_file, "INFO", "Request Time : " . date('Y-m-d H:i:s'));
writeSeparator($log_file);

// ============================================
// API KEY CHECK
// ============================================
$valid_api_key   = 'LeaderFS@Axionic#2026';
$request_api_key = $_SERVER['HTTP_X_API_KEY'] ?? '';

if ($request_api_key !== $valid_api_key) {
    writeLog($log_file, "ERROR", "UNAUTHORIZED — Invalid or missing API key");
    writeSeparator($log_file);
    fclose($log_file);
    http_response_code(401);
    echo json_encode(['http_code' => 401, 'success' => false, 'message' => 'Unauthorized - Invalid or missing API key']);
    exit;
}

writeLog($log_file, "INFO", "API Key      : Validated successfully");

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

writeLog($log_file, "INFO", "Database     : Connected successfully");

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

writeLog($log_file, "INFO", "File Uploaded : $file_name");
writeLog($log_file, "INFO", "File Size     : {$file_size}KB");
writeLog($log_file, "INFO", "File Extension: $file_ext");

// File extension check
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

// File size check max 5MB
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
$required_headers = ['extension'];
$missing_headers  = array_diff($required_headers, $header);
$extra_headers    = array_diff($header, $required_headers);

writeLog($log_file, "INFO", "CSV Headers  : " . implode(', ', $header));

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


writeLog($log_file, "INFO", "CSV Headers  : Validated successfully");

// ============================================
// VALIDATE ALL ROWS FIRST
// ============================================
writeSectionHeader($log_file, "VALIDATION PHASE");

$validation_errors = [];
$rows              = [];
$line_number       = 1;

while (($data = fgetcsv($file)) !== false) {
    $line_number++;

    // Skip blank lines
    if (empty(array_filter($data))) continue;

    // Check column count
    if (count($data) < 1) {
        $msg = "Line $line_number: Expected 1 column (extension), got " . count($data);
        $validation_errors[] = $msg;
        writeLog($log_file, "WARN", "VALIDATION — $msg");
        continue;
    }

    $extension = trim($data[0] ?? '');

    writeLog($log_file, "INFO", "Validating   : Line $line_number | Extension=$extension");

    // Extension empty check
    if (empty($extension)) {
        $msg = "Line $line_number: Extension is empty";
        $validation_errors[] = $msg;
        writeLog($log_file, "WARN", "VALIDATION — $msg");
        continue;
    }

    // Extension numeric check
    if (!preg_match('/^\d+$/', $extension)) {
        $msg = "Line $line_number: Extension '$extension' must be numeric only";
        $validation_errors[] = $msg;
        writeLog($log_file, "WARN", "VALIDATION — $msg");
        continue;
    }

    // Extension max length
    if (strlen($extension) > 12) {
        $msg = "Line $line_number: Extension '$extension' too long (max 12 digits)";
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

    // Check exists in DB
    $stmt = $conn->prepare("SELECT id FROM extensions WHERE extension = ?");
    $stmt->bind_param("s", $extension);
    $stmt->execute();
    $stmt->store_result();
    $exists = $stmt->num_rows > 0;
    $stmt->close();

    if (!$exists) {
        $msg = "Line $line_number: Extension $extension not found in DB — cannot delete";
        $validation_errors[] = $msg;
        writeLog($log_file, "WARN", "NOT FOUND — Extension $extension does not exist in database");
        continue;
    }

    writeLog($log_file, "INFO", "VALID        : Extension $extension exists — ready to delete");

    $rows[] = [
        'extension' => $extension,
        'line'      => $line_number
    ];
}

fclose($file);

writeLog($log_file, "INFO", "Total Rows   : " . ($line_number - 1));
writeLog($log_file, "INFO", "Valid Rows   : " . count($rows));
writeLog($log_file, "INFO", "Invalid Rows : " . count($validation_errors));

// ============================================
// STOP IF VALIDATION ERRORS
// ============================================
if (!empty($validation_errors)) {
    writeSectionHeader($log_file, "VALIDATION FAILED — NO RECORDS DELETED");
    foreach ($validation_errors as $err) {
        writeLog($log_file, "ERROR", $err);
    }
    writeSeparator($log_file);
    writeLog($log_file, "INFO", "====== DELETE ABORTED — FIX ERRORS AND RETRY ======");
    writeSeparator($log_file);
    fclose($log_file);

    http_response_code(400);
    echo json_encode([
        'http_code'         => 400,
        'success'           => false,
        'message'           => 'CSV validation failed. No records deleted.',
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
// ALL VALID — DELETE
// ============================================
writeSectionHeader($log_file, "DELETE PHASE");

$errors  = [];
$deleted = 0;
$fs_dir  = "/usr/local/freeswitch-automax-instance/etc/freeswitch/directory/leaderfs.axionic.io/";

foreach ($rows as $row) {
    $extension = $row['extension'];
    $fs_path   = $fs_dir . $extension . ".xml";

    writeLog($log_file, "INFO", "Processing   : Deleting extension $extension");

    // Delete from DB
    $stmt = $conn->prepare("DELETE FROM extensions WHERE extension = ?");
    $stmt->bind_param("s", $extension);

    if (!$stmt->execute()) {
        $err_msg = "DB delete failed for extension $extension: " . $stmt->error;
        $errors[] = $err_msg;
        writeLog($log_file, "ERROR", "DB DELETE FAILED — Extension $extension — " . $stmt->error);
        $stmt->close();
        continue;
    }
    $stmt->close();

    writeLog($log_file, "INFO", "DB DELETE OK : Extension $extension deleted from database");

    // Delete XML file
    if (file_exists($fs_path)) {
        if (!unlink($fs_path)) {
            $err_msg = "XML delete failed for extension $extension — DB entry already deleted";
            $errors[] = $err_msg;
            writeLog($log_file, "ERROR", "XML DELETE FAILED — Extension $extension — File: $fs_path");
            continue;
        }
        writeLog($log_file, "INFO", "XML DELETED  : Extension $extension — File: $fs_path");
    } else {
        writeLog($log_file, "WARN", "XML NOT FOUND: Extension $extension — File: $fs_path (already missing)");
    }

    $deleted++;
    writeLog($log_file, "INFO", "SUCCESS      : Extension $extension deleted successfully");
}

// ============================================
// RELOAD FREESWITCH
// ============================================
writeSectionHeader($log_file, "FREESWITCH RELOAD");

$fs_reload = shell_exec("/bin/fs_cli_automax --port 8022 -x 'reloadxml' 2>&1");
writeLog($log_file, "INFO", "ReloadXML    : " . trim($fs_reload));

if (strpos($fs_reload, '+OK') === false) {
    writeLog($log_file, "ERROR", "FREESWITCH RELOAD FAILED — Extensions deleted from DB and XML but FreeSWITCH not updated");
    writeSeparator($log_file);
    writeLog($log_file, "INFO", "====== DELETE COMPLETED WITH RELOAD ERROR ======");
    writeSeparator($log_file);
    fclose($log_file);

    http_response_code(503);
    echo json_encode([
        'http_code'  => 503,
        'success'    => false,
        'message'    => "Extensions deleted but FreeSWITCH reloadxml failed",
        'deleted'    => $deleted,
        'freeswitch' => trim($fs_reload)
    ]);
    exit;
}

writeLog($log_file, "INFO", "FREESWITCH OK: reloadxml completed successfully");

// ============================================
// SUMMARY LOG
// ============================================
writeSectionHeader($log_file, "DELETE SUMMARY");
writeLog($log_file, "INFO", "Total Rows   : " . count($rows));
writeLog($log_file, "INFO", "Deleted      : $deleted");
writeLog($log_file, "INFO", "Failed       : " . count($errors));

if (!empty($errors)) {
    writeLog($log_file, "WARN", "Failed Details:");
    foreach ($errors as $err) {
        writeLog($log_file, "ERROR", "  → $err");
    }
}

writeSeparator($log_file);
writeLog($log_file, "INFO", "====== BULK EXTENSION DELETE COMPLETED ======");
writeSeparator($log_file);
fclose($log_file);

// ============================================
// FINAL RESPONSE
// ============================================
if ($deleted > 0 && empty($errors)) {
    http_response_code(200);
    $code = 200;
} elseif ($deleted > 0 && !empty($errors)) {
    http_response_code(207);
    $code = 207;
} else {
    http_response_code(400);
    $code = 400;
}

echo json_encode([
    'http_code'  => $code,
    'success'    => ($deleted > 0),
    'deleted'    => $deleted,
    'total_rows' => count($rows),
    'errors'     => $errors,
    'freeswitch' => trim($fs_reload)
]);
?>
