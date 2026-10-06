#!/usr/bin/env bash
# ============================================================================
# postinstall.sh — CachyOS no ASUS ZenBook Duo 14 (UX482EAR)
# Rodar DEPOIS de instalar o CachyOS (sem desktop) e bootar no console TTY.
# Instala e configura: base SST/thermald, quirks (NVMe/Wi-Fi/bateria),
# stack Wayland Niri + DankMaterialShell + companheiros.
#
# Uso:
#   ./postinstall.sh                     # padrão: tudo, sem DKMS
#   ./postinstall.sh --screenpad-dkms    # + DKMS Plippo (backlight ScreenPad)
#   ./postinstall.sh --battery-limit 80  # threshold de carga (60|80|100, 0=off)
#
# Kernel: usa o padrão do CachyOS (linux-cachyos) — NÃO mexe no kernel.
# ============================================================================
set -euo pipefail

SCREENPAD_DKMS=0
BATTERY_LIMIT=80
while [[ $# -gt 0 ]]; do
  case "$1" in
    --screenpad-dkms) SCREENPAD_DKMS=1; shift ;;
    --battery-limit) BATTERY_LIMIT="$2"; shift 2 ;;
    *) echo "Flag desconhecida: $1"; exit 1 ;;
  esac
done

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m AVISO:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m ERRO:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -x /usr/bin/pacman ]] || die "pacman não encontrado — rode isto num CachyOS."
[[ "$(id -u)" -eq 0 ]] && die "NÃO rode como root; o script usa sudo internamente."
command -v sudo >/dev/null || die "sudo ausente."

USER_NAME="$(id -un)"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"

# ----------------------------------------------------------------------------
pkg() { sudo pacman -S --needed --noconfirm "$@" </dev/null || { warn "Falhou: $*"; return 1; }; }
sudo_cmd() { sudo "$@" </dev/null; }

# ----------------------------------------------------------------------------
log "1/9 Firmware de áudio Intel SST — sem isto: 'Dummy Output'"
warn "Obrigatório também: Fast Startup DESLIGADO no Windows (amp do ALC294 congela)."
pkg sof-firmware alsa-ucm-conf alsa-utils || true

log "2/9 Thermald (zonas INT340X/DPTF do TGL — evita throttling exagerado)"
pkg thermald || true
sudo_cmd systemctl enable --now thermald.service || warn "thermald.service não ativou."

log "3/9 Base de rede/BIOS"
pkg linux-firmware networkmanager wpa_supplicant os-prober efibootmgr || true
sudo_cmd systemctl enable --now NetworkManager.service || true

log "4/9 Quirks de disco: NVMe SK hynix BC711 (incompatibilidade de APST)"
NVME_PARAM="nvme_core.default_ps_max_latency_us=0"
if [[ -f /boot/limine.conf ]] && sudo grep -qi 'cmdline[:=]' /boot/limine.conf; then
  if ! sudo grep -q "$NVME_PARAM" /boot/limine.conf; then
    # Limine: uma linha 'cmdline:'/'cmdline=' por entry — anexa em todas.
    sudo sed -i -E "/^([[:space:]]*cmdline[:=])/s/$/ $NVME_PARAM/" /boot/limine.conf
    log "   → parâmetro anexado em /boot/limine.conf (todas as entries)"
  else
    log "   → já presente em /boot/limine.conf"
  fi
elif [[ -f /etc/kernel/cmdline ]]; then
  if ! sudo grep -q "$NVME_PARAM" /etc/kernel/cmdline; then
    echo "$NVME_PARAM" | sudo tee -a /etc/kernel/cmdline >/dev/null
  fi
  log "   → parâmetro anexado em /etc/kernel/cmdline"
else
  warn "UNVERIFIED: nenhum /boot/limine.conf com cmdline nem /etc/kernel/cmdline."
  warn "Inspecione o entry do Limine e adicione manualmente: $NVME_PARAM"
fi

log "5/9 Quirks de Wi-Fi 6E (AX210) e Suspensão (s2idle only neste TGL)"
sudo_cmd tee /etc/NetworkManager/conf.d/70-wifi-powersave-off.conf >/dev/null <<'EOF'
[connection]
wifi.powersave = 2
EOF
# 'Microcode SW error' do iwlwifi em scan+tráfego intenso: remova '#' para ativar.
sudo_cmd tee /etc/modprobe.d/iwlwifi-ux482.conf >/dev/null <<'EOF'
# options iwlwifi disable_11ax=Y
EOF
mem="$(cat /sys/power/mem_sleep 2>/dev/null || true)"
grep -q '\[s2idle\]' <<<"$mem" || warn "mem_sleep=$mem — esperado [s2idle]; ajuste não é possível via script."

