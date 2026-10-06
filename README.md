# CachyOS no ASUS ZenBook Duo 14 (UX482EAR)

Guia de instalação **CachyOS minimal (sem desktop) → Limine → dual-boot Windows 11 → Niri + DankMaterialShell**, com todos os quirks de hardware desta máquina específica.

> Hardware de referência: ASUS ZenBook Duo 14 UX482EAR · BIOS UX482EAR.308 · i7-1195G7 (Tiger Lake, 4C/8T, AVX-512) · Intel Iris Xe (**sem** dGPU/MUX) · 16 GB LPDDR4x-4267 soldada · NVMe SK hynix BC711 1 TB · Wi-Fi 6E Intel AX210 · Áudio Realtek ALC294 + Intel SST · Tela principal 14" FHD IPS 60Hz touch + ScreenPad Plus (IPS 1920×515 @60Hz) · Webcam USB UVC.

## Como rodar o `postinstall.sh` (pós-instalação do CachyOS)

1. Instale o CachyOS **sem desktop** (guia §1), dê **reboot**, faça login no console TTY do usuário criado.
2. Conecte o Wi-Fi no TTY:
   ```bash
   sudo systemctl start NetworkManager
   nmtui   # ativar Wi-Fi e conectar
   ```
3. Baixe e rode:
   ```bash
   sudo pacman -Syu git
   git clone https://github.com/Gabriel-Freitas-S/cachyos-zenbook-duo.git
   cd cachyos-zenbook-duo
   chmod +x postinstall.sh
   ./postinstall.sh --screenpad-dkms   # DKMS opcional (backlight do ScreenPad + FN 0x6a)
   ```
   Alternativa sem `git` (sem pipe-to-sh; **leia o conteúdo antes de rodar**):
   ```bash
   curl -fsSL -o postinstall.sh https://raw.githubusercontent.com/Gabriel-Freitas-S/cachyos-zenbook-duo/main/postinstall.sh
   less postinstall.sh   # revisão manual
   chmod +x postinstall.sh && ./postinstall.sh
   ```
4. Flags: `--screenpad-dkms` (instala DKMS Plippo p/ backlight do ScreenPad) · `--battery-limit 60|80|100` (padrão 80; `0` desativa).
5. `sudo reboot` → greetd (autologin único) → Niri + DMS. Verificação: `_§6 Checklist_` do guia.

> O script usa o kernel padrão do CachyOS (`linux-cachyos` — BORE já embutido) e não mexe no kernel.

---

## 0. Preparação no Windows (ANTES de bootar a ISO)

1. **Secure Boot OFF** — BIOS ASUS (botão F2 → *Advanced → Secure Boot* → Disabled). O guia usa Limine direto, sem shim/sbctl.
2. **Fast Startup OFF** — Windows: *Painel de Energia → Escolher a função dos botões → Desativar inicialização rápida*.
   - **Por quê:** o Bluetooth falha após o dual-boot e o amplificador do ALC294 fica travado em low power (áudio mudo) enquanto o Fast Startup estiver ligado. Fontes: AskUbuntu #1352495, ArchWiki.
3. Feche o Windows com shutdown completo (`shutdown /s /t 0`), não reinicie para a ISO — precisa de cold boot.

## 1. Instalação do CachyOS

### 1.1 Isos e caminho de instalação

- Use a ISO **CachyOS** (Calamares) — o instalador só pede "Desktop environment": **escolha "No Desktop"** para subir um sistema nu (caminho oficial suportado; ver wiki cachyos.org: *Installation on root*).
- O instalador CachyOS detecta automaticamente o nível da CPU: este i7-1195G7 tem AVX-512 → qualifica para os repos **cachyos-v3/v4** (builds otimizadas x86-64-v4). Deixe como detectado.
- **Kernel padrão CachyOS (BORE)** já vem com `SCHED_BORE` — mantenha, é o escolhido para estabilidade + performance responsiva.
- **Bootloader = Limine**: o layout **Limine + btrfs + zstd com subvolumes é o default do instalador** — aceite o layout padrão. Com Limine a ESP pode ser menor que com GRUB.
- **Dual boot:** na partição manual, NÃO toque na ESP do Windows (260 MB), MSR, nem na partição Recovery. O Limine deve detectar a entrada do Windows UEFI automaticamente; se não, adicione a entrada `.efi` manualmente no menu do Limine (limine.conf).

