<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

// ============================================
// API KEY AUTHENTICATION
// ============================================
$valid_api_key   = 'LeaderFS@Axionic#2026';
$request_api_key = $_SERVER['HTTP_X_API_KEY'] ?? '';

header('Content-Type: application/json');

if ($request_api_key !== $valid_api_key) {
    http_response_code(401);
    echo json_encode([
        'http_code' => 401,
        'success'   => false,
        'message'   => 'Unauthorized - Invalid or missing API key'
    ]);
    exit;
}

// ============================================
// DB CONNECTION
// ============================================
$conn = new mysqli("localhost", "phpuser", "php123", "pbx_user");
if ($conn->connect_error) {
    http_response_code(500);
    echo json_encode([
        'http_code' => 500,
        'success'   => false,
        'message'   => 'DB connection failed'
    ]);
    exit;
}

// ============================================
// INPUT — Support JSON + POST + GET
// ============================================
$data = json_decode(file_get_contents("php://input"), true);

$action    = $data['action']         ?? $_POST['action']         ?? $_GET['action']         ?? '';
$extension = $data['extension']      ?? $_POST['extension']      ?? $_GET['extension']      ?? '';
$password  = $data['password']       ?? $_POST['password']       ?? $_GET['password']       ?? '';
$name      = $data['caller_id_name'] ?? $_POST['caller_id_name'] ?? $_GET['caller_id_name'] ?? '';

$fp_rangeapi = fopen('extension.txt', 'a');
$date=date('Y-m-d H:m:s');

fwrite($fp_rangeapi, " action:".$action."\n");
fwrite($fp_rangeapi, " extension:".$extension."\n");
fwrite($fp_rangeapi, " password :".$password."\n");

fwrite($fp_rangeapi, " name :".$name."\n");

fwrite($fp_rangeapi, " date :".$date."\n");



// has_ip_phone — use isset to correctly handle false
if (isset($data['has_ip_phone'])) {
    $has_ip_phone = filter_var($data['has_ip_phone'], FILTER_VALIDATE_BOOLEAN) ? 1 : 0;
} elseif (isset($_POST['has_ip_phone'])) {
    $has_ip_phone = filter_var($_POST['has_ip_phone'], FILTER_VALIDATE_BOOLEAN) ? 1 : 0;
} elseif (isset($_GET['has_ip_phone'])) {
    $has_ip_phone = filter_var($_GET['has_ip_phone'], FILTER_VALIDATE_BOOLEAN) ? 1 : 0;
} else {
    $has_ip_phone = null;
}


fwrite($fp_rangeapi, " has_ip :".$has_ip_phone."\n");
fwrite($fp_rangeapi, " -------------------------------------------- :"."\n");
$fs_path = "/usr/local/freeswitch-automax-instance/etc/freeswitch/directory/leaderfs.axionic.io/" . $extension . ".xml";

// ============================================
// HELPERS
// ============================================
function respond($code, $data) {
    http_response_code($code);
    echo json_encode(array_merge(['http_code' => $code], $data));
    exit;
}

function reloadFreeSWITCH($extension) {
    $fs_reload = shell_exec("/bin/fs_cli_automax --port 8022 -x 'reloadxml' 2>&1");
    if (strpos($fs_reload, '+OK') === false) {
        respond(503, [
            'success'    => false,
            'message'    => "Extension $extension saved but FreeSWITCH reloadxml failed",
            'freeswitch' => trim($fs_reload)
        ]);
    }
    return trim($fs_reload);
}

function extensionExists($conn, $extension) {
    $stmt = $conn->prepare("SELECT id FROM extensions WHERE extension = ?");
    $stmt->bind_param("s", $extension);
    $stmt->execute();
    $stmt->store_result();
    $exists = $stmt->num_rows > 0;
    $stmt->close();
    return $exists;
}

function getExtension($conn, $extension) {
    $stmt = $conn->prepare("SELECT extension, password, name, has_ip_phone FROM extensions WHERE extension = ?");
    $stmt->bind_param("s", $extension);
    $stmt->execute();
    $result = $stmt->get_result();
    $row    = $result->fetch_assoc();
    $stmt->close();
    return $row;
}

function buildXml($extension, $password, $name, $has_ip_phone) {
    return "<include>
<user id=\"$extension\">
<params>
<param name=\"password\" value=\"$password\"/>
<param name=\"vm-password\" value=\"$password\"/>
</params>
<variables>
<variable name=\"toll_allow\" value=\"domestic,international,local\"/>
<variable name=\"accountcode\" value=\"$extension\"/>
<variable name=\"effective_caller_id_name\" value=\"$name\"/>
<variable name=\"effective_caller_id_number\" value=\"$extension\"/>
<variable name=\"outbound_caller_id_name\" value=\"$name\"/>
<variable name=\"outbound_caller_id_number\" value=\"$extension\"/>
<variable name=\"has_ip_phone\" value=\"$has_ip_phone\"/>
</variables>
</user>
</include>";
}

