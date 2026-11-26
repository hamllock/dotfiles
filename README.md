# dotfiles

My Hyprland desktop: Quickshell bar and popups, matugen wallpaper-based theming, and the apps it themes.

## Credits

The Hyprland + Quickshell setup is based on **[ilyamiro/nixos-configuration](https://github.com/ilyamiro/nixos-configuration)**.
fish, fastfetch and btop configs started from **[caelestia-dots/caelestia](https://github.com/caelestia-dots/caelestia)**.

## Layout

Each top-level folder is a [GNU Stow](https://www.gnu.org/software/stow/) package that mirrors `$HOME`:

```
hypr/.config/hypr      -> ~/.config/hypr
kitty/.config/kitty    -> ~/.config/kitty
...
```

| Package | What |
|---|---|
| hypr | Hyprland (Lua config), Quickshell widgets, scripts, SDDM theme |
| matugen | Color templates generated from the wallpaper |
| kitty, swayosd, qt5ct, qt6ct, vicinae | Apps themed by matugen |
| fish, starship, fastfetch, btop | Shell and terminal tools |
| nvim | Neovim (NvChad-based) |

## Install

```sh
sudo pacman -S stow
git clone <this repo> ~/dotfiles
cd ~/dotfiles
stow */          # or pick packages: stow hypr kitty nvim
```

Stow refuses to overwrite existing files. Back up or remove the existing `~/.config/<app>` first.

Uninstall a package: `stow -D <package>`.

## Setup after cloning

- **Wallpaper theming service:** skwd-wall runs `hypr/.config/hypr/scripts/wallpaper/skwd_bridge.sh` through a user service, which recolors everything when the wallpaper changes. Link and enable it (the SDDM sync units work the same way):
  ```sh
  systemctl --user link ~/.config/hypr/systemd/skwd-wall-bridge.service
  systemctl --user enable skwd-wall-bridge.service
  systemctl --user link ~/.config/hypr/sddm/systemd/sddm-sync.{path,service}
  systemctl --user enable --now sddm-sync.path
  ```

- **Weather:** copy `hypr/.config/hypr/scripts/quickshell/calendar/.env.example` to `.env` and fill in an [OpenWeather](https://openweathermap.org/api) key.
- **Neovim language servers** come from Mason. The LeetCode dashboard expects these: `:MasonInstall clangd clang-format pyright intelephense rust-analyzer` (TypeScript/JavaScript use typescript-tools, which needs `typescript` from npm).
- **SDDM fonts:** the `maclock` SDDM theme uses Apple's SF Pro fonts, which aren't included (license). Download them from [Apple](https://developer.apple.com/fonts/) and put the `.otf` files in `hypr/.config/hypr/sddm/maclock/fonts/`.

## License

MIT — see [LICENSE](LICENSE). This covers my own configs and scripts; third-party components credited above keep their own licenses, and the proprietary SF Pro fonts are not included.
