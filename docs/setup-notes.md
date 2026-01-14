# Notes on setting up a new machine

## Table of Contents

- [Notes on setting up a new machine](#notes-on-setting-up-a-new-machine)
  - [Table of Contents](#table-of-contents)
  - [Homebrew](#homebrew)
    - [Homebrew "brew" package manager (old ruby script still works)](#homebrew-brew-package-manager-old-ruby-script-still-works)
    - [Update .zshrc for brew](#update-zshrc-for-brew)
    - [Add Homebrew to path (brew)](#add-homebrew-to-path-brew)
    - [Add Node Version Manager (nvm)](#add-node-version-manager-nvm)
    - [Save and load .zshrc](#save-and-load-zshrc)
  - [Install NVM (Node Version Manager)](#install-nvm-node-version-manager)
    - [Install Node](#install-node)
  - [MKCERT (SSL for Localhost)](#mkcert-ssl-for-localhost)
    - [Install mkcert](#install-mkcert)
    - [Use mkcert](#use-mkcert)
    - [Config dev domain](#config-dev-domain)
    - [Docker \& Docker Compose](#docker--docker-compose)
    - [Angular UIs (Nginx) with trusted HTTPS](#angular-uis-nginx-with-trusted-https)
  - [Git Hooks](#git-hooks)
    - [MicroK8s](#microk8s)
  - [Kubernetes Setup](#kubernetes-setup)
  - [Enable Kubernetes (Visual Guide)](#enable-kubernetes-visual-guide)
  - [Keycloak Get started](#keycloak-get-started)
  - [Keycloak Local SSL](#keycloak-local-ssl)
    - [(OLD) Make a dev key pair](#old-make-a-dev-key-pair)
    - [(BETTER) Make a dev key pair using mkcert (see the Angular project)](#better-make-a-dev-key-pair-using-mkcert-see-the-angular-project)
    - [copy the files to a folder then chmod the key](#copy-the-files-to-a-folder-then-chmod-the-key)
    - [Run Keycloack using ssl keys](#run-keycloack-using-ssl-keys)
    - [Navigate to Keycloak](#navigate-to-keycloak)
  - [Keycloak Realms and Themes](#keycloak-realms-and-themes)
    - [Test Theme Selection (Login Pages)](#test-theme-selection-login-pages)
    - [PKCE Testing Helper](#pkce-testing-helper)
  - [Pyenv (manage multiple versions of Python)](#pyenv-manage-multiple-versions-of-python)
  - [Python Version Setup](#python-version-setup)
    - [2. Create Virtual Environment](#2-create-virtual-environment)
  - [VS Code Extensions](#vs-code-extensions)
  - [VS Code Debugging](#vs-code-debugging)
    - [Python API](#python-api)
    - [Node API](#node-api)
    - [Angular UIs](#angular-uis)
    - [Troubleshooting](#troubleshooting)
  

## Homebrew

### Homebrew "brew" package manager (old ruby script still works)
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

/opt/homebrew/bin/brew

### Update .zshrc for brew
cd ~
nano .zshrc

### Add Homebrew to path (brew)

eval "$(/opt/homebrew/bin/brew shellenv)"

### Add Node Version Manager (nvm)

export NVM_DIR="$HOME/.nvm"
  [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
  [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"

### Save and load .zshrc 
control+x
source .zshrc

## Install NVM (Node Version Manager)

brew update
brew install wget
brew install tree
brew install nvm

### Install Node

nvm i [version]


## MKCERT (SSL for Localhost)

### Install mkcert

brew install mkcert
brew install nss
mkcert -install

### Use mkcert

mkcert localhost
mkcert dev.local

### Config dev domain 

sudo nano /etc/hosts

  127.0.0.1       dev.local

sudo killall -HUP mDNSResponder


### Docker & Docker Compose
Install Docker and Docker Compose using Homebrew:

```sh
brew install docker
brew install docker-compose
```

And Download Docker Desktop from [docker.com](https://www.docker.com/products/docker-desktop/).

### Angular UIs (Nginx) with trusted HTTPS

Two UIs are available: `ui-news` and `ui-portal`. Each serves over HTTPS with mkcert dev certs.

To serve either UI over HTTPS locally without browser warnings, generate and mount mkcert certificates into each UI container.

- Create certs in the repo so Docker can mount them:

```sh
# From repo root
cd services/ui-news
brew install mkcert nss   # if not already installed
mkcert -install
mkcert localhost          # creates cert key pair in current folder

# Move into dedicated certs folder used by compose
mkdir -p certs
mv localhost.pem certs/
mv localhost-key.pem certs/

# Repeat for portal UI
cd ../../services/ui-portal
mkcert localhost
mkdir -p certs
mv localhost.pem certs/
mv localhost-key.pem certs/
```

- Compose mounts these into Nginx at `/etc/nginx/certs` and the nginx config uses them for TLS. If the mount is missing, the Docker image will fall back to generating a self-signed cert inside the container (you will see a browser warning).

- Bring up the UIs and backends:

```sh
# From repo root
docker compose -f infra/docker-compose.yml up --build -d ui-news ui-portal
```

- Access News UI at `https://localhost` and Portal UI at `https://localhost:4443`. HTTP routes are redirected to HTTPS.

- API proxying: Nginx forwards `/api` to the game service and `/ai` to the AI service over HTTPS. Ensure those services are up (compose `depends_on` handles startup order).

Troubleshooting tips:
- If you see the default "Welcome to nginx!" page, ensure compose mounted the certs and the image was rebuilt; the UI should be served from `dist/ui/browser`.
- If the browser shows a certificate warning, verify the `certs` folder exists at `services/ui-news/certs` and `services/ui-portal/certs` and contains `localhost.pem` and `localhost-key.pem`, and re-run `mkcert -install` if needed.

### Rebuild / Apply Changes

When you change the API or UIs, rebuild only what’s needed and restart:

```bash
# From repo root
docker compose -f infra/docker-compose.yml build news-api ui-news ui-portal
docker compose -f infra/docker-compose.yml up -d news-api rss-mcp ui-news ui-portal

# Or run full bootstrap (includes realm config + health checks)
zsh tools/bootstrap.sh

# Manual endpoint verification (optional)
bash tools/check-health.sh
```

Quick test from the News UI:
- Visit https://localhost and click Login.
- After login, use "Validate Token" to call `/api/token/validate` and "Fetch RSS" to call `/api/rss`.
- Both are proxied through Nginx and require a valid bearer token.
## Git Hooks

Enable repository git hooks so the pre-commit hook enforces protobuf generation stays clean when `proto/**` changes.

```sh
# From repo root
zsh tools/enable-githooks.sh

# Or manually:
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit
```

Test the hook:

```sh
echo "// touch" >> proto/pontoon.proto
git add proto/pontoon.proto
git commit -m "test: proto hook"
```

The hook runs `make check-proto` and blocks the commit if generation leaves the repo dirty.

### MicroK8s
Install MicroK8s using Homebrew:

```sh
brew install ubuntu/microk8s/microk8s
```

Initialize MicroK8s with custom resources:

```sh
microk8s install --cpu 4 --mem 16 --disk 50
```

## Kubernetes Setup

Check your kubectl client version:

```sh
kubectl version --client
```

Start Docker, enable Kubernetes in Docker Desktop preferences, and restart Docker.

After Kubernetes is enabled, check cluster info:

```sh
kubectl cluster-info
```

## Enable Kubernetes (Visual Guide)

[![Enable Kubernetes](img/enable-kubernetes.png)](img/enable-kubernetes.png)



## Keycloak Get started

https://www.keycloak.org/getting-started/getting-started-docker

docker run -p 127.0.0.1:8080:8080 -e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD=admin quay.io/keycloak/keycloak:26.3.3 start-dev

https://localhost:8443/admin

## Keycloak Local SSL

Docker for Mac volume mounts behave differently than the base Docker system. This is mostly because Docker tries to comply with Apple's filesystem sandbox guidelines.

As shown in Docker's preferences, only certain paths are exported by macOS.

/Users
/Volumes
/tmp
/private

### (OLD) Make a dev key pair

openssl req -newkey rsa:2048 -nodes \
  -keyout localhost-key.pem -x509 -days 3650 -out localhost.pem

### (BETTER) Make a dev key pair using mkcert (see the Angular project)

brew install mkcert
mkcert -install
mkcert localhost

### copy the files to a folder then chmod the key

chmod 755 localhost-key.pem

### Run Keycloack using ssl keys

docker run \
  --name keycloak \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD=password \
  -e KC_HTTPS_CERTIFICATE_FILE=/Users/DBenoy/certs/keycloak/localhost.pem \
  -e KC_HTTPS_CERTIFICATE_KEY_FILE=/Users/DBenoy/certs/keycloak/localhost-key.pem \
  -v $PWD/localhost.pem:/Users/DBenoy/certs/keycloak/localhost.pem \
  -v $PWD/localhost-key.pem:/Users/DBenoy/certs/keycloak/localhost-key.pem \
  -p 8443:8443 \
  quay.io/keycloak/keycloak \
  start-dev

### Navigate to Keycloak

  https://localhost:8443/admin

## Keycloak Realms and Themes

Two realms are preconfigured and auto-imported when the stack starts:

- **news**: uses the `news` theme. Config in [infra/keycloak/realm-news.json](infra/keycloak/realm-news.json) and theme at [infra/keycloak/themes/news](infra/keycloak/themes/news).
- **portal**: uses the `portal` theme. Config in [infra/keycloak/realm-portal.json](infra/keycloak/realm-portal.json) and theme at [infra/keycloak/themes/portal](infra/keycloak/themes/portal).

Admin console:
- Sign in at https://localhost:8443/admin with `admin/admin`.
- Use the realm selector (top-left) to switch between `news` and `portal`.

Seeded users:
- `news` realm: username `test`, password `test`.
- `portal` realm: username `portal-user`, password `portal`.

### Test Theme Selection (Login Pages)

Trigger an OIDC login to see each realm's themed login page:

```bash
# News realm: initiate login for news-web client
open 'https://localhost:8443/realms/news/protocol/openid-connect/auth?client_id=news-web&redirect_uri=https%3A%2F%2Flocalhost%2F&response_type=code&scope=openid'

# Portal realm: initiate login for portal-web client
open 'https://localhost:8443/realms/portal/protocol/openid-connect/auth?client_id=portal-web&redirect_uri=https%3A%2F%2Flocalhost%2F&response_type=code&scope=openid'
```

### PKCE Testing Helper

Use the local helper to generate a `code_verifier` and S256 `code_challenge` for testing/debugging login flows:

```bash
python3 tools/pkce.py --json
# Example usage in a login URL (replace the values):
open "https://localhost:8443/realms/news/protocol/openid-connect/auth?client_id=news-web&redirect_uri=https%3A%2F%2Flocalhost%2F&response_type=code&scope=openid&code_challenge_method=S256&code_challenge=REPLACE_ME"
```

If you change theme assets, rebuild Keycloak to pick up changes:

```bash
# From repo root
docker compose -f infra/docker-compose.yml build keycloak
docker compose -f infra/docker-compose.yml up -d keycloak
```

Implementation notes:
- Theme resources must be under `resources/` within each theme folder (e.g., CSS at [infra/keycloak/themes/news/resources/css/news.css](infra/keycloak/themes/news/resources/css/news.css)).
- Realms are auto-imported from [infra/keycloak/Dockerfile](infra/keycloak/Dockerfile) via `start-dev --import-realm` in compose.

### Keycloak CLI Tips (jq + docker exec)

When scripting Keycloak admin with `kcadm.sh`, prefer running `jq` on the host and piping JSON out of the container. The Keycloak container image does not include `jq` by default.

- Symptom: `jq: command not found` (inside the container)
- Cause: the container lacks `jq`
- Fix: run `jq` on the host; only run `kcadm.sh` in the container

Good pattern (host jq):

```bash
# Get client id of news-web
docker exec infra-keycloak-dev /opt/keycloak/bin/kcadm.sh get clients -r news -q clientId=news-web \
  | jq -r '.[0].id'

# List OIDC protocol mappers (selected fields)
CID=$(docker exec infra-keycloak-dev /opt/keycloak/bin/kcadm.sh get clients -r news -q clientId=news-web | jq -r '.[0].id')
docker exec infra-keycloak-dev /opt/keycloak/bin/kcadm.sh get clients/$CID/protocol-mappers/models -r news \
  | jq -r '.[] | select(.protocol=="openid-connect") | [.name, .protocolMapper] | @tsv'
```

Avoid (container jq):

```bash
# Avoid relying on jq inside the container
docker exec infra-keycloak-dev bash -lc '/opt/keycloak/bin/kcadm.sh get clients -r news | jq -r ...'  # <- will fail
```

Also, when calling Keycloak admin/token endpoints from scripts, prefer HTTPS with dev certs and follow redirects, then hand off to `jq`:

```bash
ACCESS_TOKEN=$(curl -sS -k -L https://localhost:8443/realms/master/protocol/openid-connect/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'grant_type=password&client_id=admin-cli&username=admin&password=admin' \
  | jq -r '.access_token')
echo "token length: ${#ACCESS_TOKEN}"
```

Validate responses before piping to `jq` to catch non-JSON (e.g., HTML redirects):

```bash
RESP=$(curl -sS -k -L https://localhost:8443/realms/master/protocol/openid-connect/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'grant_type=password&client_id=admin-cli&username=admin&password=admin')
printf '%s\n' "$RESP" | jq -e . >/dev/null || { echo "Not JSON:"; printf '%s\n' "$RESP" | head -n 5; }
```


## Pyenv (manage multiple versions of Python)

```bash
# Install dependencies
brew install openssl readline sqlite3 xz zlib tcl-tk
brew install pyenv

# Check your shell
echo $SHELL

# Edit shell configuration (add pyenv to PATH)
sudo nano ~/.zshrc
```

Add to `~/.zshrc`:
```bash
# Add pyenv
export PATH="$(pyenv root)/shims:$PATH"
```

```bash
# Reload shell configuration
source ~/.zshrc 

# Install Python and check versions
pyenv install 3.9.19
pyenv versions

# Install virtualenv
brew install virtualenv

# Edit AWS config (when ready)
sudo nano ~/.aws/config
```

## Python Version Setup

```bash
# Set Python 3.9.19 for the project (not global)
cd services/ai
pyenv local 3.9.19
python --version  # Should show Python 3.9.19
```

### 2. Create Virtual Environment
```bash
# Remove any existing venv
rm -rf venv

# Create new venv with Python 3.9.19
python -m venv venv
source venv/bin/activate
python --version  # Verify it shows 3.9.19
```

 

 

## VS Code Extensions

Recommended extensions for the News stack (Python + Node API + Angular UI) and container workflows.

```bash
# Core language/tools
code --install-extension ms-python.python
code --install-extension Angular.ng-template
code --install-extension dbaeumer.vscode-eslint
code --install-extension esbenp.prettier-vscode

# Containers & YAML
code --install-extension ms-azuretools.vscode-docker
code --install-extension redhat.vscode-yaml

# Productivity
code --install-extension eamodio.gitlens
code --install-extension yzhang.markdown-all-in-one
code --install-extension humao.rest-client
code --install-extension github.copilot
code --install-extension github.copilot-chat
```

Notes:
- Ensure the Python interpreter (venv) is selected per workspace folder.
- Use ESLint + Prettier for Node/Angular formatting and linting consistency.

## VS Code Debugging

### Python API
- Interpreter: Select the `services/ai/venv` interpreter via the Command Palette (`Python: Select Interpreter`).
- Launch: Add a simple `launch.json` to run your app (adjust `program` to your entry point):

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug Python API",
      "type": "python",
      "request": "launch",
      "program": "${workspaceFolder}/services/ai/app.py",
      "cwd": "${workspaceFolder}/services/ai",
      "env": {
        "PYTHONUNBUFFERED": "1"
      }
    }
  ]
}
```

If using FastAPI with Uvicorn, swap to:
```json
{
  "name": "Debug FastAPI (Uvicorn)",
  "type": "python",
  "request": "launch",
  "module": "uvicorn",
  "args": ["app:app", "--host", "0.0.0.0", "--port", "8000"],
  "cwd": "${workspaceFolder}/services/ai"
}
```

### Node API
- Scripts: Use `npm run dev` (with `ts-node`/`nodemon` if TypeScript).
- Launch: Example Node attach/run config (adjust `cwd` and script):

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Node API: npm run dev",
      "type": "pwa-node",
      "request": "launch",
      "runtimeExecutable": "npm",
      "runtimeArgs": ["run", "dev"],
      "cwd": "${workspaceFolder}/services/api-node",
      "console": "integratedTerminal"
    }
  ]
}
```

### Angular UIs
- Serve: Run `ng serve` in `services/ui-news` or `services/ui-portal`.
- Debug: Chrome attach config with proper `webRoot` for source maps:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug Angular UI (Chrome)",
      "type": "pwa-chrome",
      "request": "launch",
      "url": "https://localhost",
      "webRoot": "${workspaceFolder}/services/ui-news"
    }
  ]
}
```

### Troubleshooting
- Python venv: If the debugger uses the wrong Python, re-select the interpreter and reopen the folder.
- Node inspector: If breakpoints don’t bind, ensure `pwa-node` is used and the dev script starts with `--inspect` (many tools do automatically).
- Angular source maps: Confirm `webRoot` points at the Angular project root and `ng serve` runs with default source maps.


 