### 1.2 Particionamento sugerido (dual boot, no NVMe SK hynix BC711)

- **ESP** (a já existente do Windows, ~260 MB): monte em `/boot/efi` (Limine compartilha a ESP do Windows).
- **/ (btrfs + zstd, subvolumes @, @home, @root, @srv, @snapshots, @cache)**: use o espaço livre restante (não encoste na Recovery).
- Sem swap em disco — o sistema usa **zram** (item 3.3).

## 2. Primeiro boot — sistema base

```bash
# 2.1 Thermald (THROTTLING! Este notebook tem zonas INT340X/DPTF que precisam acabar
#     antes do throttling da ASUS)
sudo pacman -S thermald
sudo systemctl enable --now thermald

# 2.2 Firmware de áudio OBRIGATÓRIO (Intel SST/Tiger Lake — sem isso: "Dummy Output")
sudo pacman -S sof-firmware alsa-ucm-conf alsa-utils

# 2.3 Firmware Wi-Fi/BT e NVMe (já presente no CachyOS, confirme)
sudo pacman -S linux-firmware

# 2.4 Rede
sudo pacman -S networkmanager network-manager-applet wpa_supplicant
sudo systemctl enable --now NetworkManager

# 2.5 Utilidades de boot/dual-boot
sudo pacman -S os-prober efibootmgr
```

## 3. Quirks de hardware (específicos deste máquina)

### 3.1 Kernel params (mkinitcpio: `/boot/loader/entries/*.conf` ou `/etc/kernel/cmdline`)

```
nvme_core.default_ps_max_latency_us=0
```
- **Por quê:** o NVMe **SK hynix BC711** tem incompatibilidade de APST documentada — sem esse parâmetro o disco congela sob carga/ACPI deep idle. (Alternativa: `2000`/`5000` para manter alguns estados de consumo.)

Aplicar:
```bash
/etc/mkinitcpio.conf
HOOKS=(base systemd autodetect microcode kms modconf block keyboard sd-vconsole filesystems)
```
- O padrão CachyOS com Limine/btrfs já é systemd-based e dispensa o hook `fsck` em btrfs — não mexa.

### 3.2 ScreenPad Plus — o Quirk MAIOR

- **Vídeo da segunda tela: funciona nativamente** — o DRM i915/xe já expõe ela como segunda saída eDP/DP (`niri msg outputs` para confirmar nomes reais: eDP-1 principal 1920×1080, DP/eDP-2 o ScreenPad 1920×515).
- **Backlight do ScreenPad: sem módulo mainline** — o WMI de brilho (DEVID `0x00050031`) exige o DKMS **`Plippo/asus-wmi-screenpad`** (não é mais um bug de kernel: nunca suportado). Pós-DKMS, brilho em:
  `/sys/class/leds/asus::screenpad/brightness` (0–255).
- **Touchscreen duplicated (ELAN):** mapeie explicitamente o dispositivo ELAN secundário à saída certa no Wayland (ver config Niri na seção 7).
- **Geometria:** o padrão lado-a-lado fica errado — force `position x=0 y=1080` no output do ScreenPad.
- **DPMS:** apagar o backlight não para o compositor de renderizar (consumo de bateria) — espere desligar o ScreenPad manualmente quando não usar, com `brightness 0`.
- Toggle do ScreenPad (tecla FN WMI scancode **0x6a**) e troca de janelas (0x9c): **NÃO mapeados no mainline** (`dmesg | grep -i 'Unknown key'`) — o mesmo DKMS `Plippo/asus-wmi-screenpad` adiciona os keycodes; só então o FS key vira configurável no Niri.

### 3.3 Áudio Intel SST (isso resolve o "sem som")

```text
# sof-firmware + alsa-ucm-conf (item 2.2) → driver snd_sof_pci_intel_tgl
# Fallback extremo: snd-intel-dspcfg dsp_driver=1 (HDA legado) — ATENÇÃO:
# esse fallback MATA os microfones duplos (DMIC). Use só se o SOF falhar de vez.
```
Lembre-se também do fix **Fast Startup** da seção 0: sem ele o amp do ALC294 fica em low power e o som fica mudo mesmo com driver carregado.

