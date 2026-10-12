# Control Center for the Omarchy bar

The everyday switches and sliders behind one icon on the [Omarchy](https://omarchy.org) bar, laid out after the macOS Control Center.

> **A note on how this was made:** I am not a software engineer or programmer. I built this with an AI assistant (Claude) for my own Omarchy setup and I am sharing it as is. It works on my machine; I cannot promise more than that. Issues and pull requests are welcome, but I may not be able to fix things myself.

**Status: experimental.** Tested on Omarchy 4.0.4 with Hyprland 0.56.2 only.

## What it does

Clicking the icon drops a card of tiles:

- **Connections:** Wi-Fi, Bluetooth and LocalSend, each with what it is connected to. An AirDrop row can be turned on if the omdrop plugin is installed.
- **Switches:** Do Not Disturb, Night Light and Stay Awake.
- **Sliders:** display brightness and volume.
- **Batteries:** up to five peripherals.

The round buttons switch things on and off in place. The rest of a row opens Omarchy's own panel for that subject beside the card, so nothing about those panels is reimplemented here.

## Install

```
omarchy plugin add https://github.com/trevorwdunn/omarchy-control-center --enable
```

You will probably want to remove the separate network, Bluetooth and audio widgets from the bar afterwards.

## Peripheral batteries

Batteries come from four places:

- **UPower**, for Bluetooth devices and anything else the system already reports.
- **`batteries.py`**, for Keychron mice and for Logitech devices on a Bolt receiver, which are asked directly over hidraw. It only sends read-only status queries.
- **`headsetcontrol`**, if installed, for wireless headsets.
- **librepods**, if running, for AirPods.

`batteries.py` needs access to the hidraw devices. `batteries.rules` grants it to the logged-in user; the commands to install it are at the top of that file and need `sudo`. Without the rule those devices are simply not listed.

## Optional pieces

Rows for things you do not have stay empty or hidden: LocalSend needs the `bredda.localsend` plugin, AirDrop needs `netmojo.omdrop`. For the network row it first looks for a cloned panel at `~/.config/omarchy/plugins/trevor.network` (that is my own setup) and otherwise uses the stock one.

## Settings

`retreatDelayMs` and `retreatDistance` control how quickly the card closes when the pointer moves away; `showAirdrop` adds the AirDrop row. See `manifest.json`.

## Known limits

- **It leans on the bar's internals.** Omarchy's panels expect the real bar object, which a third-party widget is not given, so this borrows it from a neighbouring built-in widget. An Omarchy update can break it; if that happens the rows simply stop opening.
- **The battery queries are specific to the devices I own** (a Keychron mouse and a Logitech Bolt receiver). Other models from those makers may not answer the same way.

## Licence

GPL-3.0-or-later. You may use, change and share this for any purpose; if you distribute a changed version, its source has to be available under the same licence. See `LICENSE`.
