# calendar

Terminal calendar TUI with [omarchy](https://github.com/basecamp/omarchy) theme integration. Built with [Crystal](https://crystal-lang.org) and [crubbletea](https://github.com/baltavay/crubbletea).

## Keybindings

| Key | Action |
|-----|--------|
| `h` `j` `k` `l` / arrows | Move between days |
| `H` `L` | Previous / next month |
| `J` `K` | Next / previous year |
| `Ctrl+arrows` | Change month / year |
| `m` | Toggle Monday/Sunday as first day |
| `t` | Jump to today |
| `q` / `Ctrl+c` | Quit |

## Features

- Dynamic font scaling — day numbers grow with terminal size using Unicode block characters
- Omarchy theme — reads colors from `~/.config/omarchy/current/theme/colors.toml`, updates live on theme change
- Cursor navigation — move between days with wrap-around across month/year boundaries
- Persistent settings — first day of week saved in `~/.config/calendar/settings.json`

## Build

```
shards install
crystal build src/calendar.cr -o bin/calendar
```

## Run

```
bin/calendar
```
