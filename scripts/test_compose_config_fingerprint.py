import importlib.util
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("compose-config-fingerprint.py")
SPEC = importlib.util.spec_from_file_location("compose_config_fingerprint", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def test_fingerprint_changes_with_file_content(tmp_path: Path) -> None:
    config = tmp_path / "config.yaml"
    config.write_text("version: one\n")
    before = MODULE.fingerprint(tmp_path, ("config.yaml",), "siyuan")

    config.write_text("version: two\n")
    after = MODULE.fingerprint(tmp_path, ("config.yaml",), "siyuan")

    assert before != after


def test_secret_fingerprint_uses_metadata_without_reading_contents(
    tmp_path: Path,
) -> None:
    secrets = tmp_path / "secrets"
    secrets.mkdir()
    secret = secrets / "token"
    secret.write_text("not-readable")
    secret.chmod(0)

    digest = MODULE.fingerprint(tmp_path, ("secrets/token",), "siyuan")

    assert len(digest) == 64


def test_override_changes_only_the_affected_service(
    tmp_path: Path, monkeypatch
) -> None:
    (tmp_path / "config.siyuan.yaml").write_text("version: one\n")
    (tmp_path / "Caddyfile.siyuan").write_text("unchanged\n")
    monkeypatch.setattr(
        MODULE,
        "COMMON_INPUTS",
        {
            "lug": ("config.{site}.yaml",),
            "caddy": ("Caddyfile.{site}",),
        },
    )
    monkeypatch.setattr(MODULE, "SITE_INPUTS", {"siyuan": {}})

    before = MODULE.compose_override(tmp_path, "siyuan")
    (tmp_path / "config.siyuan.yaml").write_text("version: two\n")
    after = MODULE.compose_override(tmp_path, "siyuan")

    label = MODULE.LABEL
    assert (
        before["services"]["lug"]["labels"][label]
        != after["services"]["lug"]["labels"][label]
    )
    assert (
        before["services"]["caddy"]["labels"][label]
        == after["services"]["caddy"]["labels"][label]
    )


def test_fingerprint_is_stable_for_directory_creation_order(tmp_path: Path) -> None:
    config_dir = tmp_path / "config"
    config_dir.mkdir()
    (config_dir / "b").write_text("second")
    (config_dir / "a").write_text("first")

    first = MODULE.fingerprint(tmp_path, ("config",), "zhiyuan")
    second = MODULE.fingerprint(tmp_path, ("config",), "zhiyuan")

    assert first == second
