<?php

// Note: Authentication is handled by Django before reaching this page
// The token validation happens in fetchDetailsPHPMYAdmin view

error_reporting(E_ALL);
ini_set('display_errors', 1);

session_name('SignonSession');
session_start();

define("PMA_SIGNON_INDEX", 1);
define('PMA_SIGNON_SESSIONNAME', 'SignonSession');
define('PMA_DISABLE_SSL_PEER_VALIDATION', TRUE);

function log_debug($msg) {
    file_put_contents('/home/cyberpanel/phpmyadmin_debug.log', date('[Y-m-d H:i:s] ') . $msg . "\n", FILE_APPEND);
}

try {
    log_debug("Request received: " . json_encode(array_merge($_GET, $_POST)));

    // Merge GET and POST to handle both ways of passing token/username
    $request = array_merge($_GET, $_POST);

    if (isset($request['password']) && isset($request['username'])) {
        log_debug("Processing login for user: " . $request['username']);

        $username = htmlspecialchars($request['username'], ENT_QUOTES, 'UTF-8');
        $password = $request['password'];

        log_debug("Finalizing login with session ID: " . session_id());
        $_SESSION['PMA_single_signon_user'] = $username;
        $_SESSION['PMA_single_signon_password'] = $password;
        $_SESSION['PMA_single_signon_host'] = 'localhost';
        $_SESSION['PMA_single_signon_port'] = '3306'; 
        $_SESSION['PMA_single_signon_cfgupdate'] = array('verbose' => 'CyberPanel');

        session_write_close();
        log_debug("Session closed. Redirecting to phpMyAdmin.");

        header('Location: /phpmyadmin/index.php?server=' . PMA_SIGNON_INDEX);
        exit;
        
    } else if (isset($request['token'])) {

        ### Get credentials using the token

        $token = htmlspecialchars($request['token'], ENT_QUOTES, 'UTF-8');
        $username = isset($request['username']) ? htmlspecialchars($request['username'], ENT_QUOTES, 'UTF-8') : 'root';

        log_debug("Redirecting to fetchDetailsPHPMYAdmin with token for user: " . $username);
        $url = "/dataBases/fetchDetailsPHPMYAdmin";

        // Redirect with POST data
        echo '<form id="redirectForm" action="' . $url . '" method="post">';
        echo '<input type="hidden"  value="' . $token . '" name="token">';
        echo '<input type="hidden"  value="' . $username . '" name="username">';
        echo '</form>';
        echo '<script>document.getElementById("redirectForm").submit();</script>';
        exit;

    } else if (isset($request['logout'])) {
        $params = session_get_cookie_params();
        setcookie(session_name(), '', time() - 86400, $params["path"], $params["domain"], $params["secure"], $params["httponly"]);
        session_destroy();
        header('Location: /base/');
        return;
    }
} catch (Throwable $e) {
    log_debug('phpmyadminsignin error: ' . $e->getMessage());
    error_log('phpmyadminsignin error: ' . $e->getMessage());
    echo 'Caught exception: ', $e->getMessage(), "\n";
    $params = session_get_cookie_params();
    setcookie(session_name(), '', time() - 86400, $params["path"], $params["domain"], $params["secure"], $params["httponly"]);
    session_destroy();
    header('Location: /dataBases/phpMyAdmin');
    return;
}
