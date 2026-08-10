# Troubleshooting

Common issues encountered during the workshop and how to resolve them.

## PATH not refreshed after installation

### Symptoms

You have just installed a tool (for example `kubectl`, `helm`, or `cast-cli`) but when you run it in your shell you see an error similar to:

```text
kubectl: command not found
helm: command not found
cast-cli: command not found
```

The binary itself exists on disk (often under `/usr/local/bin` or `$HOME/.local/bin`), yet the shell cannot find it.

### Causes

There are two common causes:

1. **The install directory is not on your `PATH`.** Many CLI installers drop binaries into `/usr/local/bin` or `$HOME/.local/bin`. If neither of those directories appears in the output of `echo "$PATH"`, the shell will not resolve the new command.
2. **The current shell session was started before the install completed.** Shell sessions cache their environment when they start, so binaries added afterwards are invisible until the session is refreshed.

### Fixes

#### Quick fix for the current session

Append the install directories to `PATH` in the shell you are using right now:

```bash
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
```

You can verify the command is now reachable:

```bash
command -v kubectl
command -v helm
command -v cast-cli
```

#### Make the change permanent

Add the same `export` line to the profile file that your shell sources on startup:

- **bash**: `~/.bashrc` (or `~/.bash_profile` on macOS if that is what `bash` reads)
- **zsh**: `~/.zshrc`
- **sh / POSIX login shells**: `~/.profile`

Example for `~/.bashrc` or `~/.zshrc`:

```bash
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
```

Save the file, then either:

- Open a new terminal window, or
- Reload the profile in the current session:

  ```bash
  source ~/.bashrc   # for bash
  source ~/.zshrc    # for zsh
  ```

#### Reload an already-running session

If you do not want to open a new terminal, sourcing the profile file in the active shell is equivalent:

```bash
source ~/.bashrc
# or
source ~/.zshrc
```

### Workshop helper note

The `validate-setup.sh` script attempts to update `PATH` for the current shell session automatically so that the validation it runs right after installation can find the newly installed tools. However, this update only affects the session that ran the script. New terminal windows opened afterwards will not inherit that change unless the `export PATH=...` line has also been added to `~/.bashrc`, `~/.zshrc`, or `~/.profile`.

### Quick checklist

1. Confirm the binary is actually on disk: `ls -l /usr/local/bin/kubectl` or `ls -l $HOME/.local/bin/cast-cli`.
2. Confirm `PATH` includes its directory: `echo "$PATH"`.
3. Update `PATH` for the current session with the `export` command above.
4. Persist the change by editing `~/.bashrc`, `~/.zshrc`, or `~/.profile`.
5. Open a new terminal or `source` the profile, then re-run the command.

## Permission denied during CLI installation

### Symptoms

When installing a CLI manually, or while running `validate-setup.sh`, you see an error such as:

```text
install: cannot create regular file '/usr/local/bin/kubectl': Permission denied
mv: cannot move 'kubectl' to '/usr/local/bin/kubectl': Permission denied
cp: cannot create regular file '/usr/local/bin/helm': Permission denied
curl: (23) Failed writing body
touch: cannot touch '/usr/local/bin/cast-cli': Permission denied
```

The install step appears to start, the binary downloads successfully, and then fails when writing into `/usr/local/bin`.

### Causes

`/usr/local/bin` is a system-managed directory that is owned by `root` and not writable by regular user accounts:

```bash
ls -ld /usr/local/bin
# drwxr-xr-x  root  wheel  ...  /usr/local/bin
```

When the installer (or `validate-setup.sh`) tries to place the new binary into `/usr/local/bin` without elevated privileges, the kernel rejects the write with `EACCES` (surfaced by `install`, `mv`, `cp`, `touch`, etc. as `Permission denied`). The download itself succeeds because it writes to a location the current user does own — only the final move into `/usr/local/bin` is blocked.

### Fixes

#### Manual install — prepend `sudo`

For a manual install, prefix the final install/move command with `sudo`. For example, when installing `kubectl` from a downloaded binary:

