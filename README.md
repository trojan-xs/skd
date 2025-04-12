# skd - SSH Key Deployment Tool

**skd** is a lightweight bash script for automating SSH key generation and deployment across multiple remote hosts. It supports both interactive and YAML-configured batch modes, with optional debug logging and a clear summary of deployment results.

---

## Features

- Interactive mode or batch mode via YAML file
- Generates new SSH key pairs (per-host)
- Updates `~/.ssh/config` with alias support
- Deploys public keys over SSH or SSH+password (with `sshpass`)
- Passwords never printed unless `--debug` is enabled
- Color-coded summaries and messages
- Flags for help, syntax preview, and debug output

---

## Usage

```bash
./skd [file.yaml] [options]



Examples

# Interactive mode
./skd

# Batch mode with YAML input
./skd hosts.yaml

# Batch mode with debug output
./skd hosts.yaml -d

# Show YAML syntax example
./skd -s

# Show help
./skd -h

YAML Format

- name: ingress
  user: deploy
  host: 192.168.1.10
  port: 22
  key_type: ed25519
  aliases: [web, proxy, ingress]
  password: yourpassword




Notes

    port, key_type, aliases, and password are optional

    password is used with sshpass for first-time deployment

    If deployment succeeds, password will be overwritten in YAML as [SUCCESS] or [FAILURE]
