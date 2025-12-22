# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: BUSL-1.1

ui = true
disable_mlock = false

storage "file" {
  path = "/vault/data"
}

# HTTPS listener
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable = 1

  telemetry {
    unauthenticated_metrics_access = true
  }
}

api_addr = "https://vault.rajivwallace.com"

telemetry {
  prometheus_retention_time = "24h"
  disable_hostname = true
}
