# Third-party materials

Project-owned code is licensed under MIT; copyright (c) 2026 Leader contributors. Third-party materials retain their original licenses and are not relicensed by the project.

## Included graphical assets

- MakeHuman core meshes, targets, skin/hair assets and their derived character models: CC0-1.0. Provenance is recorded in `attribution/makehuman-sources.json`; upstream license notice is retained. This is not a redistribution of the MakeHuman application source. See https://static.makehumancommunity.org/about/license.html . Third-party community uploads are not automatically covered by core CC0; the recorded inputs are core/system assets.
- Poly Haven models and textures, including derived outdoor scenery: CC0-1.0. The source manifests in `attribution/` identify the inputs. See https://polyhaven.com/license . Poly Haven's website/code/API terms are separate from its graphical asset license.
- Cave layout, scene assembly and procedural modeling were developed for this prototype. The visual reference was a natural limestone cave; no reference video or official photograph is distributed as a texture.

## Downloaded/build-time dependencies

- Luau: MIT, pinned commit in `services/luau-runtime/dependencies.json`.
- nlohmann/json: MIT, version and header hash in the same file.
- Godot: separately installed, MIT. No Godot executable is included.
- FastAPI: MIT; Uvicorn: BSD-3-Clause; Google Cloud Text-to-Speech Python client: Apache-2.0. Installed separately through requirements; their transitive dependency licenses remain applicable.
- Codex/OpenCode, CapsWriter, Google Cloud CLI and model services are optional separately installed/configured components. No executors, authentication state, model weights or subscription entitlements are supplied.

Upstream Luau, JSON and CC0 texts are retained in `licenses/`. If distributing compiled binaries or additional third-party components later, include their applicable notices; this source preview does not claim that its code license covers them.