### 3.4 Exclusões por hardware

- **NÃO instale `supergfxctl`** — este máquina é iGPU-only (Iris Xe, sem dGPU nem MUX); o `/usr/lib/systemd/system/supergfxd.service` nem vai subir.
- **NÃO instale `asusctl`/`asusd`** — depende do WMI ROG/Gaming que este Duo **não tem** (querra quebrando o asusd). Alternativa de controle de fan só se realmente precisar: `github.com/dianlight/asus-zenbook-duo-fan-control`.

### 3.5 Wi-Fi 6E AX210 (quirks leves, guarde para o dia do erro)

```conf
# /etc/modprobe.d/iwlwifi.conf  — só se der "Microcode SW error" em scan+tráfego intenso:
options iwlwifi disable_11ax=Y

# /etc/NetworkManager/conf.d/wifi-powersave.conf — desliga powersave (evita drops):
[connection]
wifi.powersave = 2
```
- 6 GHz (Wi-Fi 6E) só libera depois do primeiro beacon AWDL/LAR de uma banda 6E — comportamento normal.

### 3.6 Suspensão / Bateria

- **s2idle only** — este Z Abyss (TGL) não tem S3: `cat /sys/power/mem_sleep` deve mostrar `[s2idle]`. Dreno esperado: 1,5–4%/h.
- **APST do NVMe** → o `nvme_core.default_ps_max_latency_us=0` da seção 3.1 já resolve a maior fonte de dreno/crash.
- **Hibernate** (suspend-then-hibernate, 1h):
  ```text
  # /etc/systemd/sleep.conf
  [Sleep]
  HibernateDelaySec=1h   # precisa de resume= no kernel params e swap suficiente (ver zram abaixo)
  # /etc/systemd/logind.conf
  HandleLidSwitch=suspend-then-hibernate
  ```
- **Battery health (threshold):** nativo, funciona sem pacote:
  ```bash
  echo 80 | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold
  ```
  Valores aceitos pelo firmware: 60 / 80 / 100. Persista via ppd ou script/udev próprio.

### 3.7 Webcam / Biometria

- Webcam USB UVC: funciona direto, sem quirk.
- Autenticação facial (Windows Hello — People ID 268): pacote **`Howdy`** (AUR) → `github.com/boltgolt/howdy`.

## 4. Gerenciamento de energia (o par ROSADO correto)

- ✅ **power-profiles-daemon** (default do CachyOS) — exposto via D-Bus; o DankMaterialShell lê dele. Integrado com o `scx_loader` (sched_ext) do CachyOS.
- ❌ **NÃO instale `tlp` nem `auto-cpufreq`** — ambos conflitam com o `intel_pstate` do Tiger Lake e interferem com o power-profiles-daemon.

- **zram já é default do CachyOS**: `zram-generator` com `zram-size = ram` (device de 16 GiB, compactado — não ocupa 16 GiB reais), compactador **zstd**, `swappiness 150`, zswap desativado. Mantenha o default. Se quiser hibernar (seção 3.6), precisará também de um arquivo de swap real na btrfs ≥ RAM, pois zram não serve para hibernar.

## 5. Niri + DankMaterialShell

### 5.1 Pacotes base do Wayland/Graph stack

```bash
# Getting Started oficial do wiki niri (lista completa):
sudo pacman -Syu \
  niri xwayland-satellite \
  xdg-desktop-portal-gnome xdg-desktop-portal-gtk \
  pipewire wireplumber pipewire-pulse \
  waybar  # (opcional — desativo no Niri, pois o DMS já é a barra)

# GPU Intel Iris Xe (TGL):
sudo pacman -S mesa vulkan-intel intel-media-driver  # VA-API p/ decode/aceleração

# Portais: NÃO usar xdg-desktop-portal-wlr (não suportado pelo niri).
# Screencast/WebRTC = portal GNOME + PipeWire; GTK como fallback de diálogos.
# Layout de portais standard já em /usr/share/xdg-desktop-portal/niri-portals.conf
```

