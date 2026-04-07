<?php
require 'config.php';

if (isset($_SESSION['user_id'])) {
    header("Location: index.php");
    exit;
}

$error = '';
$success = '';

if (isset($_GET['signup']) && $_GET['signup'] == 'success') {
    $success = "Account created successfully! Please log in.";
}

if ($_SERVER["REQUEST_METHOD"] == "POST") {
    $email = trim($_POST['email']);
    $password = $_POST['password'];

    $stmt = $pdo->prepare("SELECT id, email, password FROM users WHERE email = ?");
    $stmt->execute([$email]);
    $user = $stmt->fetch();

    if ($user && password_verify($password, $user['password'])) {
        // Password is correct, set session
        $_SESSION['user_id'] = $user['id'];
        $_SESSION['user_email'] = $user['email'];
        header("Location: index.php");
        exit;
    } else {
        $error = "Invalid email or password.";
    }
}
?>

<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Login — Soirée</title>
  <link rel="stylesheet" href="styles.css" />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,400;0,500;0,600;1,300;1,400&family=Josefin+Sans:wght@300;400;500&display=swap" rel="stylesheet" />
</head>
<body>

  <!-- HEADER -->
  <header class="site-header">
    <div class="header-inner">
      <a href="index.php" class="logo">
        <span class="logo-mark">◆</span>
        <span class="logo-text">Soirée</span>
      </a>
    </div>
  </header>

  <!-- AUTH CONTAINER -->
  <section class="auth-container">
    <div class="auth-form-wrapper">
      <div class="auth-header">
        <h1 class="auth-title">Welcome Back</h1>
        <p class="auth-subtitle">Sign in to your account</p>
      </div>

        <?php if($error): ?>
          <div style="color: #c94c4c; font-size: 13px; margin-bottom: 15px; text-align: center;">
              <?php echo $error; ?>
          </div>
        <?php endif; ?>
        <?php if($success): ?>
          <div style="color: #4caf7d; font-size: 13px; margin-bottom: 15px; text-align: center;">
              <?php echo $success; ?>
          </div>
        <?php endif; ?>

        <form class="auth-form" id="loginForm" method="POST" action="login.php">
          <div class="form-group">
            <label for="email" class="form-label">Email Address</label>
            <input type="email" id="email" name="email" class="form-input" placeholder="you@example.com" required />
          </div>

          <div class="form-group">
            <label for="password" class="form-label">Password</label>
            <input type="password" id="password" name="password" class="form-input" placeholder="••••••••" required />
          </div>

          <button type="submit" class="btn-primary auth-submit">Sign In</button>
        </form>

      <p class="auth-footer">
        Don't have an account? 
        <a href="signup.php" class="form-link auth-link">Sign Up</a>
      </p>
    </div>
  </section>

</body>
</html>
