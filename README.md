# Parcel-App
This is the newest updated app for our SD2 project.

# Git Workflow (GitHub Flow)

## Branches

- `main` is protected:
  - No direct commits.
  - No force-pushes.
- All work happens in short-lived branches.

## Branch naming

Use:

`<type>/<first-last>/<area>-<short-desc>`

where:
- `<type>` is one of: `feat`, `fix`, `hotfix`, `refactor`, `chore`, `docs`
- `<first-last>` is your name, lowercase, separated by `-`
- `<area>` is the main part of the system (e.g. `livemap`, `mqtt`, `rfid`, `ui`)

**Examples:**
- `feat/brian-zhang/livemap-panel`
- `fix/sara-lee/mqtt-reconnect-bug`
- `refactor/john-doe/parcel-service-cleanup`

## Flow for any change

1. Update `main`:
   ```bash
   git checkout main
   git pull

