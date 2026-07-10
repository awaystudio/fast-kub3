#!/usr/bin/env bats
#
# fast-kub3 — test suite (bats)
#
# Strategia di test:
#   1. Tutti i comandi esterni (curl, wget, apt, kubectl, envsubst, sudo, …)
#      sono sostituiti da stub nella dir $BATS_TEST_TMPDIR/bin (aggiunta in $PATH
#      prima del PATH di sistema). Ogni stub registra la propria chiamata.
#   2. I test non toccano il sistema reale: nessun download, nessun K3s.
#   3. Il menu è testato iniettando l'input via echo | bash, verificando
#      quale funzione viene chiamata e quale codice di uscita è restituito.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# ---------------------------------------------------------------------------
# Helper: crea la dir degli stub per questo test e la prepende al PATH
# ---------------------------------------------------------------------------
setup() {
    STUB_DIR="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUB_DIR"
    export PATH="$STUB_DIR:$PATH"
    export CALL_LOG="$BATS_TEST_TMPDIR/calls.log"
    : > "$CALL_LOG"

    # Stub generico: registra "STUB_NAME arg1 arg2 ..." nel log, poi esce 0
    _make_stub() {
        local name="$1"; shift
        # Se ci sono opzioni extra (es exit code) gestiscile qui
        local exit_code="${1:-0}"
        cat > "$STUB_DIR/$name" <<STUB
#!/usr/bin/env bash
echo "$name \$*" >> "$CALL_LOG"
exit $exit_code
STUB
        chmod +x "$STUB_DIR/$name"
    }

    _make_stub curl
    _make_stub wget
    _make_stub apt
    _make_stub kubectl
    _make_stub envsubst
    _make_stub sudo
    _make_stub sh        # curl ... | sh  →  solo sh è coinvolto nella pipe

    # hostname stub: ritorna un IP ben noto
    cat > "$STUB_DIR/hostname" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *-I* ]]; then echo "192.0.2.1 "; else hostname; fi
STUB
    chmod +x "$STUB_DIR/hostname"

    # k3s-uninstall.sh stub
    mkdir -p "$BATS_TEST_TMPDIR/usr/local/bin"
    cat > "$BATS_TEST_TMPDIR/usr/local/bin/k3s-uninstall.sh" <<'STUB'
#!/usr/bin/env bash
echo "k3s-uninstall.sh $*" >> "$CALL_LOG"
STUB
    chmod +x "$BATS_TEST_TMPDIR/usr/local/bin/k3s-uninstall.sh"
    export PATH="$BATS_TEST_TMPDIR/usr/local/bin:$PATH"

    # File di deployment finto
    export JELLYFIN_DEPLOYMENT="$BATS_TEST_TMPDIR/jellyfin-deployment.yaml"
    echo "# fake yaml" > "$JELLYFIN_DEPLOYMENT"

    # HOME finta (evita scrivere su ~/.bashrc reale)
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"

    # Sovrascriviamo SCRIPT_DIR con il repo reale (le funzioni lo usano)
    export SCRIPT_DIR="$REPO_ROOT"
}

teardown() {
    # Nessuna pulizia manuale necessaria: bats elimina BATS_TEST_TMPDIR
    :
}

# ---------------------------------------------------------------------------
# Carica functions.sh in una sub-shell (evita pollution tra test)
# ---------------------------------------------------------------------------
_run_func() {
    local func="$1"; shift
    bash -c "
        export PATH='$PATH'
        export CALL_LOG='$CALL_LOG'
        export HOME='$HOME'
        export JELLYFIN_DEPLOYMENT='$JELLYFIN_DEPLOYMENT'
        export SCRIPT_DIR='$REPO_ROOT'
        export IP='192.0.2.1'
        source '$REPO_ROOT/functions.sh'
        $func \"\$@\"
    " -- "$@"
}

# ---------------------------------------------------------------------------
# ── functions.sh ────────────────────────────────────────────────────────────
# ---------------------------------------------------------------------------