```bash
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

The same pattern applies to `helm` and `cast-cli`:

```bash
sudo install -m 0755 helm /usr/local/bin/helm
sudo install -m 0755 cast-cli /usr/local/bin/cast-cli
```

You will be prompted for your password (unless `sudo` is configured to cache credentials for the current session).

#### `validate-setup.sh` — grant passwordless sudo or run as a privileged user

The `validate-setup.sh` helper script already detects this case and tries `sudo -n` (non-interactive) when `/usr/local/bin` is not writable by the current user. The `-n` flag tells `sudo` to fail fast instead of prompting for a password, so if elevated authentication cannot proceed unattended, the script reports a failure rather than blocking on a password prompt.

To make `validate-setup.sh` run end-to-end without interaction, pick one of the following:

- **Enable passwordless sudo for the install commands.** Add a narrowly scoped line to `/etc/sudoers.d/validate-setup` (use `visudo` to edit safely):

  ```text
  yourusername ALL=(root) NOPASSWD: /usr/bin/install, /bin/ln, /usr/bin/ln
  ```

  This lets the script call `sudo -n install ...` without a password prompt.

- **Run the script under a user that can write to `/usr/local/bin`.** For example, log in as `root` (or a user in a group that owns `/usr/local/bin`) and re-run `../../setup/validate-setup.sh`.

- **Pre-install the CLIs into `/usr/local/bin` as root** (using `sudo install ...` as shown above), then re-run `validate-setup.sh`. The script is idempotent: each `install_*` function detects the already-installed binary and skips it.

#### Alternative — install into `$HOME/.local/bin`

If you cannot or do not want to use `sudo`, install the CLIs into a user-writable directory that is already (or can be) on your `PATH`:

```bash
mkdir -p "$HOME/.local/bin"
install -m 0755 kubectl "$HOME/.local/bin/kubectl"
install -m 0755 helm    "$HOME/.local/bin/helm"
install -m 0755 cast-cli "$HOME/.local/bin/cast-cli"
```

Make sure `$HOME/.local/bin` is on your `PATH` (see the "PATH not refreshed after installation" section above), then re-run `validate-setup.sh`. The script will detect the existing binaries and skip re-installing them.

### Security note

`sudo` grants full administrative rights for the duration of the command, so only run scripts from trusted sources with elevated privileges. Before `sudo`-ing an installer:

- Confirm you are running the official command from the tool's documented installation page (for example, the Kubernetes, Helm, and Cast AI documentation sites).
- When the project publishes a checksum (SHA-256, SHA-512) or a GPG signature for the downloaded archive, verify it before running the installer as root:

  ```bash
  sha256sum -c kubectl.sha256
  gpg --verify kubectl.sha256.asc kubectl
  ```

- Prefer installing the CLIs without `sudo` (into `$HOME/.local/bin`) when your environment allows it, and reserve `sudo` for cases where the system path is required.

### Quick checklist

1. Check ownership of `/usr/local/bin`: `ls -ld /usr/local/bin`.
2. For a one-off install, prepend `sudo` to the install command (for example `sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl`).
3. For `validate-setup.sh`, configure passwordless `sudo` for the install commands, run the script as a privileged user, or pre-install the CLIs into `/usr/local/bin`.
4. If `sudo` is not available, install into `$HOME/.local/bin` and ensure it is on `PATH`.
5. Verify checksums (when provided) before running any installer with `sudo`.

## Architecture mismatch errors

### Symptoms

A CLI was installed successfully (no permission errors, no download failures), but invoking it fails with one of the following:

```text
bash: /usr/local/bin/kubectl: cannot execute binary file: Exec format error
bash: /usr/local/bin/helm: cannot execute binary file: Exec format error
zsh: command not found: /usr/local/bin/cast-cli   # with "Bad CPU type in executable" in the system log
zsh: killed        /usr/local/bin/kubectl
Killed
```

On macOS, the same situation is often surfaced as:

```text
[1]    killed    kubectl
```

or, when inspecting the binary directly:

```bash
file /usr/local/bin/kubectl
# /usr/local/bin/kubectl: ELF 64-bit LSB executable, x86-64 ...   (on an arm64 machine)
# /usr/local/bin/helm:   Mach-O 64-bit executable x86_64          (on an arm64 machine)
```

The binary is present and executable (`ls -l` shows `-rwxr-xr-x`), but the kernel refuses to load it because the instruction set does not match the host CPU.

### Causes

The binary that was downloaded and installed was built for a different CPU architecture than the machine you are running it on. This is the most common cause of `Exec format error` and `Bad CPU type in executable` and is the cause of the kernel's `Killed` response when the dynamic loader immediately faults.

Typical mismatches during the workshop:

- An `amd64` (also known as `x86_64`) binary installed on an `arm64` machine — for example, an Intel build of `kubectl`, `helm`, or `cast-cli` dropped onto an Apple Silicon (M1/M2/M3/M4) Mac or an AWS Graviton (`aarch64`) instance.
- An `arm64` binary installed on an `x86_64` machine — for example, copying a binary from an Apple Silicon Mac onto an Intel-based host without rebuilding.

The install step itself succeeds because the file is a valid executable *for some* CPU — it just is not the right CPU.

### How to check the current architecture

Use `uname -m` to print the machine hardware name of the host you are on:

```bash
uname -m
```

The output will be one of:

- `x86_64` (also written as `amd64`) — Intel/AMD 64-bit.
- `aarch64` (also written as `arm64`) — ARM 64-bit (Apple Silicon, AWS Graviton, Raspberry Pi 5 in 64-bit mode, etc.).
- Anything else — an architecture the workshop tools do not ship a build for.

You can confirm the architecture the binary on disk was built for with `file`:

```bash
file /usr/local/bin/kubectl
file /usr/local/bin/helm
file /usr/local/bin/cast-cli
```

If `file` says `x86_64` (or `amd64`) and `uname -m` says `arm64`, you have an architecture mismatch.

### Architecture mapping used by the validation script

`validate-setup.sh` picks the binary to download with the following mapping, derived directly from the output of `uname -m`:

| `uname -m` output | Downloaded binary suffix |
| ----------------- | ------------------------ |
| `x86_64` / `amd64` | `amd64`                 |
| `aarch64` / `arm64` | `arm64`                |
| anything else       | script exits with an error |

In other words: `x86_64` and `amd64` both resolve to an `amd64` download, and `aarch64` and `arm64` both resolve to an `arm64` download. If you downloaded a binary by hand and used the wrong suffix, the table above tells you which archive you actually need.

### Fixes

#### 1. Remove the wrong binary

Delete the mismatched binary so the next install step can replace it without conflict:

```bash
rm -f /usr/local/bin/kubectl
rm -f /usr/local/bin/helm
rm -f /usr/local/bin/cast-cli
```

If the binary lives in `$HOME/.local/bin` instead, remove it from there:

```bash
rm -f "$HOME/.local/bin/kubectl"
rm -f "$HOME/.local/bin/helm"
rm -f "$HOME/.local/bin/cast-cli"
```

`rm -f` does not error if the file is already gone, so it is safe to run unconditionally.

#### 2. Re-run `validate-setup.sh`

The simplest path back to a working install is to let the helper script pick the correct binary for your machine:

```bash
../../setup/validate-setup.sh
```

`validate-setup.sh` detects the host architecture with `uname -m`, applies the mapping in the table above (`x86_64`/`amd64` -> `amd64`, `aarch64`/`arm64` -> `arm64`), and downloads the matching archive. After it completes, verify that the tools run:

```bash
kubectl version --client
helm version
cast-cli --version
```

#### 3. Manual install of the correct archive

If you are installing the CLI by hand, download the archive that matches `uname -m`:

- For `x86_64` / `amd64` hosts, download the `...-amd64.tar.gz` (or `...-linux-amd64`, `...-darwin-amd64`, `...-windows-amd64.exe`) artifact.
- For `aarch64` / `arm64` hosts, download the `...-arm64.tar.gz` (or `...-linux-arm64`, `...-darwin-arm64`, `...-windows-arm64.exe`) artifact.

Example for `kubectl` on an `arm64` Linux host:

```bash
curl -fsSLO "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

