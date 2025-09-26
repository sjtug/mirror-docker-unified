from repos import *
from build_blocks import *


def test_file_server_repo():
    repo = FileServerRepo("centos", "/srv/disk1/centos")
    node = Node(
        "file_server /centos/* browse",
        [Node("root /srv/disk1", []), Node("hide .*", [])],
    )
    assert str(Node("", repo.as_repo())) == str(Node("", [node]))


def test_file_server_subdomain():
    repo = FileServerRepo("centos", "/srv/disk1/centos")
    node = Node(
        "file_server /* browse",
        [Node("root /srv/disk1/centos", []), Node("hide .*", [])],
    )
    assert str(Node("", repo.as_subdomain())) == str(
        Node("", gzip("/*") + log() + hidden() + [node])
    )
