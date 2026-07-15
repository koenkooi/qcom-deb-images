---
name: debos-build
description: >-
  Run, validate, and debug the debos image builds in this repo (qcom-deb-images
  / Arduino UNO Q downstream). Use when asked to build a rootfs/disk/flash
  image, render or lint a debos recipe, reproduce a CI build locally, or verify
  a recipe change. Covers the Makefile targets, the raw debos invocations CI
  uses, the container-vs-native toolchain, and how to fan the work out across
  right-sized subagents.
---

# debos-build

Build and validate the debos images in this repo. debos renders a YAML recipe
(Go templates) into a sequence of actions run inside a fakemachine VM.

## 0. Orient first (cheap)

Before building anything, confirm the toolchain and pick the fastest useful
check. A full build is minutes-to-tens-of-minutes and needs KVM; a template
render is seconds.

```sh
command -v debos docker ; ls -l /dev/kvm 2>/dev/null   # what's available
debos --help >/dev/null 2>&1 && echo "native debos present"
```

Key fact about this host class: a **stale native debos** (e.g. the 2020 Debian
package) fails on recipes that use newer template funcs like `split` with
`function "split" not defined`. That is a *tooling* problem, not a recipe bug.
When native debos is old or missing, use the container (below) — it is what CI
and the Makefile default to.

## 1. Toolchain: container vs native

The Makefile auto-selects (`USE_CONTAINER=auto`): native if `debos` is on PATH,
else the container `ghcr.io/go-debos/debos:latest`. Force it with
`make USE_CONTAINER=yes|no ...`.