Example for `helm` on a `darwin` (`macOS`) `amd64` host:

```bash
curl -fsSL -o helm.tgz "https://get.helm.sh/helm-$(curl -fsSL https://api.github.com/repos/helm/helm/releases/latest | grep tag_name | cut -d '"' -f 4)-darwin-amd64.tar.gz"
tar -xzf helm.tgz
sudo install -m 0755 darwin-amd64/helm /usr/local/bin/helm
```

After installing, sanity-check with `file` and `uname -m` to confirm the architectures match, then run a `version` command to confirm the binary actually executes.

### Quick checklist

1. Confirm the symptom with `file /usr/local/bin/<tool>` and look for `x86_64` on an `arm64` host (or vice versa).
2. Check the host architecture with `uname -m` (`x86_64`/`amd64` vs `aarch64`/`arm64`).
3. Remove the wrong binary: `rm -f /usr/local/bin/kubectl` (repeat for `helm` and `cast-cli`).
4. Re-run `validate-setup.sh` so it downloads the correct archive for your architecture.
5. For manual installs, download the archive whose suffix (`amd64` or `arm64`) matches the output of `uname -m`.

## cast-cli download or installation failure

### Symptoms

When installing `cast-cli` (either by running `validate-setup.sh` or by invoking the installer manually with `curl -fsSL https://get.cast.ai/linux | bash`), the install step aborts with one of the following:

