# ==========================================
# Security Group — Monitoring EC2
# ==========================================
resource "aws_security_group" "monitoring_sg" {
  name        = "monitoring-sg"
  description = "Allow access to Prometheus, Grafana, and Splunk"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Splunk Web UI"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Splunk HEC"
    from_port   = 8088
    to_port     = 8088
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "monitoring-sg" }
}

# ==========================================
# EC2 Instance — Monitoring
# ==========================================
resource "aws_instance" "monitoring" {
  ami                         = var.ami_id
  instance_type               = "t3.medium"
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.web_subnet.id
  vpc_security_group_ids      = [aws_security_group.monitoring_sg.id]
  user_data_replace_on_change = true

  user_data = <<-EOT
    #!/bin/bash
    exec > /var/log/monitoring-setup.log 2>&1
    set -x

    echo "=== Waiting for apt lock ==="
    for i in $(seq 1 30); do
      if flock -n /var/lib/dpkg/lock-frontend -c true 2>/dev/null && \
         flock -n /var/lib/apt/lists/lock -c true 2>/dev/null; then
        echo "apt lock is free"
        break
      fi
      echo "Waiting... $i/30"
      sleep 10
    done

    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      curl wget unzip gnupg2 software-properties-common apt-transport-https

    # ==========================================
    # Install Prometheus
    # ==========================================
    PROM_VERSION="2.51.0"
    wget -q "https://github.com/prometheus/prometheus/releases/download/v$${PROM_VERSION}/prometheus-$${PROM_VERSION}.linux-amd64.tar.gz" -O /tmp/prometheus.tar.gz
    tar -xzf /tmp/prometheus.tar.gz -C /tmp
    mv /tmp/prometheus-$${PROM_VERSION}.linux-amd64/prometheus /usr/local/bin/
    mv /tmp/prometheus-$${PROM_VERSION}.linux-amd64/promtool /usr/local/bin/
    mkdir -p /etc/prometheus /var/lib/prometheus

    cat > /etc/prometheus/prometheus.yml << 'PROMEOF'
    global:
      scrape_interval: 15s

    scrape_configs:
      - job_name: 'prometheus'
        static_configs:
          - targets: ['localhost:9090']
    PROMEOF

    useradd --no-create-home --shell /bin/false prometheus
    chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

    cat > /etc/systemd/system/prometheus.service << 'SVCEOF'
    [Unit]
    Description=Prometheus
    After=network.target

    [Service]
    User=prometheus
    ExecStart=/usr/local/bin/prometheus \
      --config.file=/etc/prometheus/prometheus.yml \
      --storage.tsdb.path=/var/lib/prometheus \
      --storage.tsdb.retention.time=15d \
      --web.listen-address=0.0.0.0:9090
    Restart=always

    [Install]
    WantedBy=multi-user.target
    SVCEOF

    systemctl daemon-reload
    systemctl enable prometheus
    systemctl start prometheus

    # ==========================================
    # Install Grafana
    # ==========================================
    wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
    echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" \
      > /etc/apt/sources.list.d/grafana.list
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y grafana

    cat > /etc/grafana/provisioning/datasources/prometheus.yaml << 'GRAFEOF'
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        url: http://localhost:9090
        isDefault: true
        editable: true
    GRAFEOF

    systemctl daemon-reload
    systemctl enable grafana-server
    systemctl start grafana-server

    # ==========================================
    # Install Splunk Enterprise
    # ==========================================
    SPLUNK_VERSION="9.2.1"
    SPLUNK_BUILD="78803f08aabb"
    wget -q -O /tmp/splunk.deb \
      "https://download.splunk.com/products/splunk/releases/$${SPLUNK_VERSION}/linux/splunk-$${SPLUNK_VERSION}-$${SPLUNK_BUILD}-linux-2.6-amd64.deb"
    dpkg -i /tmp/splunk.deb

    /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt \
      --seed-passwd "SoireeSplunk2026!"

    /opt/splunk/bin/splunk enable boot-start -systemd-managed 1 --accept-license --answer-yes --no-prompt

    systemctl enable Splunkd
    systemctl start Splunkd

    echo "=== Monitoring setup complete ==="
  EOT

  tags = { Name = "monitoring machine" }
}

resource "aws_eip" "monitoring_eip" {
  domain   = "vpc"
  instance = aws_instance.monitoring.id
  tags     = { Name = "monitoring-eip" }
}

# ==========================================
# Outputs
# ==========================================
output "monitoring_public_ip" {
  description = "Monitoring server public IP"
  value       = aws_eip.monitoring_eip.public_ip
}

output "monitoring_urls" {
  description = "Monitoring service URLs"
  value = {
    prometheus = "http://${aws_eip.monitoring_eip.public_ip}:9090"
    grafana    = "http://${aws_eip.monitoring_eip.public_ip}:3000"
    splunk     = "http://${aws_eip.monitoring_eip.public_ip}:8000"
  }
}
