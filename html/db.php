<?php

error_reporting(E_ALL);
ini_set('display_errors', 1);

$conn = new mysqli("localhost","phpuser","php123","pbx_user");
if ($conn->connect_error) {
    die("DB connection failed: " . $conn->connect_error);
}

echo "Database connected successfully";

?>