```text
curl: (6) Could not resolve host: get.cast.ai
curl: (35) SSL connect error
curl: (60) SSL certificate problem: unable to get local issuer certificate
failed to install cast-cli via get.cast.ai/linux
# bash: line 1: cast-cli: command not found   (after a non-zero exit)
```

Or, after the installer appears to finish successfully, `cast-cli` is still missing:

```text
$ cast-cli --version
zsh: command not found: cast-cli
bash: cast-cli: command not found
```

In this second case `command -v cast-cli` returns nothing, even though the installer reported success.

### Causes

There are four common causes for a `cast-cli` install that either fails outright or leaves the binary unreachable on `PATH`:

1. **Network or DNS problems.** The host cannot reach the internet at all, or DNS cannot resolve `get.cast.ai` (or the underlying artifact bucket the installer fetches from). `curl` reports this as `(6) Could not resolve host`.
2. **TLS interception.** A corporate proxy, Zscaler / Netskope / Cloudflare WARP agent, or antivirus product is terminating TLS and re-signing the connection with its own CA. `curl` cannot validate the chain against the system trust store and reports `(35) SSL connect error` or `(60) SSL certificate problem`.
3. **Temporary outage of `get.cast.ai` or the artifact bucket.** The installer URL or the storage backend it downloads from is briefly unreachable. Retrying after a few minutes usually resolves this.
4. **The installer drops the binary as `castctl` instead of `cast-cli`.** Recent versions of the Cast AI installer (and some archived artifacts) place the binary on disk with the name `castctl`. The install step therefore exits 0, but `cast-cli` is never created and the shell cannot find it. This is the most common cause of the "installer succeeded but `cast-cli: command not found`" pattern.

### Fixes

Work through the steps below in order. Each step assumes you have already read the previous one.

#### 1. Check network connectivity to the installer endpoint

Confirm that your host can reach `get.cast.ai` at all:

```bash
curl -I https://get.cast.ai/linux
```

A healthy response starts with `HTTP/2 200` (or `HTTP/1.1 200 OK`). If the request hangs, returns `(6) Could not resolve host`, or times out, you have a DNS or routing problem that needs to be fixed before the installer can succeed — for example, by joining a VPN, switching networks, or pointing your resolver at a working nameserver.

#### 2. Retry the installer

If connectivity is fine, retry the installer with the same command the script uses. The `get.cast.ai/linux` payload is idempotent and safe to re-run:

```bash
curl -fsSL https://get.cast.ai/linux | bash
```

The `-f` flag makes `curl` fail fast on HTTP errors so the `bash` half does not run on a broken payload, and `-sSL` follows redirects while staying silent unless something goes wrong. If the retry succeeds, jump to step 3 to verify `cast-cli` is actually on `PATH`.

#### 3. If the installer succeeded but `cast-cli` is not found, symlink `castctl`

Some releases of the installer drop the binary as `castctl` rather than `cast-cli`. First confirm it is there under the alternate name:

