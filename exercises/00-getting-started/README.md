# Step 0: Getting Started

Welcome to the workshop. This lesson prepares your Linux environment so you can
follow along with every exercise that follows. It is intentionally short: by the
end of it you should have a known-good toolchain and a repeatable way to verify
it.

## What this lesson does

This lesson validates your Linux setup and installs any CLIs that are missing
from your machine. Concretely, it ensures that the following tools are available
on your `PATH` and working:

- `kubectl` — the Kubernetes command-line client
- `helm` — the Kubernetes package manager
- `cast-cli` — the MSP workshop CLI used to interact with the lab environment

Rather than asking you to run each install by hand, the lesson ships an
idempotent helper script, `validate-setup.sh`, located in this directory. The
script:

1. Probes your environment for the tools above.
2. Installs any tool that is missing or that does not satisfy the required
   minimum version.
3. Reports a clear pass/fail summary so you know exactly where you stand before
   you move on.

Because the script is idempotent, you can re-run it as often as you like —
during the lesson to recover from a mistake, at the start of a later lesson to
double-check your environment, or after a Strigo workspace refresh.

> Tip: If anything in the script fails, fix the underlying issue and rerun it
> before continuing to the next lesson. The remaining exercises assume that
> `kubectl`, `helm`, and `cast-cli` are installed and on your `PATH`.

## Prerequisites

Before you run `validate-setup.sh`, make sure you have the following:

- **A Linux environment.** A recent Ubuntu, Debian, Fedora, RHEL, or
  distribution derived from one of those. You should be running a `bash` shell
  (the default on most Linux installations).
- **`curl`.** Used by the install script to download release artifacts from
  GitHub and the Kubernetes project. Most Linux distributions ship `curl` by
  default; if it is missing, install it with your package manager
  (for example `apt-get install curl` or `dnf install curl`).
- **Internet access.** The script needs to reach GitHub releases and, for
  `helm`, get.helm.sh. If you are behind a corporate proxy, make sure your
  shell's `HTTP_PROXY` / `HTTPS_PROXY` environment variables are configured
  before you start.
- **`sudo` (optional).** The script installs the CLIs into `/usr/local/bin` by
  default. If your user can write to `/usr/local/bin` without elevation you do
  not need `sudo`. If you cannot, either pre-authenticate once with `sudo`
  before running the script, or have it ready to enter your password when
  prompted.

## 1. Installing and verifying `kubectl`

`kubectl` is the official Kubernetes command-line client. Every later exercise
in this workshop assumes it is on your `PATH`. The instructions below are
**idempotent**: only run the install step if the check step shows that
`kubectl` is missing.

### 1.1 Check whether `kubectl` is already installed

Run this command first. It prints the client version (and warns if `kubectl`
is not on `PATH`):

```bash
kubectl version --client
```

