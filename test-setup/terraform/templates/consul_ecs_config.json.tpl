{
  "bootstrapDir": "/consul",
  "consulServers": {
    "hosts": "${consul_private_ip}",
    "http":  { "port": 8500 },
    "grpc":  { "port": 8502 },
    "skipServerWatch": true,
    "defaults": { "tls": false }
  },
  "service": {
    "name": "test-service",
    "port": 8080
  },
  "proxy": {
    "publicListenerPort": 20000,
    "healthCheckPort":    22000
  },
  "healthSyncContainers": ["app"],
  "transparentProxy": { "enabled": false }
}