log "6/9 GPU Intel Iris Xe + VA-API"
pkg mesa vulkan-intel intel-media-driver libva-utils || true

log "7/9 Stack Wayland: Niri + portais + áudio gráfico"
pkg niri xwayland-satellite \
    xdg-desktop-portal-gnome xdg-desktop-portal-gtk \
    pipewire wireplumber pipewire-pulse || die "Stack Niri falhou."
# portal-wlr NÃO é suportado pelo niri; niri-portals.conf do pacote já aponta GNOME+GTK.

log "8/9 Display manager (greetd) — o wiki do niri NÃO recomenda TTY cru"
GREETER=""
if pkg greetd; then
  if pkg greetd-tuigreet; then GREETER="/usr/bin/tuigreet --time"; fi
  sudo_cmd tee /etc/greetd/config.toml >/dev/null <<EOF
[terminal]
vt = 1

[default]
command = "${GREETER:-niri-session}"
user = "greeter"

# Entrada única de autologin pós-instalação (o greeter assume depois):
[initial_session]
command = "niri-session"
user = "$USER_NAME"
EOF
  sudo_cmd systemctl enable greetd.service || warn "greetd.service não ativou."
else
  warn "greetd não instalado — entre por TTY com 'niri-session' (UNVERIFIED: risco exposto do wiki)."
fi

log "9/9 DankMaterialShell (dms-shell do repo [extra]) + companheiros"
pkg dms-shell || die "dms-shell ausente no repo — verifique pacman -Si dms-shell."
pkg hyprpolkitagent wl-clipboard cliphist wtype brightnessctl i2c-tools \
    pavucontrol playerctl matugen networkmanager bluez bluez-utils || true
sudo_cmd systemctl enable --now bluetooth.service || true

# Fontes de sistema (o runtime do DMS já embute Google Sans Flex/Material/FiraCode)
pkg inter-font ttf-fira-code ttf-nerd-fonts-symbols || true
if pkg paru || pkg yay; then
  AUR="$(command -v paru || command -v yay)"
  "$AUR" -S --needed --noconfirm ttf-material-symbols-variable-git </dev/null \
    || warn "Fonte de ícones AUR falhou (opcional)."
else
  warn "Sem helper AUR (paru/yay) — puxe ttf-material-symbols-variable-git manualmente (opcional)."
fi

log "Config niri do UX482EAR (se ainda não existir config)"
NIRI_DIR="$USER_HOME/.config/niri"
if sudo test ! -f "$NIRI_DIR/config.kdl"; then
  sudo_cmd install -d -o "$USER_NAME" -g "$USER_NAME" "$NIRI_DIR"
  sudo_cmd -u "$USER_NAME" tee "$NIRI_DIR/config.kdl" </dev/null >/dev/null <<'KDL'
// UX482EAR: tela principal + ScreenPad Plus (1920x515) ABAIXO.
// Confirme os nomes das saídas com: niri msg outputs
output "eDP-1" {
    scale 1.0
    position x=0 y=0
}
output "eDP-2" {
    scale 1.0
    position x=0 y=1080
}

// Backdrop das camadas do DMS
layer-rule {
    match namespace="^quickshell$"
    place-within-backdrop true
}
layer-rule {
    match namespace="^dms:blurwallpaper$"
    place-within-backdrop true
}

// Diálogos do DMS flutuantes
window-rule {
    match app-id=r#"^com\.danklinux\.dms$"#
    open-floating true
}

spawn-at-startup "bash" "-c" "wl-paste --watch cliphist store"

binds {
    Mod+Space { spawn "dms" "ipc" "call" "spotlight" "toggle"; }
    Mod+V     { spawn "dms" "ipc" "call" "clipboard" "toggle"; }
    Mod+N     { spawn "dms" "ipc" "call" "notifications" "toggle"; }
    Mod+M     { spawn "dms" "ipc" "call" "processlist" "toggle"; }
    Mod+Y     { spawn "dms" "ipc" "call" "dankdash" ""; }
    Mod+Comma { spawn "dms" "ipc" "call" "settings" "focusOrToggle"; }
    Mod+Alt+L { spawn "dms" "ipc" "call" "lock" "lock"; }
    XF86AudioRaiseVolume  { spawn "dms" "ipc" "call" "audio" "increment" "3"; }
    XF86AudioLowerVolume  { spawn "dms" "ipc" "call" "audio" "decrement" "3"; }
    XF86AudioMute         { spawn "dms" "ipc" "call" "audio" "mute"; }
    XF86MonBrightnessUp   { spawn "dms" "ipc" "call" "brightness" "increment" "5" ""; }
    XF86MonBrightnessDown { spawn "dms" "ipc" "call" "brightness" "decrement" "5" ""; }
}
KDL
  sudo_cmd systemctl --user add-wants niri.service dms || warn "Falhou add-wants dms (rode: systemctl --user add-wants niri.service dms)."
  log "   → config.kdl criado + serviço user dms ligado ao niri"