If you see output that includes a `Client Version:` line, `kubectl` is already
installed and you can skip ahead to [section 2](#2-installing-and-verifying-helm).
If your shell reports `command not found` (or similar), continue with the
install steps below.

> Note: `kubectl version --client` is purely a local check — it does not talk
> to any cluster and works even before you have ever authenticated to one.

### 1.2 Install `kubectl` from the official Linux static binary (only if missing)

The Kubernetes project publishes a signed static binary on `dl.k8s.io`. The
commands below download the **latest stable release** for your CPU
architecture (`amd64` or `arm64`) and install it into `/usr/local/bin`, which
is on `PATH` for a standard Linux install. Run them only if the check above
showed that `kubectl` is missing.

```bash
# 1. Pick the latest stable version (e.g. "v1.31.0") into a shell variable.
KUBECTL_VERSION="$(curl -L -s https://dl.k8s.io/release/stable.txt)"

# 2. Detect your CPU architecture. Defaults to amd64 if uname is unavailable.
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64)  ARCH='amd64' ;;
  aarch64) ARCH='arm64' ;;
  arm64)   ARCH='arm64' ;;
  *)       ARCH='amd64' ;;
esac

# 3. Download the matching static binary to a temporary file.
curl -fLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"

# 4. Install it into /usr/local/bin. Use sudo only if your user cannot write
#    there directly. When you are not using sudo, omit the root ownership
#    flags so `install` preserves your user as the owner.
if [ -w /usr/local/bin ]; then
  install -m 0755 kubectl /usr/local/bin/kubectl
else
  sudo install -m 0755 kubectl /usr/local/bin/kubectl
fi

# 5. Clean up the downloaded archive.
rm -f kubectl
```

A few things worth knowing about this sequence:

- The download URL resolves to whatever `stable.txt` currently points at, so
  re-running it later will pull the newest release rather than pinning you to
  an old one.
- `install -m 0755` sets sane read/execute permissions for everyone. When
  you run it without `sudo`, the binary is owned by your current user; when
  you run it with `sudo`, it is owned by `root`.
- If you are on a locked-down workstation that does not allow writes to
  `/usr/local/bin`, install into `~/.local/bin` instead and add that directory
  to your `PATH` for future shells.

### 1.3 Verify the installation

After the install completes, run the same check from
[section 1.1](#11-check-whether-kubectl-is-already-installed) again to confirm
that the new binary is on `PATH` and reports a version:

```bash
kubectl version --client
```

You should now see a `Client Version:` line. If `kubectl version --client`
still reports `command not found`, open a new shell so it picks up the updated
`PATH`, or `hash -r` / `rehash` in the current one, and try once more.

> Reminder: the check command and the verification command are intentionally
> the same. Run it before installing to decide whether to install, and run it
> again after installing to confirm success.

## 2. Installing and verifying `helm`

`helm` is the de facto Kubernetes package manager. A handful of later
exercises in this workshop deploy bundled manifests as Helm charts, so you
need it on your `PATH` alongside `kubectl`. As with `kubectl`, the steps
below are **idempotent**: only run the install block if the check shows that
`helm` is not already present.

### 2.1 Check whether `helm` is already installed

Run this first. It prints the version of the `helm` binary on your `PATH`
(or warns that it is missing):

```bash
helm version
```

If you see output that starts with `version.BuildInfo{Version:"vX.Y.Z", ...}`
(or the short form `vX.Y.Z`), `helm` is already installed and you can skip
ahead to [section 3](#3-installing-and-verifying-cast-cli). If your shell
reports `command not found` (or similar), continue with the install steps
below.

> Note: `helm version` is a purely local check. It does not require a running
> Kubernetes cluster or any pre-existing configuration on your machine.

### 2.2 Install `helm` from `get.helm.sh` (only if missing)

The Helm project publishes an official install script on `get.helm.sh` /
GitHub. The script detects your OS and CPU architecture (`amd64`, `arm64`,
`arm`, `armv6`, `armv7`, `ppc64le`, `s390x`, and so on), downloads the
matching release tarball, and installs the binary to `/usr/local/bin/helm`.
Run the commands below **only if** the check in
[section 2.1](#21-check-whether-helm-is-already-installed) showed that
`helm` is missing.

```bash
# 1. Download the official Helm install script. -f makes curl fail on HTTP
#    errors so a broken download never silently corrupts the next step.
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3

# 2. Inspect what you just downloaded. You should see a bash script that
#    references get.helm.sh and detects your architecture.
less get_helm.sh

# 3. Mark the script executable and run it. It will detect your OS and CPU
#    architecture automatically and install the latest stable Helm release
#    to /usr/local/bin/helm. Use sudo only if your user cannot write there.
if [ -w /usr/local/bin ]; then
  bash get_helm.sh
else
  sudo bash get_helm.sh
fi

# 4. Clean up the downloaded installer.
rm -f get_helm.sh
```

A few things worth knowing about this sequence:

- The script is fetched from `get.helm.sh`'s canonical mirror on GitHub
  (`helm/helm`'s `main` branch, `scripts/get-helm-3`). Re-running it later
  will pull the newest Helm release rather than pinning you to an old one.
- Architecture detection is handled inside the script — it inspects
  `uname -m` and maps it to the correct asset name, so the same commands
  work on `amd64` (x86_64) and `arm64` (aarch64) Linux hosts.
- The default install location is `/usr/local/bin/helm`. If you are on a
  locked-down workstation that does not allow writes to `/usr/local/bin`,
  set the `HELM_INSTALL_DIR` environment variable before running the
  script (for example `HELM_INSTALL_DIR=$HOME/.local/bin bash get_helm.sh`)
  and add that directory to your `PATH` for future shells.
- The same idempotency rule applies at the script level: `get_helm.sh`
  refuses to overwrite an existing `helm` installation without an explicit
  flag, so it is safe to re-run.

### 2.3 Verify the installation

After the install completes, run the same check from
[section 2.1](#21-check-whether-helm-is-already-installed) again to confirm
that the new binary is on `PATH` and reports a version:

```bash
helm version
```

You should now see a `version.BuildInfo{Version:"vX.Y.Z", ...}` line (or
the short form `vX.Y.Z`). If `helm version` still reports `command not
found`, open a new shell so it picks up the updated `PATH`, or run
`hash -r` / `rehash` in the current one, and try once more.

> Reminder: the check command and the verification command are intentionally
> the same. Run it before installing to decide whether to install, and run it
> again after installing to confirm success.

## 3. Installing and verifying `cast-cli`

`cast-cli` is the MSP workshop CLI used to interact with the lab
environment. A handful of later exercises in this workshop call it to
provision clusters, register API keys, and drive the guided lab workflow,
so you need it on your `PATH` alongside `kubectl` and `helm`. As with the
previous tools, the steps below are **idempotent**: only run the install
block if the check shows that `cast-cli` is not already present.

### 3.1 Check whether `cast-cli` is already installed

Run this first. It prints the version of the `cast-cli` binary on your
`PATH` (or warns that it is missing):

```bash
cast-cli --version
```

If you see a version string (for example `cast-cli version vX.Y.Z`),
`cast-cli` is already installed and you can skip ahead to
[section 4](#4-setting-up-convenient-shell-aliases). If your shell reports
`command not found` (or similar), continue with the install steps below.

> Note: Some older releases of `cast-cli` may not implement the `--version`
> flag. If `cast-cli --version` is rejected, fall back to `cast-cli version`,
> or run `cast-cli --help` to confirm that the binary is on your `PATH` and
> to see the exact command surface it accepts. Any of these forms is
> sufficient to detect whether the tool is installed.

### 3.2 Install `cast-cli` from `get.cast.ai` (only if missing)

CAST AI publishes an official install script at `get.cast.ai/linux`. The
script detects your OS and CPU architecture, downloads the matching
release binary, and installs it to `/usr/local/bin/cast-cli`. Run the
command below **only if** the check in
[section 3.1](#31-check-whether-cast-cli-is-already-installed) showed that
`cast-cli` is missing.

```bash
curl https://get.cast.ai/linux | bash
```

If the installer cannot write the binary into `/usr/local/bin` (for
example because your user does not have write permission there), re-run
the install with elevation so the script can drop the binary in place:

```bash
curl https://get.cast.ai/linux | sudo bash
```

A few things worth knowing about this sequence:

- The script is fetched over HTTPS from `get.cast.ai`. Re-running it later
  will pull the newest `cast-cli` release rather than pinning you to an
  old one.
- Architecture detection is handled inside the script — it inspects
  `uname` and selects the correct asset, so the same command works on
  `amd64` (x86_64) and `arm64` (aarch64) Linux hosts.
- The default install location is `/usr/local/bin/cast-cli`. If you are on
  a locked-down workstation that does not allow writes to `/usr/local/bin`,
  install into `~/.local/bin` instead (for example by setting
  `INSTALL_DIR=$HOME/.local/bin` before running the script) and add that
  directory to your `PATH` for future shells.

### 3.3 Verify the installation

After the install completes, run the same check from
[section 3.1](#31-check-whether-cast-cli-is-already-installed) again to
confirm that the new binary is on `PATH` and reports a version:

```bash
cast-cli --version
```

You should now see a `cast-cli version vX.Y.Z` line. If
`cast-cli --version` still reports `command not found`, open a new shell
so it picks up the updated `PATH`, or run `hash -r` / `rehash` in the
current one, and try once more. As noted above, you can also fall back
to `cast-cli version` or `cast-cli --help` to confirm that the binary is
on your `PATH`.

> Reminder: the check command and the verification command are intentionally
> the same. Run it before installing to decide whether to install, and run it
> again after installing to confirm success.

## 4. Setting up convenient shell aliases

Typing `kubectl` over and over gets tedious. The standard short alias for
the workshop is `k`, and `validate-setup.sh` creates it for you
automatically as part of the run that installs the CLIs. You do not need to
do anything by hand on a default Linux install — just re-open your shell
after the script finishes and `k` will be available.

### 4.1 What the script does for you

When `validate-setup.sh` runs, in addition to installing `kubectl`,
`helm`, and `cast-cli`, it does the following in the background:

1. Detects your shell by inspecting `$SHELL`. It picks `~/.bashrc` for
   `bash`, `~/.zshrc` for `zsh`, `~/.config/fish/config.fish` for `fish`,
   and `~/.profile` for any other shell. If `$SHELL` is unset or unknown,
   it falls back to the first existing file out of `~/.bashrc`,
   `~/.zshrc`, or `~/.profile` (defaulting to `~/.profile` if none exist).
2. Appends a single `alias k=kubectl` line (or `abbr k kubectl` for fish)
   to the chosen profile file so the alias is loaded by every new
   interactive shell.
3. If the script can identify the same profile in the current shell, it
   also `source`s it so the alias becomes available immediately — no need
   to open a new terminal.

Because this happens silently and is idempotent, re-running the script on
a machine where `k` is already defined is a no-op: it will not append a
duplicate line on top of an existing alias, and it will not clobber a
custom definition.

### 4.2 Manual fallback

If the script cannot detect your shell profile — for example because you
launched it from a non-interactive shell that does not export `$SHELL`,
because you use a non-standard profile location, or because your profile
file is read-only — you can add the alias yourself with a single line.
The command below appends it to `~/.bashrc` and re-sources it in the
current shell so the alias is available immediately:

```bash
echo "alias k=kubectl" >> ~/.bashrc && source ~/.bashrc
```

Substitute your own profile file if you do not use bash — for example
`~/.zshrc` for zsh or `~/.profile` for a POSIX-only login shell:

```bash
echo "alias k=kubectl" >> ~/.zshrc && source ~/.zshrc
```

If you keep your aliases in a file other than the ones above (for example
`~/.aliases` or `~/.config/shell/aliases.sh`), drop the line there instead
and source that file in the current shell.

### 4.3 Verify the alias works

Once the alias is in place, confirm that it resolves to `kubectl` by
running the same version check you used in section 1. The two commands
below should produce identical output:

```bash
kubectl version --client
k version --client
```

If `k version --client` reports `command not found`, the alias is not
loaded in your current shell. Either open a new terminal so your profile
is read on startup, or re-run the `source ~/.bashrc` step from
[section 4.2](#42-manual-fallback) using whichever profile file holds the
alias. You can also run `alias k` to check whether the alias is currently
defined and inspect the profile file directly if it is not.

## 5. Using the `validate-setup.sh` script

The lesson ships an idempotent helper script, `validate-setup.sh`, located
in this directory (`exercises/00-getting-started/`). Instead of running the
install blocks in sections 1, 2, 3, and 4 by hand, you can run the script
once and let it do all of that work for you. The script:

1. Checks whether `kubectl`, `helm`, and `cast-cli` are installed and on
   your `PATH`.
2. Installs any tool that is missing (without overwriting a working
   installation of the same tool).
3. Creates the `k=kubectl` shell alias automatically by appending
   `alias k=kubectl` to the first matching shell profile it finds
   (`~/.bashrc`, `~/.zshrc`, `~/.profile`, `~/.bash_profile`,
   `~/.zprofile`, ...).
4. Prints a clear pass/fail summary at the end so you know exactly where
   you stand before you move on to the next lesson.

### 5.1 Run the script from the lesson directory

The script lives in the lesson directory itself, so the simplest way to
run it is to `cd` into the directory, mark it executable, and execute it:

```bash
cd exercises/00-getting-started
chmod +x validate-setup.sh
./validate-setup.sh
```

If you do not already have the script on disk (for example because you
are following the lesson from a fresh clone that has not been updated
yet, or because you want to pin a known-good copy), download it with
`curl` first and then run the same two commands:

```bash
curl -fsSL -o validate-setup.sh <URL>
chmod +x validate-setup.sh
./validate-setup.sh
```

Replace `<URL>` with the location your instructor provides. The `-f` flag
makes `curl` fail on HTTP errors so a broken download never silently
corrupts the next step.

When the script installs a binary into `/usr/local/bin`, it uses `sudo`
only if your user cannot write there directly. Have your password ready
if you are prompted.

### 5.2 Safe to re-run

Because the script probes each tool before installing it, you can run
`./validate-setup.sh` as many times as you like without side effects:

- **Already-installed tools are left alone.** If `kubectl`, `helm`, or
  `cast-cli` is already on your `PATH` and reports a version, the script
  prints the detected version and a `skipping` message instead of
  reinstalling it.
- **The `k=kubectl` alias is added only once.** The script checks your
  profile for an existing `alias k=kubectl` line before appending, so
  re-running it will not create duplicate alias entries and will not
  clobber a custom definition.
- **It is safe to run after a Strigo workspace refresh**, at the start
  of a later lesson to double-check your environment, or after restoring
  a backup. Each invocation is independent and idempotent.

### 5.3 Example expected output

A successful first run prints something close to the following. Exact
versions and wording will vary as new releases ship, but the structure
should match:

```text
[validate-setup] Checking required CLIs...
[validate-setup] kubectl: not found, installing latest stable...
[validate-setup] kubectl installed: Client Version: v1.31.0
[validate-setup] helm: found, skipping (v3.16.3+g...)
[validate-setup] cast-cli: not found, installing latest...
[validate-setup] cast-cli installed: castctl 0.18.2
[validate-setup] alias k=kubectl added to /home/you/.bashrc
[validate-setup] sourced /home/you/.bashrc in current shell
[validate-setup] All checks passed. You are ready for the next lesson.
```

What to look for in the output:

- An `installed:` line for every tool that the script had to fetch, with
  the version it ended up installing.
- A `found, skipping` line for every tool that was already present.
- An `Alias created` (first run) or `already present` (subsequent runs)
  line confirming that the `k` alias is wired up.
- A final `All checks passed.` line. If you see that, the lesson is
  done and you can move on. If you see anything else as the last line,
  read it carefully — it is the failure the script wants you to fix
  before continuing.

### 5.4 If something goes wrong

If the script reports a failure — a download error, a permission error,
a missing dependency, a non-zero exit code, or a final line other than
`All checks passed.` — open the
[Troubleshooting Guide](../common/troubleshooting.md) that ships with
the lesson for step-by-step recovery instructions.

The guide covers the most common failure modes (no internet access,
corporate proxies, locked-down `/usr/local/bin`, missing `sudo`,
read-only profile files, and so on) and explains how to recover from
each one.

After fixing the underlying issue, re-run the same two commands from
[section 5.1](#51-run-the-script-from-the-lesson-directory):

```bash
cd exercises/00-getting-started
./validate-setup.sh
```

When the script finishes with `All checks passed.`, you are ready to
move on to the next lesson.
