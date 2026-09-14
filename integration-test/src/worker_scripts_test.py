import os
import shutil
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).parents[2]
ANACONDA_SCRIPT = REPO_ROOT / "lug/worker-script/anaconda.sh"


def prepare_anaconda_scripts(tmp_path: Path, stub_body: str) -> tuple[Path, Path]:
    script_dir = tmp_path / "worker-script"
    script_dir.mkdir()
    anaconda = script_dir / "anaconda.sh"
    shutil.copy2(ANACONDA_SCRIPT, anaconda)

    mirror_clone = script_dir / "mirror-clone-v2.sh"
    mirror_clone.write_text(stub_body)
    mirror_clone.chmod(0o755)
    (script_dir / "conda.pkgs.yaml").touch()
    (script_dir / "conda.cloud.yaml").touch()
    return anaconda, tmp_path / "calls"


def run_anaconda(anaconda: Path, calls: Path) -> subprocess.CompletedProcess[str]:
    env = {
        **os.environ,
        "CALLS": str(calls),
        "LUG_anaconda_phase_retry": "2",
        "LUG_anaconda_phase_retry_interval": "0",
    }
    return subprocess.run(
        [str(anaconda), "--workers", "4"],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )


def test_anaconda_retries_only_the_failed_phase(tmp_path: Path) -> None:
    anaconda, calls = prepare_anaconda_scripts(
        tmp_path,
        """#!/usr/bin/env bash
set -euo pipefail
prefix=
while (($#)); do
  if [[ $1 == --s3-prefix ]]; then prefix=$2; shift 2; else shift; fi
done
printf '%s\n' "$prefix" >>"$CALLS"
if [[ $prefix == anaconda/cloud ]] && [[ $(grep -c '^anaconda/cloud$' "$CALLS") == 1 ]]; then
  exit 23
fi
""",
    )

    result = run_anaconda(anaconda, calls)

    assert result.returncode == 0, result.stderr
    assert calls.read_text().splitlines() == [
        "anaconda/pkgs",
        "anaconda/cloud",
        "anaconda/cloud",
    ]


def test_anaconda_stops_after_the_last_phase_attempt(tmp_path: Path) -> None:
    anaconda, calls = prepare_anaconda_scripts(
        tmp_path,
        """#!/usr/bin/env bash
set -euo pipefail
prefix=
while (($#)); do
  if [[ $1 == --s3-prefix ]]; then prefix=$2; shift 2; else shift; fi
done
printf '%s\n' "$prefix" >>"$CALLS"
exit 23
""",
    )

    result = run_anaconda(anaconda, calls)

    assert result.returncode == 23
    assert calls.read_text().splitlines() == ["anaconda/pkgs", "anaconda/pkgs"]
    assert "anaconda/cloud" not in calls.read_text()