- xwayland-satellite é a porta de compatibilidade X11 (niri não tem server X11 interno); é opcional ― rode-o no spawn se precisar de apps X11.

### 5.2 Sessão

- **Recomendação do wiki niri: entre por um Display Manager (greetd é o mais leve), NÃO por TTY cru.**
  - `/usr/share/wayland-sessions/niri.desktop` executa `/usr/bin/niri-session` (ativa `niri.service` user-level + `graphical-session.target`).
  ```bash
  sudo pacman -S greetd greetd-gtkgreet
  sudo systemctl enable greetd.service
  ```

### 5.3 DankMaterialShell (DMS) + quickshell

```bash
# DMS está no repo [extra] (não precisa de AUR):
sudo pacman -S dms-shell       # v1.6.2+ (replace do antigo dms-shell-niri)
# quickshell já vem como dependência direta:
# extra/quickshell v0.3.1+ (DMS 1.6 exige quickshell >= 0.3.0)
```

- **Instalar o serviço** do DMS *dentro* do Niri:
  ```bash
  systemctl --user add-wants niri.service dms
  # alternativa (config.kdl): spawn-at-startup "dms" "run"
  ```
- **REMOVA o `spawn-at-startup "waybar"`** do seu config.kdl — o DMS já inclui barra + notificações + launcher + lock + wallpapers.
- Coisas que o DMS **substitui:** launcher (Spotlight), notificações, lock screen, gerenciador de wallpaper, visualizador de clipboard.

### 5.4 Companheiros mínimos

```bash
sudo pacman -S hyprpolkitagent wl-clipboard cliphist wtype \
     brightnessctl i2c-tools pipewire wireplumber pipewire-pulse \
     pavucontrol playerctl networkmanager bluez bluez-utils
sudo systemctl enable --now bluetooth.service

# daemon do clipboard (o DMS só visualiza):
spawn-at-startup "bash" "-c" "wl-paste --watch cliphist store &"
```
- Launcher/lock/notifications/wallpaper **já são nativos do DMS** — não instale fuzzel/mako/swaylock/swaybg.
- `matugen` (do repo [extra]) roda na troca de wallpaper do DMS → gera `~/.config/niri/dms/colors.kdl`, temas GTK e o esquema ANSI dank16 automaticamente.

### 5.5 Fontes

```bash
sudo pacman -S inter-font ttf-fira-code ttf-nerd-fonts-symbols
# ícones Material Symbols no sistema (AUR):
paru -S ttf-material-symbols-variable-git
```
- As fontes do runtime do DMS (Google Sans Flex, Material Symbols, FiraCode Nerd Font) já vem embutidas via `dank-qml-common` — os pacotes de sistema acima são para o resto do shell (apps GTK/QT, terminal).

### 5.6 Config do Niri — UX482EAR (3 edições obrigatórias)

```kdl
// 1) Duas telas eDP — ScreenPad ABAIXO da principal (geometria real do hardware):
output "eDP-1" {
    scale 1.0
    position x=0 y=0      // principal 1920x1080
}
output "eDP-2" {           // ou o nome real que niri msg outputs mostrar (DP-1 etc.)
    scale 1.0
    position x=0 y=1080   // ScreenPad 1920x515 — sempre ABAIXO
}

// 2) Backdrop para as camadas do DMS (quickshell + wallpaper blur):
layer-rule {
    match namespace="^quickshell$"
    place-within-backdrop true
}
layer-rule {
    match namespace="^dms:blurwallpaper$"
    place-within-backdrop true
}

// 3) Diálogos do DMS flutuantes:
window-rule {
    match app-id=r#"^com\.danklinux\.dms$"#
    open-floating true
}
```

### 5.7 Binds recomendados (IPC do DMS, bloco `binds` do config.kdl)

