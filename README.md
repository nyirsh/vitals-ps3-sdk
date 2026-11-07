# vitals-ps3-sdk

The build environment for [vitals-ps3](../vitals-ps3) as a Docker image: RPCS3's PS3DK (GCC for the
PPU and SPU, PSL1GHT, prx-gen for PRX and SPRX modules) built from source at a pinned commit, with
vitals' patch to prx-gen. PS3DK only ships prebuilt for Windows, and building it takes hours, so
this project builds it once and publishes the image.

The image is about 1.5 GB, for `linux/amd64` and `linux/arm64`.

## Using it

```bash
docker pull ghcr.io/OWNER/vitals-ps3-sdk:latest
```

or from GitLab or Docker Hub:

```bash
docker pull registry.gitlab.com/NAMESPACE/vitals-ps3-sdk:latest
```

```bash
docker pull nyirsh/vitals-ps3-sdk:latest
```

Then, in vitals-ps3, point the Makefile at it instead of building it locally:

```bash
make IMAGE=ghcr.io/OWNER/vitals-ps3-sdk:latest
```

Commands run in the image get the toolchain from its login shell (`PS3DEV` and the rest):

```bash
docker run --rm -v "$PWD":/src -w /src ghcr.io/OWNER/vitals-ps3-sdk bash -lc 'ppu-gcc --version'
```

## Tags

| Tag              | What it is                                                               |
| ---------------- | ------------------------------------------------------------------------ |
| `latest`         | The default branch's newest build                                        |
| `ps3dk-<commit>` | The newest build of that PS3DK commit (`PS3DK_COMMIT` in the Dockerfile) |
| `sha-<commit>`   | The build of this repository's commit                                    |
| `v1`, `v2`…      | A git tag                                                                |

Every tag holds both architectures. GitLab also keeps `sha-<commit>-amd64` and `-arm64`, the
per-architecture images the others are made from; a cleanup policy (Settings > Packages and
registries) can remove the old ones.

## What's here

- `Dockerfile`: two stages. The first builds PS3DK and applies the patches, about 25 GB with GCC's
  build trees and sources; the second is a fresh Ubuntu 24.04 with the installed SDK, its host
  programs stripped, and only the packages running them needs.
- `patches/prx-gen-split-segments.patch`: vitals' change to prx-gen (the Dockerfile says what it
  does).
- `.github/workflows/publish.yml`: GitHub Actions, publishing to `ghcr.io/<owner>/vitals-ps3-sdk`.
- `.gitlab-ci.yml`: GitLab CI, publishing to the project's container registry.

Either CI also copies the image to Docker Hub when it has Docker Hub credentials (see below).

These are a copy of vitals-ps3's `tools/docker`, which vitals-ps3's `make image` still builds from.
A change to one should be made to the other until vitals-ps3 uses the published image.

## When the CI runs

On a push to the default branch that changes the Dockerfile, the patches or the CI file; on a
`v*` tag; and by hand (GitHub: Actions > Publish image > Run workflow; GitLab: Build > Pipelines >
Run pipeline).

Both build each architecture natively, on its own runner, then join the two under one tag:
building GCC under emulation would take far longer than any runner allows.

## Building it locally

```bash
docker build -t vitals-ps3-sdk .
```

The builder stage's layers stay in Docker's build cache (about 17 GB), which makes a rebuild quick;
`docker builder prune` frees it.