else
  warn "config.kdl já existe em $NIRI_DIR — NÃO sobrescrevi. Confira manualmente:"
  warn "   outputs (ScreenPad em y=1080), layer-rules quickshell/dms:blurwallpaper,"
  warn "   window-rule com.danklinux.dms, e 'systemctl --user add-wants niri.service dms'."
fi

if [[ "$BATTERY_LIMIT" != "0" ]]; then
  log "Threshold de bateria da ASUS: ${BATTERY_LIMIT}% (nativo via asus-nb-wmi)"
  case "$BATTERY_LIMIT" in 60|80|100) ;; *) warn "Valor inválido ($BATTERY_LIMIT) — skip."; BATTERY_LIMIT=0 ;; esac
fi
if [[ "$BATTERY_LIMIT" != "0" ]]; then
  sudo_cmd tee /usr/local/bin/asus-charge-threshold >/dev/null <<EOF
#!/bin/sh
printf '%s\n' "$BATTERY_LIMIT" > /sys/class/power_supply/BAT0/charge_control_end_threshold || true
EOF
  sudo_cmd chmod +x /usr/local/bin/asus-charge-threshold
  sudo_cmd tee /etc/systemd/system/asus-charge-threshold.service >/dev/null <<'EOF'
[Unit]
Description=ASUS charge control end threshold (UX482EAR)
After=multi-user.target
ConditionPathExists=/sys/class/power_supply/BAT0/charge_control_end_threshold

[Service]
Type=oneshot
ExecStart=/usr/local/bin/asus-charge-threshold

[Install]
WantedBy=multi-user.target
EOF
  sudo_cmd systemctl enable --now asus-charge-threshold.service || true
fi

if [[ "$SCREENPAD_DKMS" -eq 1 ]]; then
  log "ScreenPad Plus backlog: DKMS Plippo/asus-wmi-screenpad (backlight WMI DEVID 0x00050031)"
  pkg git base-devel dkms linux-cachyos-headers || die "Dependências do DKMS falharam."
  TMPD="$(mktemp -d)"
  git clone --depth 1 --recurse-submodules https://github.com/Plippo/asus-wmi-screenpad "$TMPD" \
    || die "clone Plippo/asus-wmi-screenpad falhou."
  if sudo make -C "$TMPD" module; then
    sudo make -C "$TMPD" install || warn "make install falhou."
    sudo modprobe asus_wmi_screentop 2>/dev/null \
      || warn "modprobe falhou — veja src/module/ do repo para o nome real do .ko e dkms."
    sudo rmdir "$TMPD" 2>/dev/null || sudo rm -rf "$TMPD"
    log "   → após carregar: brilho em /sys/class/leds/asus::screenpad/brightness (0-255)"
    log "   → scancodes 0x6a (toggle ScreenPad) e 0x9c ficam mapeados (FN keys)."
  else
    warn "Build do módulo falhou — verifique headers linux-cachyos-headers vs kernel em uso."
    warn "Guia manual + helper UI: github.com/lakinduakash/asus-screenpad-control"
  fi
  # UNVERIFIED: nome do módulo (asus-wmi-screenpad vs asus_wmi_screentop) e caminho de
  # instalação do make install deste fork; o script cobre o caminho make module+install.
fi

log "Resumo do estado:"
printf ' - thermald:      %s\n' "$(systemctl is-enabled thermald.service 2>/dev/null || echo off)"
printf ' - NetworkManager:%s\n' "$(systemctl is-enabled NetworkManager.service 2>/dev/null || echo off)"
printf ' - greetd:        %s\n' "$(systemctl is-enabled greetd.service 2>/dev/null || echo n/a)"
printf ' - bluetooth:     %s\n' "$(systemctl is-enabled bluetooth.service 2>/dev/null || echo n/a)"
printf ' - dms user-want: %s\n' "$(systemctl --user is-enabled dms.service 2>/dev/null || echo 'após login no niri')"
printf ' - arg NVMe:      aplicado em limine.conf/cmdline (reinicie p/ valer)'
[[ "$BATTERY_LIMIT" != "0" ]] && \
printf ' - bateria:       %s%% (charge_control_end_threshold)\n' "$BATTERY_LIMIT"

log "Pós-instalação concluída."
log "Sugestão: sudo reboot → entre por greetd → teste 'niri msg outputs' e 'dms ipc call spotlight toggle'."
log "Video do ScreenPad já sobe nativo; o BACKLIGHT dele só com --screenpad-dkms (== flag check)."