```bash
command -v castctl
ls -l "$(command -v castctl 2>/dev/null)" 2>/dev/null
```

If `castctl` resolves to a real file, create a `cast-cli` symlink in the same directory:

```bash
ln -s "$(command -v castctl)" "$(dirname "$(command -v castctl)")/cast-cli"
```

Verify that `cast-cli` is now reachable:

```bash
command -v cast-cli
cast-cli --version
```

If `command -v castctl` returns nothing, the installer did not actually place a binary anywhere on disk — re-run it (step 2) and watch its output for errors before proceeding.

#### 4. Fallback — install into `$HOME/.local/bin`

If `/usr/local/bin` is unwritable and the installer refuses to proceed, or if you simply want a user-local install, drop the binary into `$HOME/.local/bin` (which should already be on `PATH` per the "PATH not refreshed after installation" section above):

```bash
mkdir -p "$HOME/.local/bin"
# When the installer exits non-zero, download the archive directly and unpack it manually:
curl -fsSL -o /tmp/cast-cli.tar.gz https://get.cast.ai/linux
tar -xzf /tmp/cast-cli.tar.gz -C /tmp
install -m 0755 /tmp/cast-cli "$HOME/.local/bin/cast-cli"
```

Then verify:

```bash
command -v cast-cli
cast-cli --version
```

If `command -v cast-cli` still returns nothing, add `$HOME/.local/bin` to `PATH` (see the "PATH not refreshed after installation" section) and reopen your shell.

#### 5. Behind a corporate proxy — configure `HTTPS_PROXY` and retry

If you are behind an outbound HTTPS proxy, export the proxy URL before re-running the installer so `curl` (and the installer it shells out to) can route through it:

```bash
export HTTPS_PROXY="http://proxy.example.com:3128"
# Optional, only if your proxy also intercepts plain HTTP:
export HTTP_PROXY="http://proxy.example.com:3128"
# If the proxy uses a private CA, point curl at the CA bundle:
export CURL_CA_BUNDLE="/etc/ssl/certs/corporate-ca.pem"
curl -fsSL https://get.cast.ai/linux | bash
```

If your environment uses a PAC file or a WARP / Zscaler / Netskope agent, make sure the agent is connected and trusted by your shell session before retrying — `curl` will otherwise see the agent's MITM certificate and fail with `(60)`.

### Workshop helper note

The `validate-setup.sh` script used during the workshop already knows about the `castctl` -> `cast-cli` rename: if it finds `castctl` on `PATH` but no `cast-cli`, it automatically creates the symlink described in step 3 before it gives up. So running `../../setup/validate-setup.sh` after a successful installer run is usually enough to repair this case without manual intervention.

### Quick checklist

1. Verify reachability with `curl -I https://get.cast.ai/linux`.
2. Retry the installer: `curl -fsSL https://get.cast.ai/linux | bash`.
3. If `cast-cli` is still missing, check `command -v castctl` and create a symlink: `ln -s "$(command -v castctl)" "$(dirname "$(command -v castctl)")/cast-cli"`.
4. As a fallback, drop the binary into `$HOME/.local/bin` and ensure that directory is on `PATH`.
5. Behind a proxy, export `HTTPS_PROXY` (and `CURL_CA_BUNDLE` if needed) before retrying.
6. Re-run `validate-setup.sh` so its built-in `castctl` -> `cast-cli` symlink logic runs.

## Alias `k` not available in new terminals

### Symptoms

You ran `validate-setup.sh` and the script reported that the `k` shorthand alias for `kubectl` was added to your shell profile. However, when you open a new terminal window or tab and try to use the alias, you see:

```text
$ k get nodes
k: command not found
```

The alias is missing even though the setup script claimed success, and the same command works fine in the terminal window where you originally ran `validate-setup.sh`.

### Causes

There are three common causes for this situation:

