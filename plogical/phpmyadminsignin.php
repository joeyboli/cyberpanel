<?php

// Note: Authentication is handled by Django before reaching this page
// The token validation happens in fetchDetailsPHPMYAdmin view

error_reporting(E_ALL);
ini_set('display_errors', 1);

session_start();

define("PMA_SIGNON_INDEX", 1);

try {
    define('PMA_SIGNON_SESSIONNAME', 'SignonSession');
    define('PMA_DISABLE_SSL_PEER_VALIDATION', TRUE);

    // Merge GET and POST to handle both ways of passing token/username
    $request = array_merge($_GET, $_POST);

    if (isset($request['password']) && isset($request['username'])) {

        session_name(PMA_SIGNON_SESSIONNAME);
        @session_start();

        $username = htmlspecialchars($request['username'], ENT_QUOTES, 'UTF-8');
        $password = $request['password'];

        $_SESSION['PMA_single_signon_user'] = $username;
        $_SESSION['PMA_single_signon_password'] = $password;
        $_SESSION['PMA_single_signon_host'] = 'localhost';

        @session_write_close();

        header('Location: /phpmyadmin/index.php?server=' . PMA_SIGNON_INDEX);
        exit;
        
    } else if (isset($request['token'])) {

        ### Get credentials using the token

        $token = htmlspecialchars($request['token'], ENT_QUOTES, 'UTF-8');
        $username = htmlspecialchars($request['username'], ENT_QUOTES, 'UTF-8');

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
} catch (Exception $e) {
    error_log('phpmyadminsignin error: ' . $e->getMessage());
    echo 'Caught exception: ', $e->getMessage(), "\n";
    $params = session_get_cookie_params();
    setcookie(session_name(), '', time() - 86400, $params["path"], $params["domain"], $params["secure"], $params["httponly"]);
    session_destroy();
    header('Location: /dataBases/phpMyAdmin');
    return;
}
