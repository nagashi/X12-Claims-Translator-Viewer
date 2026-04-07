# X12 Claims Translator Viewer — Start Server Script Notes

## Overview

The original `start_server.sh` script was written on a Linux machine. When run on macOS, it failed
because it used Linux-specific commands to retrieve OS information and network details. This document
explains what was changed, why, and how the updated script handles multiple operating systems.

---

## Problem with the Original Script

The original script contained two Linux-specific commands that do not work on macOS:

1. **OS information:**
   ```bash
   cat /proc/version
   ```
   The `/proc` virtual filesystem does not exist on macOS. Running this command on macOS produces
   a "No such file or directory" error, which can cause the script to abort depending on shell settings.

2. **IP address retrieval:**
   ```bash
   /sbin/ifconfig | grep "net addr" | head -1 | sed 's/Bcast//' | awk -F\: '{print $2;}'
   ```
   On macOS, `ifconfig` output uses `inet` instead of `inet addr`, so the grep pattern produces no
   results. Additionally, modern Linux distributions have also moved away from this older `ifconfig`
   format in favor of the `ip` command.

---

## What Was Changed

### 1. Operating System Detection

The updated script uses `uname -s` to detect the OS before running any OS-specific commands:

```bash
OS=$(uname -s 2>/dev/null || echo "Unknown")
```

`uname -s` returns:

| OS                        | Value returned    |
|---------------------------|-------------------|
| macOS                     | `Darwin`          |
| Linux                     | `Linux`           |
| Windows (Git Bash)        | `MINGW64_NT-...`  |
| Windows (Cygwin)          | `CYGWIN_NT-...`   |
| Windows (MSYS2)           | `MSYS_NT-...`     |
| Other Unix (BSD, Solaris) | varies            |

A `case` block then branches on this value to run the correct commands for each platform.

---

### 2. macOS (Darwin) Branch

```bash
Darwin)
    echo "Server OS info is: $(sw_vers | tr '\n' '  ')"
    IP=$(ipconfig getifaddr en0 2>/dev/null)
    [ -z "$IP" ] && IP=$(ipconfig getifaddr en1 2>/dev/null)
    [ -z "$IP" ] && IP="Unknown"
    echo "IP Address: $IP"
    ;;
```

- **`sw_vers`** is the macOS-native command for OS version info (returns ProductName,
  ProductVersion, and BuildVersion).
- **`ipconfig getifaddr en0`** retrieves the IPv4 address for the primary network interface.
  The script falls back to `en1` (common for Wi-Fi) if `en0` yields nothing.

---

### 3. Linux Branch

```bash
Linux)
    echo "Server OS info is: $(cat /proc/version)"
    IP=$(ifconfig 2>/dev/null | grep "inet addr" | head -1 | sed 's/Bcast//' | awk -F\: '{print $2;}' | awk '{print $1}')
    [ -z "$IP" ] && IP=$(ip addr show 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | head -1 | awk '{print $2}' | cut -d/ -f1)
    [ -z "$IP" ] && IP="Unknown"
    echo "IP Address: $IP"
    ;;
```

- The original `cat /proc/version` and `ifconfig` commands are preserved for Linux since they are
  valid there.
- A fallback using the modern **`ip addr show`** command is added, because many current Linux
  distributions no longer include `ifconfig` by default (it is part of the `net-tools` package,
  which is not installed on minimal or modern distros).

---

### 4. Windows Branch (Git Bash / Cygwin / MSYS2)

```bash
MINGW*|CYGWIN*|MSYS*)
    echo "Server OS info is: Windows (Running via $(uname -s))"
    echo "NOTE: Ensure Elixir and PostgreSQL are installed and accessible in this environment."
    IP=$(ipconfig 2>/dev/null | grep "IPv4" | head -1 | awk -F: '{print $2}' | tr -d ' \r')
    [ -z "$IP" ] && IP="Unknown"
    echo "IP Address: $IP"
    ;;
```

- Windows does not natively execute bash scripts. The script must be run under **Git Bash**,
  **Cygwin**, **MSYS2**, or **WSL (Windows Subsystem for Linux)**.
- Under WSL, `uname -s` returns `Linux`, so the Linux branch handles that case automatically.
- Under Git Bash, Cygwin, or MSYS2, `uname -s` returns a value matching `MINGW*`, `CYGWIN*`,
  or `MSYS*` respectively.
- **`ipconfig`** is the Windows command for network info and is accessible from these environments.
  The IPv4 address is parsed from its output.
- Elixir on Windows must be installed separately and `mix` must be in the system `PATH`.

---

### 5. Other / Unknown OS Branch

```bash
*)
    echo "Server OS info is: $OS $(uname -r 2>/dev/null)"
    IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$IP" ] && IP="Unknown"
    echo "IP Address: $IP"
    ;;
```

- For any unrecognized OS (e.g., FreeBSD, OpenBSD, Solaris), `uname -r` provides the kernel
  release version as supplemental info.
- **`hostname -I`** is used as a broadly compatible IP lookup; it is not available on all Unix
  variants but serves as a reasonable default.

---

### 6. Error Handling Improvements

The original script used `|| { echo "..."; exit 2; }` inline. The updated script uses the
pre-defined `die()` function consistently throughout for cleaner, uniform error reporting:

```bash
cd "$HOME" || die "Error----> Cannot change to home directory."
git clone ... || die "Error----> Git clone failed."
mix deps.get || die "Error----> mix deps.get failed."
mix setup    || die "Error----> mix setup failed."
```

---

### 7. Test Output — Explicit Pass/Fail Summary

**Original behavior:** The original script ran `mix test` and relied entirely on ExUnit's default
output. While ExUnit does print a summary line (e.g., `127 tests, 0 failures`), it is buried within
verbose test output and can be easy to miss — especially when all tests pass and there is no
prominent failure block.

**Updated behavior:** The script now captures the full test output, displays it as before, then
parses the ExUnit summary line and prints an explicit, always-visible summary:

```
===============================
Test Results Summary:
  Tests Passed : 127
  Tests Failed : 0
===============================
```

This ensures that both the passed count and the failed count are always displayed, regardless of
whether any tests failed. The counts are extracted by parsing the ExUnit summary line format:

```
N tests, N failures
```

The passed count is calculated as `TOTAL - FAILURES`, so it is always accurate and always shown.

---

## Files Produced

| File                  | Description                                      |
|-----------------------|--------------------------------------------------|
| `start_server.sh`     | Updated OS-aware startup script                  |
| `start_server_notes.pdf` | This document (PDF version)                   |

---

## Usage

Make the script executable and run it:

```bash
chmod +x start_server.sh
./start_server.sh
```

For help:

```bash
./start_server.sh -h
```