@test "install_k3s: chiama curl passando l'URL di get.k3s.io" {
    run _run_func install_k3s
    [ "$status" -eq 0 ]
    grep -q "curl" "$CALL_LOG"
    # verifica che l'URL di k3s sia tra gli argomenti
    grep "curl" "$CALL_LOG" | grep -q "k3s.io"
}

@test "install_k3s: stampa messaggio 'Installing K3s...'" {
    run _run_func install_k3s
    [[ "$output" == *"Installing K3s"* ]]
}

@test "install_k9s: chiama wget con URL per il .deb dell'arch corrente" {
    run _run_func install_k9s
    grep -q "wget" "$CALL_LOG"
    # L'URL deve contenere il pacchetto k9s per l'architettura rilevata
    # (amd64 su runner x86, arm64/arm su Raspberry Pi). Deriviamo l'atteso
    # dalla stessa mappatura di detect_k9s_arch.
    case "$(uname -m)" in
        x86_64|amd64)        expected="amd64" ;;
        aarch64|arm64)       expected="arm64" ;;
        armv7l|armv6l|arm)   expected="arm" ;;
        *)                   expected="amd64" ;;
    esac
    grep "wget" "$CALL_LOG" | grep -q "k9s_linux_${expected}.deb"
}

@test "install_k9s: stampa l'architettura rilevata" {
    run _run_func install_k9s
    [[ "$output" == *"Detected host architecture"* ]]
}

# ── detect_k9s_arch: mappatura uname -m -> suffisso pacchetto k9s ────────────
# Ogni test inietta uno stub di `uname` che finge una specifica architettura.

_run_func_with_uname() {
    local fake_machine="$1"; shift
    local func="$1"; shift
    cat > "$STUB_DIR/uname" <<STUB
#!/usr/bin/env bash
if [[ "\$*" == *-m* ]]; then echo "$fake_machine"; else /usr/bin/uname "\$@"; fi
STUB
    chmod +x "$STUB_DIR/uname"
    _run_func "$func" "$@"
}

@test "detect_k9s_arch: x86_64 -> amd64" {
    run _run_func_with_uname "x86_64" detect_k9s_arch
    [ "$status" -eq 0 ]
    [ "$output" = "amd64" ]
}

@test "detect_k9s_arch: aarch64 -> arm64" {
    run _run_func_with_uname "aarch64" detect_k9s_arch
    [ "$status" -eq 0 ]
    [ "$output" = "arm64" ]
}

@test "detect_k9s_arch: armv7l -> arm" {
    run _run_func_with_uname "armv7l" detect_k9s_arch
    [ "$status" -eq 0 ]
    [ "$output" = "arm" ]
}

@test "detect_k9s_arch: architettura non supportata -> errore (exit 1)" {
    run _run_func_with_uname "riscv64" detect_k9s_arch
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unsupported architecture"* ]]
}

@test "install_k9s: stampa messaggio 'Installing K9s...'" {
    run _run_func install_k9s
    [[ "$output" == *"Installing K9s"* ]]
}

@test "config_k9s: aggiunge KUBECONFIG a ~/.bashrc" {
    run _run_func config_k9s
    [ "$status" -eq 0 ]
    grep -q "KUBECONFIG" "$HOME/.bashrc"
}

@test "config_k9s: chiama sudo per il chown di k3s.yaml" {
    run _run_func config_k9s
    grep -q "sudo" "$CALL_LOG"
}

@test "install: esegue install_k3s, install_k9s e config_k9s in sequenza" {
    run _run_func install
    [ "$status" -eq 0 ]
    grep -q "curl" "$CALL_LOG"
    grep -q "wget" "$CALL_LOG"
    grep -q "sudo" "$CALL_LOG"
}

@test "deploy_jellyfin: chiama kubectl apply" {
    run _run_func deploy_jellyfin
    grep -q "kubectl" "$CALL_LOG"
    grep "kubectl" "$CALL_LOG" | grep -q "apply"
}