1. **The alias was added to a different shell profile than the one you are currently running.** `validate-setup.sh` detects the login shell from the `$SHELL` environment variable (for example, `/bin/zsh` or `/bin/bash`) and appends the `alias k=kubectl` line to that shell's startup file (`~/.zshrc`, `~/.bashrc`, `~/.config/fish/config.fish`, and so on). If you later open a terminal that runs a *different* shell, the alias is invisible because that other shell sources a different profile.
2. **The new shell session was started before the alias was appended.** Shell sessions read their profile files once, at startup. If `validate-setup.sh` wrote the alias to `~/.bashrc` *after* your current shell session was already running, that session never picked up the change. Closing the window and reopening it is what reloads the profile.
3. **Non-interactive shells do not source the profile.** Commands run from scripts, editors, IDEs, CI runners, or `ssh host command` invocations typically start a non-interactive shell that skips `~/.bashrc` / `~/.zshrc`. In those contexts `k` is undefined even after a fresh login, because `alias` is a shell built-in that lives only in interactive shells.

### Fixes

#### 1. Reload the detected profile in the current terminal

The fastest fix for an already-open terminal is to source the profile file that contains the new alias:

```bash
source ~/.bashrc        # bash
source ~/.zshrc         # zsh
source ~/.config/fish/config.fish   # fish (uses `abbr`, not `alias`)
```

After running `source`, retry `k get nodes`. If the alias was appended correctly, the command resolves.

#### 2. Open a new terminal window or tab

Profiles are read once when a shell starts, so the cleanest way to pick up a newly added alias is to open a fresh terminal window or tab:

- On macOS, press `Cmd + T` to open a new tab in Terminal.app, or use your terminal emulator's "New Window" / "New Tab" action.
- On Linux, open a new terminal window from your desktop environment.

The new session sources the updated profile on startup and `k` is available immediately.

#### 3. If you are using a different shell than the one detected

Confirm which shell is currently running:

```bash
echo "$SHELL"          # login shell recorded in /etc/passwd
echo "$0"              # actual shell process for this session
ps -p "$$" -o comm=    # current shell executable
```

If the login shell (from `$SHELL`) does not match the shell you are actually using, add the alias manually to the profile of the shell you are running. For example, if `$SHELL` says `/bin/bash` but you are running `zsh` interactively, append the alias to `~/.zshrc`:

```bash
echo "alias k=kubectl" >> ~/.zshrc
```

For **fish**, the equivalent of an alias is an abbreviation, added with `abbr` rather than `alias`:

```fish
abbr -a k kubectl
abbr --save k kubectl   # persist across sessions
```

#### 4. Bash on macOS: also update `~/.bash_profile`

On macOS, when `bash` is invoked as a *login shell* it reads `~/.bash_profile` (or `~/.profile`), not `~/.bashrc`. If `~/.bash_profile` exists and does not source `~/.bashrc`, the alias appended to `~/.bashrc` will never run in a fresh login terminal. Two common remedies:

- **Source `~/.bashrc` from `~/.bash_profile`** so both interactive and login shells pick up the alias:

  ```bash
  # add this to ~/.bash_profile if it is not already there
  [[ -r ~/.bashrc ]] && source ~/.bashrc
  ```

- **Append the alias directly to `~/.bash_profile`** instead of `~/.bashrc`:

  ```bash
  echo "alias k=kubectl" >> ~/.bash_profile
  ```

After either change, open a new terminal window or run `source ~/.bash_profile` in the current session.

### Workshop helper note

`validate-setup.sh` attempts to `source` the updated profile automatically so that the validation step it runs right after appending the alias can resolve `k` immediately. That `source` only affects the session that executed the script — it does not propagate to other already-open terminal windows, nor does it survive once that session ends. New terminals inherit the alias only because it was written to a profile file on disk; they will not see it until they read that file themselves.

### Quick checklist

1. Confirm the alias is actually on disk: `grep -n "alias k=" ~/.bashrc ~/.zshrc ~/.bash_profile 2>/dev/null`.
2. Reload the profile in the current session: `source ~/.bashrc`, `source ~/.zshrc`, or `source ~/.config/fish/config.fish`.
3. Open a new terminal window or tab so the profile is read at startup.
4. If `bash` on macOS is your login shell, ensure `~/.bash_profile` sources `~/.bashrc` or holds the alias directly.
5. If you are using a shell different from the one in `$SHELL`, append the alias to that shell's profile (use `abbr` for fish).
6. Re-run `validate-setup.sh` if the alias is missing from disk entirely.
