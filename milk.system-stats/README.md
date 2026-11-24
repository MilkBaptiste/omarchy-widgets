# System stats bar buttons

User-owned Omarchy plugin displaying CPU usage, memory usage, and Intel GPU
clock speed. Click a button for details; click it again or press Escape to
close. The details panel can launch the installed `btop` system monitor.

Readings refresh every two seconds using Python's standard library and local
`/proc` and `/sys` files. No additional service, package, or elevated permissions
are required. CPU usage is calculated between samples, so the first reading
appears after two samples. Memory usage uses Linux `MemAvailable`.

The GPU label shows MHz, not utilization. The reader currently supports the
Intel i915 sysfs frequency files found on this machine. If readings become
unavailable, the button shows a dash.

The bar entry is `milk.system-stats` in `~/.config/omarchy/shell.json`.
The existing battery button is `omarchy.power`, with `showPercentage: true`.
Remove the `milk.system-stats` layout entry to hide these three buttons.
If saved changes do not appear, run `omarchy restart shell` from a desktop
terminal.

The original bar configuration was backed up to
`~/.config/omarchy/shell.json.bak.20261030-171142-system-stats`.
Keep this as a reference; restoring the entire backup also restores other bar
settings from that date.

Validation: manifest and bar JSON passed checks; the data reader returned
CPU, memory and Intel GPU readings. The user confirmed the buttons work on
the live desktop on 2026-10-30.
