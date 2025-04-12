# skd - SSH Key Deployment Tool

**skd** is a lightweight Bash script for automating SSH key generation and deployment across multiple remote hosts. It supports both interactive and YAML-configured batch modes, with optional debug logging and a clear summary of deployment results.

---

## Features

- Interactive or batch mode (via YAML file)
- Per-host SSH key generation
- Appends new entries to `~/.ssh/config` with optional aliases
- Key deployment via direct SSH or password-based `sshpass`
- Passwords are never printed unless `--debug` is enabled
- Color-coded output for steps, success, and failure
- Built-in help and YAML syntax output

---

## Usage

```bash
./skd [file.yaml] [options]
```

### Examples

```bash
# Interactive mode
./skd

# Batch mode with YAML input
./skd hosts.yaml

# Batch mode with debug logging
./skd hosts.yaml -d

# Show expected YAML format
./skd -s

# Show help
./skd -h
```

---

## YAML Format

```yaml
- name: ingress
  user: deploy
  host: 192.168.1.10
  port: 22
  key_type: ed25519
  aliases: [web, proxy, ingress]
  password: yourpassword
```

### Notes

- `port`, `key_type`, `aliases`, and `password` are optional
- `password` is used with `sshpass` for first-time key deployment
- After deployment, `password` will be replaced with `[SUCCESS]` or `[FAILURE]` in the YAML file

---

## Flags

| Flag             | Description                          |
|------------------|--------------------------------------|
| `-d`, `--debug`  | Enable debug output with timestamps  |
| `-s`, `--syntax` | Show expected YAML format            |
| `-h`, `--help`   | Show usage help                      |

---

## Requirements

- `bash`
- `ssh`, `ssh-keygen`, `scp`
- `sshpass` (optional, only needed for password-based deployment)
- `yq` (auto-downloaded temporarily if missing)

---

## License

MIT

---

## Author

Maintained by [YourNameHere]. Contributions welcome.
