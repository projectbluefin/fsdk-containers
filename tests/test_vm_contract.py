"""Static contract tests for the bootable donate-clanker VM guest."""
from pathlib import Path


ROOT = Path(__file__).parents[1]
CONFIG = ROOT / "elements/podman-vm/donate-clanker-vm-config.bst"
SOURCE = ROOT / "elements/podman-vm/files/donate-clanker-worker.source"
EFI = ROOT / "elements/podman-vm/podman-vm-efi.bst"
BOOTSTRAP = ROOT / "elements/podman-vm/files/donate-clanker-bootstrap.py"


def test_guest_packages_current_worker_and_runtime_config():
    config = CONFIG.read_text()
    source = SOURCE.read_text()

    assert "ref: 5155b0bbdba0262b0ed1d948acf8d2e26b8205ce" in config
    assert "commit=5155b0bbdba0262b0ed1d948acf8d2e26b8205ce" in source
    assert "donate-clanker/image/config/goose.yaml" in config
    assert "donate-clanker/image/config/local-agent-policy.md" in config


def test_loader_root_uuid_is_rewritten_from_prepare_image_output():
    efi = EFI.read_text()

    assert 'prepare-image.sh \\' in efi
    assert 'sed -E -i \\' in efi
    assert 'root=UUID=${uuid_root}' in efi
    assert 'extraargs = "-U ${uuid_root}' in efi


def test_bootstrap_uses_non_seekable_binary_channel():
    bootstrap = BOOTSTRAP.read_text()

    assert "os.O_RDWR | os.O_CLOEXEC" in bootstrap
    assert 'os.fdopen(fd, "r+b", buffering=0)' in bootstrap
    assert 'channel.readline(65536)' in bootstrap
    assert 'channel.write(' in bootstrap