```kdl
binds {
    Mod+Space { spawn "dms" "ipc" "call" "spotlight" "toggle"; }
    Mod+V     { spawn "dms" "ipc" "call" "clipboard" "toggle"; }
    Mod+N     { spawn "dms" "ipc" "call" "notifications" "toggle"; }
    Mod+M     { spawn "dms" "ipc" "call" "processlist" "toggle"; }
    Mod+Y     { spawn "dms" "ipc" "call" "dankdash" ""; }
    Mod+Comma { spawn "dms" "ipc" "call" "settings" "focusOrToggle"; }
    Mod+Alt+L { spawn "dms" "ipc" "call" "lock" "lock"; }
    // teclas XF86 (volume/brilho do teclado ASUS):
    XF86AudioRaiseVolume   { spawn "dms" "ipc" "call" "audio" "increment" "3"; }
    XF86AudioLowerVolume   { spawn "dms" "ipc" "call" "audio" "decrement" "3"; }
    XF86AudioMute          { spawn "dms" "ipc" "call" "audio" "mute"; }
    XF86MonBrightnessUp    { spawn "dms" "ipc" "call" "brightness" "increment" "5" ""; }
    XF86MonBrightnessDown  { spawn "dms" "ipc" "call" "brightness" "decrement" "5" ""; }
}
```
- FN keys principais (volume, mute, F7/F8 brilho, retroiluminação do teclado) funcionam **nativamente** via `asus-nb-wmi` — sem pacote extra.
- O toggle do ScreenPad (scancode WMI 0x6a) fica usável **só** depois do DKMS Plippo (seção 3.2).

---

## 6. Checklist de verificação pós-instalação

```bash
# CPU/Turbo/sched
cat /sys/devices/system/cpu/intel_pstate/status    # active
grep -c BORE /proc/loadavg 2>/dev/null || uname -v # kernel CachyOS BORE

# Disco (APST fixado)
sudo dmesg | grep -i nvme                          # sem stall/hang de BC711

# Áudio (SOF ok, sem dummy)
pactl info | grep -i default
dmesg | grep -E 'sof|snd_sof'

# Wi-Fi
iwctl station wlan0 show                           # AX210 6E

# Telas
niri msg outputs                                   # eDP-1 + eDP-2(ScreenPad)

# DMS vivo
systemctl --user status dms
dms ipc call spotlight toggle

# ScreenPad backlight (após DKMS)
cat /sys/class/leds/asus::screenpad/brightness
```

---

## 7. Itens UNVERIFIED (junta que precisa de teste no metal real)

1. **Scancodes 0x6a / 0x9c upstream** — fontes de 2024/2025 citam o Plippo DKMS como indispensável; versões 6.12+ do kernel podem ter introduzido o mapeamento sem nós ver — teste `dmesg` antes de instalar o DKMS.
2. **Interface de brilho secundária no sysfs** — sem rodar o DKMS não há como saber o caminho exato; inspecione `ls /sys/class/backlight/` depois.
3. **Modelo do amp/tweeters secundário** (CS35L41 vs TAS2781) — não confirmado por probe; sem alternativa real de quirk por enquanto.
4. **Nome exato da saída do ScreenPad no Niri** — `eDP-2` ou `DP-1`; confirmar com `niri msg outputs`.
5. **Secure Boot** — status não concluível pelo Windows API adversas; vamos OFF de qualquer forma (decisão do usuário).

## Fontes principais

- CachyOS: wiki.cachyos.org/installation/installation_on_root, wiki.cachyos.org/features/cachyos_settings, wiki.cachyos.org/configuration/general_system_tweaks, github.com/CachyOS/cachyos-calamares, github.com/CachyOS/New-Cli-Installer
- Niri: archlinux.org/packages/extra/x86_64/niri/, github.com/YaLTeR/niri/wiki/Getting-Started
- DMS: archlinux.org/packages/extra/x86_64/dms-shell/, github.com/AvengeMedia/DankMaterialShell (install.danklinux.com / dankinstall)
- ScreenPad/quirks: github.com/Plippo/asus-wmi-screenpad, github.com/lakinduakash/asus-screenpad-control, github.com/flukejones/asusctl issue #188, ArchWiki ALSA (SOF), ArchWiki Laptop/ASUS
- Áudio dual-boot: askubuntu.com/questions/1352495
- NVMe BC711 APST: relatos Aranha/ArchWiki ( unidades SK hynix)
- Howdy: github.com/boltgolt/howdy
