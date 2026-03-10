# cinder-env

Pyenv shim for running Cinder (Meta's CPython fork) via Docker.

## Prerequisites

- Docker
- pyenv

## Setup

```bash
./cinder_env/setup.sh
pyenv local cinder
```

## Usage

```bash
python script.py
python --config=cinder.json script.py
pip install somepackage
```

## How it works

Every `python` invocation runs inside a persistent Cinder container with your current directory mounted at `/app`. Before running, the entrypoint always typechecks the file with `cinderx.compiler --static`. If that passes, it runs with the configured JIT flags. A fresh `/scratch` directory is created inside the container on every invocation.

## Structured errors

All errors are written to stderr as a tuple:

```
("typecheck error", "<error>", "<stdout>")
("runtime error", "<stderr>", "<stdout>")
("docker error", "<message>", "")
```

`docker error` is emitted by the shim if the Docker daemon is not running.

## Config file

Pass `--config=<file.json>` to control JIT flags. Without a config, all JIT flags are enabled and `jitlist_main.txt` is used by default.

```json
{
  "flags": ["-X", "jit", "-X", "jit-shadow-frame"],
  "jit_list": "/path/to/jit-list.txt"
}
```

- `flags` — list of `-X` flags passed to the runtime (not the typechecker)
- `jit_list` — path to a JIT list file. Defaults to `/jitlist_main.txt` baked into the image.

## File layout

```
cinder_env/
├── Dockerfile
├── setup.sh
├── entrypoint.sh
├── jitlist_main.txt
├── shims/
│   ├── python
│   └── pip
└── scripts/
    └── parse_config.py
```