Raw container invocation (mirrors the Makefile's `DEBOS_CMD`), useful for
one-off renders and lint:

```sh
docker run --rm --user "$(id -u)" --workdir /recipes \
  --mount "type=bind,source=$(pwd),destination=/recipes" \
  --security-opt label=disable \
  ${KVM:+--device /dev/kvm} \
  ghcr.io/go-debos/debos:latest \
  <debos-args...>
```

Add `--device /dev/kvm` for real builds (fakemachine needs it; without it debos
falls back to the much slower qemu backend). Omit it for `--dry-run` renders.

## 2. Validate a recipe WITHOUT building (seconds)

`--dry-run --print-recipe` renders the Go template and prints the final recipe
without executing any action. This is the first thing to run after any recipe
or overlay change — it catches template/syntax errors and shows the effective
package/action list.

```sh
docker run --rm --user "$(id -u)" --workdir /recipes \
  --mount "type=bind,source=$(pwd),destination=/recipes" \
  --security-opt label=disable \
  ghcr.io/go-debos/debos:latest \
  --dry-run --print-recipe \
  -t overlays:arduino-unoq-releases,qsc-deb-releases \
  -t xfcedesktop:true \
  -t kernelpackage:linux-image-6.19.0-unoq \
  debos-recipes/qualcomm-linux-debian-rootfs.yaml
```

A clean render ends with `==== Recipe done (Dry run) ====`.

### Known non-standard action

`debos-recipes/qualcomm-linux-debian-image-arduino.yaml` uses the action
`image-standalone-partitions`, which is **not** in upstream debos. Stock/latest
debos renders it as `unknown action: image-standalone-partitions`. This is
expected: Arduino CI builds a debos fork
(`github.com/facchinm/debos.git`, branch `action-standalone-partitions`) to get
it. Don't "fix" the recipe — either build that debos fork, or validate the other
recipes and treat this one as render-blocked on stock debos.

## 3. Full builds (Makefile — preferred for local dev)

```sh
make rootfs.tar          # base rootfs -> rootfs.tar (+ dtbs.tar.gz)
make disk-ufs.img        # UFS disk image (4096-byte sectors) from rootfs.tar
make disk-sdcard.img     # SD/eMMC image (512-byte sectors)
make flash               # flashable assets (needs dtbs.tar.gz)
make test                # builds disk-ufs.img, then py.test-3 (needs qemu)
make clean               # rm images/tars ; make clean-debos removes .debos-*
```

Pass template vars through `EXTRA_DEBOS_OPTS`, e.g. a locally built kernel:

```sh
make rootfs.tar EXTRA_DEBOS_OPTS="-t localdebs:local-debs/ -t kernelpackage:none"
```

Resource defaults live in `DEBOS_OPTS` (`--memory 1GiB --scratchsize 6GiB`);
override for large images with `make DEBOS_OPTS=...` or bump `--scratchsize`.

## 4. Reproducing the Arduino CI build locally

`.github/workflows/build-tester-images.yaml` runs three debos steps in order.
Reproduce with the raw container command (section 1), same args:

```sh
# 1) rootfs
debos --scratchsize 8GiB \
  -t overlays:arduino-unoq-releases,qsc-deb-releases \
  -t xfcedesktop:true \
  -t aptlocalrepo:$PWD/local-apt-repo \
  -t kernelpackage:<pkg-from-precompiled-deb> \
  -t buildid:<id> -t includecontainers:<bool> \
  --print-recipe debos-recipes/qualcomm-linux-debian-rootfs.yaml

# 2) arduino-extra overlays
debos -t imagetype:sdcard --scratchsize 8GiB \
  -t aptlocalrepo:$PWD/local-apt-repo -t includecontainers:true \
  --print-recipe debos-recipes/qualcomm-linux-debian-rootfs-arduino-extra.yaml

# 3) arduino image (needs the facchinm debos fork — see section 2)
debos -t imagetype:sdcard --scratchsize 8GiB \
  -t rootsize:<n> -t homesize:<n> \
  --print-recipe debos-recipes/qualcomm-linux-debian-image-arduino.yaml
```

The base (non-Arduino) CI path lives in `.github/workflows/debos.yml` and uses
the plural `-t kernelpackages:<comma-list>` (the singular `kernelpackage` is
deprecated but still honored with a warning).

## 5. Static checks (match CI exactly)

CI (`.github/workflows/static-checks.yml`) runs, via `scripts/functions`
`scan_files <mime> <linter>`:

- shellcheck on shell scripts, **with** `export SHELLCHECK_OPTS="-e SC2086,SC3043"`
- flake8 and pylint `--errors-only` on Python

Locally these tools are often absent; run them via containers so results match:

```sh
# shellcheck a script exactly like CI
docker run --rm --user "$(id -u)" \
  --mount "type=bind,source=$(pwd),destination=/work" -w /work \
  koalaman/shellcheck:stable -e SC2086,SC3043 path/to/script
```

Overlay files under `debos-recipes/overlays/*/` keep their git mode, so
executable dispatcher/hook scripts must be committed `0755` (`git ls-files -s`
should show `100755`). NetworkManager conf.d files are ini/keyfile — validate
with `python3 -c "import configparser,...; c.read(f)"`.

## 6. QEMU boot test

`scripts/run-qemu.py` boots a built image (auto sector size, CoW overlay,
`--headless`). `ci/qemu_test.py` (run by `make test`) drives the serial console
with pexpect. Both need `qemu-system-aarch64` — if it's missing locally, say so
and defer the boot test to CI rather than faking a pass.

## 7. Fanning out across subagents (right-sized models)

These builds are slow and independent, so parallelize — but match model size to
task difficulty. Default to the **smallest** model that can do the step;
escalate only for genuine debugging/judgement.

- **haiku** (cheap, use by default for): rendering recipes with
  `--dry-run --print-recipe` and reporting pass/fail; running a single
  shellcheck/flake8/pylint invocation; grepping recipes for a var/action;
  collecting `git`/toolchain facts; summarizing a build log's tail.
- **sonnet** (mid): diagnosing a *template render* failure, cross-referencing a
  recipe against the CI workflow, reconciling a rebase against upstream recipe
  changes.
- **opus** (reserve for): multi-recipe failures with unclear root cause,
  designing a recipe/overlay change, anything needing repo-wide judgement.

Parallelize independent work in **one message with multiple Agent calls**, e.g.
one haiku agent per recipe to `--dry-run --print-recipe` and report only
`RECIPE: PASS|FAIL + last error line`. Fan out lint the same way: one small
agent per linter. Then, if any come back FAIL, escalate just those to a
mid/large agent with the captured error.

Give each agent a **narrow, verifiable** instruction and ask for a terse
structured result (not a file dump). Never run a full multi-minute `make` build
inside a subagent you're blocking on unless the user asked for the built
artifact — prefer renders/lints for validation.

## Recipes at a glance

- `qualcomm-linux-debian-rootfs.yaml` — base rootfs -> `rootfs.tar` (+dtbs).
- `qualcomm-linux-debian-image.yaml` — disk image from rootfs; `-t imagetype:ufs|sdcard`.
- `qualcomm-linux-debian-flash.yaml` — flashable assets; `-t target_boards:...`.
- `qualcomm-linux-debian-rootfs-arduino-extra.yaml` — Arduino APT repo, UNO Q metapackage, libs.
- `qualcomm-linux-debian-image-arduino.yaml` — Arduino image (needs facchinm debos fork).
