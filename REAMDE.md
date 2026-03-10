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

Every `python` invocation runs inside the Cinder container with your current directory mounted at `/app`. Before running, the entrypoint always typechecks the file with `cinderx.compiler --static`. If that passes, it runs with the configured JIT flags.

## Structured errors

All errors are written to stderr as a tuple:

```
("typecheck error", "<error>", "<stdout>")
("runtime error", "<stderr>", "<stdout>")
("docker error", "<message>", "")
```

`docker error` is emitted by the shim itself if the Docker daemon isn't running.

## Config file

Pass `--config=<file.json>` to control JIT flags. Without a config, all JIT flags are enabled by default.

```json
{
  "flags": ["-X", "jit", "-X", "jit-shadow-frame"],
  "jit_list": "hotfunctions.txt"
}
```

- `flags`: list of `-X` flags passed to the runtime (not the typechecker)
- `jit_list`: path to a JIT list file, relative to your working directory

## File layout

```
cinder_env/
├── Dockerfile
├── setup.sh
├── entrypoint.sh
├── shims/
│   ├── python
│   └── pip
└── scripts/
    └── parse_config.py
```