// ============================================
// CREATE
// ============================================
if ($action == "create") {

    if (empty($extension) || empty($password) || empty($name)) {
        respond(400, [
            'success' => false,
            'message' => "extension, password and caller_id_name are required"
        ]);
    }

    if (extensionExists($conn, $extension)) {
        respond(409, [
            'success' => false,
            'message' => "Extension $extension already exists. Use action=update to modify it."
        ]);
    }

    $ip_phone_val = ($has_ip_phone !== null) ? $has_ip_phone : 0;

    $stmt = $conn->prepare("INSERT INTO extensions (extension, password, name, has_ip_phone) VALUES (?, ?, ?, ?)");
    $stmt->bind_param("sssi", $extension, $password, $name, $ip_phone_val);

    if (!$stmt->execute()) {
        respond(500, ['success' => false, 'message' => "DB insert failed: " . $stmt->error]);
    }
    $stmt->close();

    // Write XML
    if (file_put_contents($fs_path, buildXml($extension, $password, $name,$has_ip_phone )) === false) {
        // Rollback DB
        $rollback = $conn->prepare("DELETE FROM extensions WHERE extension = ?");
        $rollback->bind_param("s", $extension);
        $rollback->execute();
        $rollback->close();
        respond(500, [
            'success'  => false,
            'message'  => "Failed to write XML file. DB entry rolled back.",
            'rollback' => true
        ]);
    }

    // Reload FreeSWITCH — 503 if fails
    $fs_reload = reloadFreeSWITCH($extension);

    respond(201, [
        'success'        => true,
        'message'        => "Extension $extension created successfully",
        'extension'      => $extension,
        'caller_id_name' => $name,
        'has_ip_phone'   => (bool)$ip_phone_val,
        'freeswitch'     => $fs_reload
    ]);
}

// ============================================
// UPDATE
// ============================================
elseif ($action == "update") {

    if (empty($extension)) {
        respond(400, ['success' => false, 'message' => "extension is required"]);
    }

    if (!extensionExists($conn, $extension)) {
        respond(404, [
            'success' => false,
            'message' => "Extension $extension not found. Use action=create to add it."
        ]);
    }

    $existing     = getExtension($conn, $extension);
    $new_password = !empty($password) ? $password : $existing['password'];
    $new_name     = !empty($name)     ? $name     : $existing['name'];
    $new_ip_phone = ($has_ip_phone !== null) ? $has_ip_phone : $existing['has_ip_phone'];

    $changed = [];
    if ($new_password !== $existing['password'])          $changed[] = 'password';
    if ($new_name     !== $existing['name'])              $changed[] = 'caller_id_name';
    if ((int)$new_ip_phone !== (int)$existing['has_ip_phone']) $changed[] = 'has_ip_phone';

    if (empty($changed)) {
        respond(400, [
            'success' => false,
            'message' => "Nothing to update - same values provided for extension $extension"
        ]);
    }

    $stmt = $conn->prepare("UPDATE extensions SET password = ?, name = ?, has_ip_phone = ? WHERE extension = ?");
    $stmt->bind_param("ssis", $new_password, $new_name, $new_ip_phone, $extension);

    if (!$stmt->execute()) {
        respond(500, ['success' => false, 'message' => "DB update failed: " . $stmt->error]);
    }
    $stmt->close();

    // Write XML
    if (file_put_contents($fs_path, buildXml($extension, $new_password, $new_name, $new_ip_phone)) === false) {
        // Rollback DB
        $rollback = $conn->prepare("UPDATE extensions SET password = ?, name = ?, has_ip_phone = ? WHERE extension = ?");
        $rollback->bind_param("ssis", $existing['password'], $existing['name'], $existing['has_ip_phone'], $extension);
        $rollback->execute();
        $rollback->close();
        respond(500, [
            'success'  => false,
            'message'  => "Failed to write XML file. DB rolled back to previous values.",
            'rollback' => true
        ]);
    }

    // Reload FreeSWITCH — 503 if fails
    $fs_reload = reloadFreeSWITCH($extension);

    respond(200, [
        'success'        => true,
        'message'        => "Extension $extension updated successfully",
        'extension'      => $extension,
        'updated'        => $changed,
        'caller_id_name' => $new_name,
        'password'       => $new_password,
        'has_ip_phone'   => (bool)$new_ip_phone,
        'freeswitch'     => $fs_reload
    ]);
}

// ============================================
// DELETE
// ============================================
elseif ($action == "delete") {

    if (empty($extension)) {
        respond(400, ['success' => false, 'message' => "extension is required"]);
    }

    if (!extensionExists($conn, $extension)) {
        respond(404, [
            'success' => false,
            'message' => "Extension $extension not found. Nothing to delete."
        ]);
    }

    $stmt = $conn->prepare("DELETE FROM extensions WHERE extension = ?");
    $stmt->bind_param("s", $extension);

    if (!$stmt->execute()) {
        respond(500, ['success' => false, 'message' => "DB delete failed: " . $stmt->error]);
    }
    $stmt->close();

    if (file_exists($fs_path)) {
        if (!unlink($fs_path)) {
            respond(500, [
                'success'  => false,
                'message'  => "Failed to delete XML file for extension $extension.",
                'rollback' => true
            ]);
        }
    }

    // Reload FreeSWITCH — 503 if fails
    $fs_reload = reloadFreeSWITCH($extension);

    respond(200, [
        'success'    => true,
        'message'    => "Extension $extension deleted successfully",
        'extension'  => $extension,
        'freeswitch' => $fs_reload
    ]);
}

// ============================================
// INVALID ACTION
// ============================================
else {
    respond(400, [
        'success' => false,
        'message' => "Invalid action. Use: create, update, delete"
    ]);
}
?>
