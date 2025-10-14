# Maintenance

## Goals

- Keep SQLite statistics fresh and storage efficient without disrupting interactive usage or causing downtime. [attached_file:2]

## Heuristics

- The tool evaluates stats completeness, free space, fragmentation ratio \( \text{frag} = \frac{\text{page\_count}}{\text{page\_count} - \text{freelist\_count}} \) and WAL size thresholds to decide actions. [attached_file:2]
- Actions include ANALYZE, PRAGMA optimize, WAL checkpoint, and VACUUM or VACUUM INTO during safe windows. [attached_file:2]

## Usage

- Auto mode: ./tools/sqlite-maintenance.sh runs analysis and then applies the minimal needed operations. [attached_file:2]
- Cron mode: ./tools/sqlite-maintenance.sh --cron avoids VACUUM if the app is running, favoring lighter maintenance until a quiet window. [attached_file:2]
