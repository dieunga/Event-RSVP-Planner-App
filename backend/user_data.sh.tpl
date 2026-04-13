#!/bin/bash
set -e
exec > /var/log/user-data.log 2>&1

echo "=== Starting EC2 setup ==="

# ==========================================
# Install packages
# ==========================================
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  apache2 php libapache2-mod-php php-mysql php-cli \
  php-curl php-xml php-mbstring php-zip \
  unzip curl composer mysql-client awscli

# ==========================================
# Configure Apache
# ==========================================
a2enmod rewrite

# Prefer index.php over index.html
sed -i 's/DirectoryIndex index\.html/DirectoryIndex index.php index.html/' /etc/apache2/mods-enabled/dir.conf

# Allow .htaccess overrides
cat > /etc/apache2/conf-available/webapp.conf << 'CONFEOF'
<Directory /var/www/html>
    AllowOverride All
    Options Indexes FollowSymLinks
    Require all granted
</Directory>
CONFEOF
a2enconf webapp

# ==========================================
# Deploy app files from S3
# ==========================================
aws s3 sync s3://${s3_bucket}/app/ /var/www/html/ --region ${aws_region}

# ==========================================
# Write config.php with live DB details
# ==========================================
cat > /var/www/html/config.php << 'PHPEOF'
<?php
session_start();

$host     = '${rds_address}';
$dbname   = '${db_name}';
$username = '${db_username}';
$password = '${db_password}';

try {
    $pdo = new PDO("mysql:host=$host;dbname=$dbname", $username, $password);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch(PDOException $e) {
    die("Database Connection failed: " . $e->getMessage());
}
?>
PHPEOF

# ==========================================
# Initialize DB schema (with retry)
# ==========================================
DB_HOST="${rds_address}"
DB_USER="${db_username}"
DB_PASS="${db_password}"
DB_NAME="${db_name}"

echo "=== Waiting for database to be reachable ==="
for i in $(seq 1 20); do
  if mysql -h "$DB_HOST" -u "$DB_USER" "-p$DB_PASS" -e "SELECT 1" 2>/dev/null; then
    echo "Database is ready."
    break
  fi
  echo "Attempt $i/20 - retrying in 15s..."
  sleep 15
done

mysql -h "$DB_HOST" -u "$DB_USER" "-p$DB_PASS" "$DB_NAME" << 'SQLEOF'
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL
);
SQLEOF

echo "=== Schema initialized ==="

# ==========================================
# Finalize permissions and start Apache
# ==========================================
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

systemctl enable apache2
systemctl restart apache2

echo "=== Setup complete ==="
