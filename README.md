# Widevine Installer for Firefox Flatpak (ARM64)

Install Widevine DRM for Firefox Flatpak on aarch64 Linux systems.

## Requirements

- ARM64/aarch64 architecture
- glibc ≥ 2.36
- Firefox Flatpak installed
- `curl`, `squashfs-tools`, `python3`

## Installation

```bash
chmod +x install-widevine-flatpak.sh
./install-widevine-flatpak.sh
```

Restart Firefox after installation.

## Verify

- Visit `about:plugins` in Firefox
- Test on Netflix or Spotify

## Uninstall

```bash
rm -rf ~/.var/app/org.mozilla.firefox/widevine
flatpak override --user --reset org.mozilla.firefox
```

## Credits

- Original patcher: [@DavidBuchanan314](https://github.com/DavidBuchanan314)
- Improvements: [@marcan](https://github.com/marcan)

## License

MIT (see LICENSE file)

Note: Widevine itself is proprietary Google software.
