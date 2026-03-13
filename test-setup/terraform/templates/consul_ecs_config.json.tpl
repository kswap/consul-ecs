{
  "bootstrapDir": "/consul",
  "consulServers": {
    "hosts": "${consul_private_ip}",
    "http":  { "port": 8500, "https": false },
    "grpc":  { "port": 8502 },
    "skipServerWatch": true,
    "defaults": { "tls": false }
  },
  "service": {
    "name": "test-service",
    "port": 80
  },
  "proxy": {
    "publicListenerPort": 20000,
    "healthCheckPort":    22000
  },
  "healthSyncContainers": ["app"],
  "transparentProxy": { "enabled": false }
}