@test "deploy_jellyfin: crea ~/deployment/ e vi copia il manifest" {
    run _run_func deploy_jellyfin
    [ -f "$HOME/deployment/jellyfin-deployment.yaml" ]
}

@test "deploy_jellyfin: stampa l'IP e la porta 30096" {
    run _run_func deploy_jellyfin
    [[ "$output" == *"192.0.2.1:30096"* ]]
}

@test "remove: chiama kubectl delete sul manifest Jellyfin" {
    # preposiziona il manifest finto dove remove lo aspetta
    mkdir -p "$HOME/deployment"
    cp "$JELLYFIN_DEPLOYMENT" "$HOME/deployment/jellyfin-deployment.yaml"
    run _run_func remove
    grep -q "kubectl" "$CALL_LOG"
    grep "kubectl" "$CALL_LOG" | grep -q "delete"
}

@test "remove: tenta di disinstallare K3s" {
    run _run_func remove
    [[ "$output" == *"Uninstalling K3s"* ]]
}

@test "remove: rimuove k9s con apt" {
    run _run_func remove
    grep -q "apt" "$CALL_LOG"
    grep "apt" "$CALL_LOG" | grep -q "k9s"
}

@test "remove: stampa 'Cleanup complete.'" {
    run _run_func remove
    [[ "$output" == *"Cleanup complete."* ]]
}

# ---------------------------------------------------------------------------
# ── fast-kub3.sh — routing del menu ─────────────────────────────────────────
# ---------------------------------------------------------------------------

# Esegue fast-kub3.sh in una sub-shell con PATH stub e input simulato.
# $1 = stringa da passare via stdin al menu
_run_menu() {
    local input="$1"
    echo "$input" | bash -c "
        export PATH='$PATH'
        export CALL_LOG='$CALL_LOG'
        export HOME='$HOME'
        export JELLYFIN_DEPLOYMENT='$JELLYFIN_DEPLOYMENT'
        export SCRIPT_DIR='$REPO_ROOT'
        export IP='192.0.2.1'
        # Sourcing: il guard in fast-kub3.sh NON avvia il menu automaticamente
        source '$REPO_ROOT/fast-kub3.sh'
        # Ri-definisce le funzioni come stub per testare solo il routing del menu
        install()        { echo 'CALLED:install'; }
        deploy_jellyfin(){ echo 'CALLED:deploy_jellyfin'; }
        remove()         { echo 'CALLED:remove'; }
        # Avvia il menu esplicitamente (sleep stubbato per non attendere davvero)
        sleep() { :; }
        menu
    "
}

@test "menu opzione 1: chiama install e termina con exit 0" {
    run _run_menu "1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CALLED:install"* ]]
    [[ "$output" != *"CALLED:deploy_jellyfin"* ]]
}

@test "menu opzione 2: chiama install e poi deploy_jellyfin" {
    run _run_menu "2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CALLED:install"* ]]
    [[ "$output" == *"CALLED:deploy_jellyfin"* ]]
}

@test "menu opzione 3: chiama remove" {
    run _run_menu "3"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CALLED:remove"* ]]
}

@test "menu opzione 0: esce senza chiamare funzioni" {
    run _run_menu "0"
    [ "$status" -eq 0 ]
    [[ "$output" != *"CALLED:"* ]]
}

@test "menu opzione invalida: stampa 'invalid option'" {
    # Prima una scelta invalida, poi 0 per uscire
    run _run_menu $'99\n0'
    [[ "$output" == *"invalid option"* ]]
}

@test "fast-kub3.sh sourced direttamente NON avvia il menu" {
    # Se viene source-ato (non eseguito), il menu non parte
    run bash -c "
        export PATH='$PATH'
        export HOME='$HOME'
        export SCRIPT_DIR='$REPO_ROOT'
        source '$REPO_ROOT/fast-kub3.sh'
        echo 'source_ok'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"source_ok"* ]]
}
