# Control Center for the Omarchy bar

One bar icon for network, Bluetooth and volume on the [Omarchy](https://omarchy.org) bar. Clicking it drops a small menu; each row opens the full panel for that subject beside the menu.

> **A note on how this was made:** I am not a software engineer or programmer. I built this with an AI assistant (Claude) for my own Omarchy setup and I am sharing it as is. It works on my machine; I cannot promise more than that. Issues and pull requests are welcome, but I may not be able to fix things myself.

**Status: experimental.** Tested on Omarchy 4.0.4 with Hyprland 0.56.2 only.

## How it works

The rows open Omarchy's own network, Bluetooth and audio panels, so nothing about those panels is reimplemented here. For the network row it first looks for a cloned panel at `~/.config/omarchy/plugins/trevor.network` (that is my own setup) and otherwise uses the stock one.

## Install

```
omarchy plugin add https://github.com/trevorwdunn/omarchy-control-center --enable
```

You will probably want to remove the separate network, Bluetooth and audio widgets from the bar afterwards.

## Settings

`retreatDelayMs` and `retreatDistance` control how quickly the menu closes when the pointer moves away. See `manifest.json`.

## Known limits

- **It leans on the bar's internals.** Omarchy's panels expect the real bar object, which a third-party widget is not given, so this borrows it from a neighbouring built-in widget. An Omarchy update can break it; if that happens the rows simply stop opening.

## Licence

GPL-3.0-or-later. You may use, change and share this for any purpose; if you distribute a changed version, its source has to be available under the same licence. See `LICENSE`.
