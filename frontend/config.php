<?php
session_start();

$host = 'database-1.cfmmi4iqyrkp.ap-southeast-1.rds.amazonaws.com';
$dbname = 'webdb';
$username = 'admin'; 
$password = 'admin123';     

try {
    $pdo = new PDO("mysql:host=$host;dbname=$dbname", $username, $password);
    // Set the PDO error mode to exception
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch(PDOException $e) {
    die("Database Connection failed: " . $e->getMessage());
}
?>