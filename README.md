# translator

A keyboard-driven, offline translation dictionary for the terminal, built on
[sdcv](https://github.com/Dushistov/sdcv) and StarDict dictionaries. Designed for
low-powered machines. See [ROADMAP.md](ROADMAP.md) for the plan.

## Development

Development happens in Docker; the app itself is installed natively, not shipped
as a container.

```sh
docker compose build                # Python 3.8 + sdcv + pytest
docker compose run --rm app         # run the TUI
docker compose run --rm test        # run the tests
docker compose run --rm app bash    # shell with sdcv on PATH
```

Put StarDict dictionaries (each a folder with `.ifo`, `.idx`, `.dict[.dz]`) in
`./dictionaries/`. They're mounted read-only at `/data/dic` and ignored by git.
Containers have no network access, which matches how the app runs in practice.

To check against a newer Python: `docker compose build --build-arg PYTHON_VERSION=3.12`.
