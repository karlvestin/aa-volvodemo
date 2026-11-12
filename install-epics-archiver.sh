#!/usr/bin/env bash
# Install EPICS Archiver Appliance quickstart in an existing Ubuntu VM.
# Does not start the archiver or configure a system service.
set -Eeuo pipefail

ARCHIVER_VERSION="${ARCHIVER_VERSION:-2.5.0}"
TOMCAT_VERSION="${TOMCAT_VERSION:-11.0.26}"
ENV_NAME="${ENV_NAME:-epics-archiver}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/epics-archiver}"
ARCHIVER_FILE="archappl_v${ARCHIVER_VERSION}.tar.gz"
TOMCAT_FILE="apache-tomcat-${TOMCAT_VERSION}.tar.gz"
ARCHIVER_URL="https://github.com/archiver-appliance/epicsarchiverap/releases/download/${ARCHIVER_VERSION}/${ARCHIVER_FILE}"
TOMCAT_URL="https://dlcdn.apache.org/tomcat/tomcat-11/v${TOMCAT_VERSION}/bin/${TOMCAT_FILE}"

log() { printf '\n==> %s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
trap 'printf "ERROR: install failed at line %s (exit code %s)\n" "$LINENO" "$?" >&2' ERR

for tool in conda curl tar sha512sum; do
    command -v "$tool" >/dev/null 2>&1 || fail "Missing $tool (install Miniforge/Conda first)."
done

log "Conda environment: ${ENV_NAME}"
if ! conda env list --json | python3 -c '
import json, os, sys
name = sys.argv[1]
data = json.load(sys.stdin)
sys.exit(0 if any(os.path.basename(p) == name for p in data["envs"]) else 1)
' "$ENV_NAME"; then
    conda create -y -n "$ENV_NAME" --override-channels -c conda-forge 'openjdk=25'
else
    log "Environment exists; checking Java version"
fi

conda run -n "$ENV_NAME" java -version

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

download() {
    local url="$1" dest="$2"
    if [[ -s "$dest" ]]; then
        log "Using existing ${dest}"
    else
        log "Downloading ${dest}"
        curl -fL --retry 3 --connect-timeout 20 -o "${dest}.part" "$url"
        mv "${dest}.part" "$dest"
    fi
}

download "$ARCHIVER_URL" "$ARCHIVER_FILE"
download "$TOMCAT_URL" "$TOMCAT_FILE"

log "Verifying Tomcat SHA-512"
curl -fLsS --retry 3 "${TOMCAT_URL}.sha512" -o "${TOMCAT_FILE}.sha512"
# Apache checksum format begins with the 128-digit digest; extract it regardless of whitespace/filename format.
expected=$(grep -Eo '[[:xdigit:]]{128}' "${TOMCAT_FILE}.sha512" | head -n 1)
[[ -n "$expected" ]] || fail "Could not read Apache SHA-512 checksum"
printf '%s  %s\n' "$expected" "$TOMCAT_FILE" | sha512sum --check --status || fail "Tomcat checksum mismatch"

log "Extracting Archiver Appliance"
# Verify the archive before extracting. Do not pipe tar into grep -q under
# pipefail: grep may exit early and cause tar to fail with SIGPIPE.
tar -tzf "$ARCHIVER_FILE" >/dev/null || fail "Invalid Archiver Appliance archive: $ARCHIVER_FILE"

tar -xzf "$ARCHIVER_FILE"

# Official release packages normally put the WAR files and quickstart.sh
# directly at archive root. Accommodate a single enclosing directory too.
for artifact in quickstart.sh mgmt.war engine.war etl.war retrieval.war; do
    if [[ ! -f "$artifact" ]]; then
        found=$(find . -mindepth 2 -maxdepth 4 -type f -name "$artifact" -print -quit)
        if [[ -n "$found" ]]; then
            cp "$found" "./$artifact"
        else
            fail "Missing $artifact after extraction of $ARCHIVER_FILE. Check archive with: tar -tzf $ARCHIVER_FILE | grep -E '(war|quickstart)'"
        fi
    fi
done
chmod +x quickstart.sh

log "Generating start script"
cat > start-archiver.sh <<START
#!/usr/bin/env bash
set -Eeuo pipefail
cd "\$(dirname "\$(readlink -f "\$0")")"
# Restrict CA discovery to localhost inside the VM. Network isolation must
# still be enforced by the VM network, not by these variables alone.
export EPICS_CA_AUTO_ADDR_LIST=NO
export EPICS_CA_ADDR_LIST=127.0.0.1
# Avoid inheriting a host/ESS PVA discovery configuration.
export EPICS_PVA_AUTO_ADDR_LIST=NO
export EPICS_PVA_ADDR_LIST=127.0.0.1
exec conda run --no-capture-output -n "${ENV_NAME}" bash -c '
    export JAVA_HOME="\$CONDA_PREFIX"
    exec bash ./quickstart.sh "${TOMCAT_FILE}"
'
START
chmod +x start-archiver.sh

cat <<DONE

Installation complete: ${INSTALL_DIR}

To start the archiver:
    cd "${INSTALL_DIR}"
    ./start-archiver.sh

Once ready, open:
    http://<VM-IP>:17665/mgmt/ui/index.html

Note: The quickstart does not persist its PV configuration across restarts.
This installer does not start the server, so you can isolate the VM first.
DONE
