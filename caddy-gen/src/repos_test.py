from repos import *
from build_blocks import *


def test_file_server_repo():
    repo = FileServerRepo("centos", "/srv/disk1/centos")
    node = Node(
        "handle /centos/*",
        [
            Node(
                "file_server browse",
                [Node("root /srv/disk1", []), Node("hide .*", [])],
            ),
            *hidden(),
        ],
    )
    assert str(Node("", repo.as_repo())) == str(Node("", [node]))


def test_file_server_subdomain():
    repo = FileServerRepo("centos", "/srv/disk1/centos")
    node = Node(
        "file_server /* browse",
        [Node("root /srv/disk1/centos", []), Node("hide .*", [])],
    )
    assert str(Node("", repo.as_subdomain())) == str(
        Node("", gzip("/*") + log() + [node] + hidden())
    )


def test_handler_order_preserves_security_and_encoded_byte_accounting():
    assert handler_order() == [
        Node("order cerberus before redir"),
        Node("order bandwidth_quota before cerberus"),
        Node("order waf before bandwidth_quota"),
    ]


def test_bandwidth_quota_paths_cover_only_direct_serving():
    assert bandwidth_quota_path(FileServerRepo("centos", "/srv/centos")) == "/centos/*"
    assert (
        bandwidth_quota_path(ProxyRepo("git/linux.git", "git-backend"))
        == "/git/linux.git/*"
    )
    assert bandwidth_quota_path(RedirRepo("fedora", "https://example.test")) is None


def test_bandwidth_quota_policy():
    assert bandwidth_quota_policy(["/centos/*", "/git/linux.git/*"]) == [
        Node(
            "@bandwidth_quota_download",
            [Node("method GET"), Node("path /centos/* /git/linux.git/*")],
        ),
        Node(
            "bandwidth_quota @bandwidth_quota_download",
            [
                Node("state_path {$CADDY_BANDWIDTH_QUOTA_DB:/data/bandwidth-quota.db}"),
                Node(
                    "whitelist_file "
                    "{$CADDY_BANDWIDTH_QUOTA_WHITELIST_FILE:"
                    "caddy/waf/blacklist/bandwidth-quota-whitelist.txt}"
                ),
                Node("ipv4_prefix 24"),
                Node("ipv6_prefix 64"),
                Node("window 5h 30GiB"),
                Node("window 168h 150GiB"),
                Node("window 720h 500GiB"),
            ],
        ),
    ]


def test_waf_policy():
    waf_dir = "{$CADDY_WAF_DIR:caddy/waf}"
    ip_blacklist_file = (
        "{$CADDY_WAF_IP_BLACKLIST_FILE:caddy/waf/blacklist/crawler-ip-blacklist.txt}"
    )
    ip_whitelist_file = (
        "{$CADDY_WAF_IP_WHITELIST_FILE:"
        "caddy/waf/blacklist/bandwidth-quota-whitelist.txt}"
    )
    dns_blacklist_file = (
        "{$CADDY_WAF_DNS_BLACKLIST_FILE:caddy/waf/blacklist/dns-blacklist.txt}"
    )
    assert waf_policy() == [
        Node(
            "waf",
            [
                Node(f"rule_file {waf_dir}/general-policy.json"),
                Node(f"rule_file {waf_dir}/crawler-policy.json"),
                Node(f"ip_blacklist_file {ip_blacklist_file}"),
                Node(f"ip_whitelist_file {ip_whitelist_file}"),
                Node(f"dns_blacklist_file {dns_blacklist_file}"),
                Node("anomaly_threshold 10"),
                Node("max_request_body_size 1048576"),
                Node("log_severity info"),
                Node("log_json"),
                Node("log_path {$CADDY_WAF_LOG_PATH:/var/log/caddy/mirrorz/waf.log}"),
                Node("redact_sensitive_data"),
            ],
        )
    ]
