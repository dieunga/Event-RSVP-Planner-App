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
      - job_name: 'node'
        static_configs:
          - targets: ['localhost:9100']
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
    # Install Node Exporter
    # ==========================================
    NODE_EXP_VERSION="1.7.0"
    wget -q "https://github.com/prometheus/node_exporter/releases/download/v$${NODE_EXP_VERSION}/node_exporter-$${NODE_EXP_VERSION}.linux-amd64.tar.gz" -O /tmp/node_exporter.tar.gz
    tar -xzf /tmp/node_exporter.tar.gz -C /tmp
    mv /tmp/node_exporter-$${NODE_EXP_VERSION}.linux-amd64/node_exporter /usr/local/bin/
    useradd --no-create-home --shell /bin/false node_exporter || true

    cat > /etc/systemd/system/node_exporter.service << 'NODEEOF'
    [Unit]
    Description=Node Exporter
    After=network.target

    [Service]
    User=node_exporter
    ExecStart=/usr/local/bin/node_exporter
    Restart=always

    [Install]
    WantedBy=multi-user.target
    NODEEOF

    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl start node_exporter

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

    # ---- Dashboard provisioner config ----
    mkdir -p /var/lib/grafana/dashboards

    cat > /etc/grafana/provisioning/dashboards/default.yaml << 'DASHPROVEOF'
    apiVersion: 1
    providers:
      - name: default
        orgId: 1
        folder: Server Monitoring
        type: file
        disableDeletion: false
        updateIntervalSeconds: 30
        options:
          path: /var/lib/grafana/dashboards
    DASHPROVEOF

    # ---- Server Monitoring Dashboard JSON ----
    cat > /var/lib/grafana/dashboards/server-monitoring.json << 'DASHEOF'
    {
      "annotations": {"list": []},
      "editable": true,
      "graphTooltip": 1,
      "id": null,
      "panels": [
        {
          "datasource": {"type": "prometheus"},
          "fieldConfig": {
            "defaults": {
              "color": {"mode": "palette-classic"},
              "custom": {"drawStyle": "line", "fillOpacity": 10, "lineWidth": 2, "showPoints": "never"},
              "max": 100, "min": 0, "unit": "percent",
              "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "yellow", "value": 70}, {"color": "red", "value": 90}]}
            },
            "overrides": []
          },
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
          "id": 1,
          "options": {"legend": {"calcs": ["mean", "max", "lastNotNull"], "displayMode": "table", "placement": "bottom", "showLegend": true}, "tooltip": {"mode": "multi"}},
          "targets": [
            {"datasource": {"type": "prometheus"}, "expr": "100 - (avg by(instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)", "legendFormat": "CPU Usage %", "refId": "A"}
          ],
          "title": "CPU Usage",
          "type": "timeseries"
        },
        {
          "datasource": {"type": "prometheus"},
          "fieldConfig": {
            "defaults": {
              "color": {"mode": "palette-classic"},
              "custom": {"drawStyle": "line", "fillOpacity": 10, "lineWidth": 2, "showPoints": "never"},
              "max": 100, "min": 0, "unit": "percent"
            },
            "overrides": []
          },
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
          "id": 2,
          "options": {"legend": {"calcs": ["mean", "max", "lastNotNull"], "displayMode": "table", "placement": "bottom", "showLegend": true}},
          "targets": [
            {"datasource": {"type": "prometheus"}, "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100", "legendFormat": "Memory Usage %", "refId": "A"}
          ],
          "title": "Memory Usage",
          "type": "timeseries"
        },
        {
          "datasource": {"type": "prometheus"},
          "fieldConfig": {
            "defaults": {
              "color": {"mode": "palette-classic"},
              "custom": {"drawStyle": "line", "fillOpacity": 10, "lineWidth": 2, "showPoints": "never"},
              "unit": "Bps"
            },
            "overrides": []
          },
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
          "id": 3,
          "options": {"legend": {"calcs": ["mean", "max"], "displayMode": "table", "placement": "bottom", "showLegend": true}},
          "targets": [
            {"datasource": {"type": "prometheus"}, "expr": "rate(node_disk_read_bytes_total[5m])", "legendFormat": "Read - {{device}}", "refId": "A"},
            {"datasource": {"type": "prometheus"}, "expr": "rate(node_disk_written_bytes_total[5m])", "legendFormat": "Write - {{device}}", "refId": "B"}
          ],
          "title": "Disk I/O",
          "type": "timeseries"
        },
        {
          "datasource": {"type": "prometheus"},
          "fieldConfig": {
            "defaults": {
              "color": {"mode": "palette-classic"},
              "custom": {"drawStyle": "line", "fillOpacity": 10, "lineWidth": 2, "showPoints": "never"},
              "unit": "Bps"
            },
            "overrides": []
          },
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
          "id": 4,
          "options": {"legend": {"calcs": ["mean", "max"], "displayMode": "table", "placement": "bottom", "showLegend": true}},
          "targets": [
            {"datasource": {"type": "prometheus"}, "expr": "rate(node_network_receive_bytes_total{device!=\"lo\"}[5m])", "legendFormat": "In - {{device}}", "refId": "A"},
            {"datasource": {"type": "prometheus"}, "expr": "rate(node_network_transmit_bytes_total{device!=\"lo\"}[5m])", "legendFormat": "Out - {{device}}", "refId": "B"}
          ],
          "title": "Network Traffic",
          "type": "timeseries"
        },
        {
          "datasource": {"type": "prometheus"},
          "fieldConfig": {
            "defaults": {
              "color": {"mode": "palette-classic"},
              "custom": {"drawStyle": "line", "fillOpacity": 10, "lineWidth": 2, "showPoints": "never"},
              "unit": "short"
            },
            "overrides": []
          },
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
          "id": 5,
          "options": {"legend": {"calcs": ["mean", "max"], "displayMode": "table", "placement": "bottom", "showLegend": true}},
          "targets": [
            {"datasource": {"type": "prometheus"}, "expr": "node_load1", "legendFormat": "1m", "refId": "A"},
            {"datasource": {"type": "prometheus"}, "expr": "node_load5", "legendFormat": "5m", "refId": "B"},
            {"datasource": {"type": "prometheus"}, "expr": "node_load15", "legendFormat": "15m", "refId": "C"}
          ],
          "title": "System Load Average",
          "type": "timeseries"
        },
        {
          "datasource": {"type": "prometheus"},
          "fieldConfig": {
            "defaults": {
              "color": {"mode": "palette-classic"},
              "custom": {"drawStyle": "line", "fillOpacity": 10, "lineWidth": 2, "showPoints": "never"},
              "unit": "percentunit"
            },
            "overrides": []
          },
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
          "id": 6,
          "options": {"legend": {"calcs": ["mean", "lastNotNull"], "displayMode": "table", "placement": "bottom", "showLegend": true}},
          "targets": [
            {"datasource": {"type": "prometheus"}, "expr": "1 - node_filesystem_avail_bytes{mountpoint=\"/\",fstype!=\"tmpfs\"} / node_filesystem_size_bytes{mountpoint=\"/\",fstype!=\"tmpfs\"}", "legendFormat": "Disk Used %", "refId": "A"}
          ],
          "title": "Filesystem Usage",
          "type": "timeseries"
        },
        {
          "datasource": {"type": "prometheus"},
          "fieldConfig": {
            "defaults": {
              "color": {"mode": "thresholds"},
              "mappings": [],
              "max": 100, "min": 0,
              "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "yellow", "value": 70}, {"color": "red", "value": 90}]},
              "unit": "percent"
            }
          },
          "gridPos": {"h": 4, "w": 6, "x": 0, "y": 24},
          "id": 7,
          "options": {"orientation": "auto", "reduceOptions": {"calcs": ["lastNotNull"]}, "showThresholdLabels": false, "showThresholdMarkers": true},
          "targets": [
            {"datasource": {"type": "prometheus"}, "expr": "100 - (avg(irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)", "legendFormat": "CPU %", "refId": "A"}
          ],
          "title": "CPU %",
          "type": "gauge"
        },
        {
          "datasource": {"type": "prometheus"},
          "fieldConfig": {
            "defaults": {
              "color": {"mode": "thresholds"},
              "mappings": [],
              "max": 100, "min": 0,
              "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "yellow", "value": 70}, {"color": "red", "value": 90}]},
              "unit": "percent"
            }
          },
          "gridPos": {"h": 4, "w": 6, "x": 6, "y": 24},
          "id": 8,
          "options": {"orientation": "auto", "reduceOptions": {"calcs": ["lastNotNull"]}, "showThresholdLabels": false, "showThresholdMarkers": true},
          "targets": [
            {"datasource": {"type": "prometheus"}, "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100", "legendFormat": "Memory %", "refId": "A"}
          ],
          "title": "Memory %",
          "type": "gauge"
        },
        {
          "datasource": {"type": "prometheus"},
          "fieldConfig": {
            "defaults": {
              "color": {"mode": "thresholds"},
              "mappings": [],
              "max": 100, "min": 0,
              "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "yellow", "value": 70}, {"color": "red", "value": 90}]},
              "unit": "percent"
            }
          },
          "gridPos": {"h": 4, "w": 6, "x": 12, "y": 24},
          "id": 9,
          "options": {"orientation": "auto", "reduceOptions": {"calcs": ["lastNotNull"]}, "showThresholdLabels": false, "showThresholdMarkers": true},
          "targets": [
            {"datasource": {"type": "prometheus"}, "expr": "(1 - node_filesystem_avail_bytes{mountpoint=\"/\",fstype!=\"tmpfs\"} / node_filesystem_size_bytes{mountpoint=\"/\",fstype!=\"tmpfs\"}) * 100", "legendFormat": "Disk %", "refId": "A"}
          ],
          "title": "Disk %",
          "type": "gauge"
        },
        {
          "datasource": {"type": "prometheus"},
          "fieldConfig": {
            "defaults": {
              "color": {"fixedColor": "blue", "mode": "fixed"},
              "mappings": [],
              "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}]},
              "unit": "s"
            }
          },
          "gridPos": {"h": 4, "w": 6, "x": 18, "y": 24},
          "id": 10,
          "options": {"colorMode": "background", "graphMode": "none", "justifyMode": "center", "reduceOptions": {"calcs": ["lastNotNull"]}},
          "targets": [
            {"datasource": {"type": "prometheus"}, "expr": "node_time_seconds - node_boot_time_seconds", "legendFormat": "Uptime", "refId": "A"}
          ],
          "title": "Uptime",
          "type": "stat"
        }
      ],
      "refresh": "30s",
      "schemaVersion": 38,
      "tags": ["server", "monitoring"],
      "time": {"from": "now-3h", "to": "now"},
      "timepicker": {},
      "title": "Server Monitoring",
      "uid": "server-monitoring",
      "version": 1
    }
    DASHEOF

    chown -R grafana:grafana /var/lib/grafana/dashboards

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
