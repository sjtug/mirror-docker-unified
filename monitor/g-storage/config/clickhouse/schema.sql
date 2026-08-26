CREATE DATABASE IF NOT EXISTS hotspot;

CREATE TABLE IF NOT EXISTS hotspot.requests_raw
(
    event_time DateTime64(3, 'UTC') CODEC(DoubleDelta, ZSTD(3)),
    event_id FixedString(64),
    org LowCardinality(String),
    server LowCardinality(String),
    http_host LowCardinality(String),
    repo LowCardinality(String),
    path String,
    request_method LowCardinality(String),
    status UInt16,
    status_class LowCardinality(String),
    body_bytes_sent UInt64,
    request_time Float32,
    upstream_response_time Float32,
    content_type LowCardinality(String),
    proxied UInt8,
    range_requested UInt8,
    client_key FixedString(64),
    referer_host LowCardinality(String),
    ua_browser LowCardinality(String),
    ua_os LowCardinality(String),
    ua_device_type LowCardinality(String),
    client_country_code LowCardinality(String),
    client_region LowCardinality(String),
    client_asn UInt32,
    is_bot UInt8,
    request_id String
)
ENGINE = MergeTree
PARTITION BY toDate(event_time)
ORDER BY (org, server, repo, event_time)
TTL toDateTime(event_time) + INTERVAL 14 DAY DELETE
SETTINGS index_granularity = 8192,
         ttl_only_drop_parts = 1,
         default_compression_codec = 'ZSTD(3)';

CREATE TABLE IF NOT EXISTS hotspot.repo_5m_state
(
    bucket DateTime('UTC') CODEC(DoubleDelta, ZSTD(3)),
    org LowCardinality(String),
    server LowCardinality(String),
    http_host LowCardinality(String),
    repo LowCardinality(String),
    status_class LowCardinality(String),
    request_method LowCardinality(String),
    requests AggregateFunction(count),
    bytes AggregateFunction(sum, UInt64),
    unique_clients AggregateFunction(uniqCombined64, FixedString(64)),
    request_time_quantiles AggregateFunction(quantilesTDigest(0.50, 0.95, 0.99), Float32),
    upstream_time_quantiles AggregateFunction(quantilesTDigest(0.50, 0.95, 0.99), Float32),
    range_requests AggregateFunction(sum, UInt64),
    bot_requests AggregateFunction(sum, UInt64)
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(bucket)
ORDER BY (org, server, bucket, repo, http_host, status_class, request_method)
TTL bucket + INTERVAL 365 DAY DELETE
SETTINGS default_compression_codec = 'ZSTD(3)';

CREATE MATERIALIZED VIEW IF NOT EXISTS hotspot.repo_5m_mv
TO hotspot.repo_5m_state
AS SELECT
    toDateTime(toStartOfInterval(event_time, INTERVAL 5 MINUTE), 'UTC') AS bucket,
    org,
    server,
    http_host,
    repo,
    status_class,
    request_method,
    countState() AS requests,
    sumState(body_bytes_sent) AS bytes,
    uniqCombined64State(client_key) AS unique_clients,
    quantilesTDigestState(0.50, 0.95, 0.99)(request_time) AS request_time_quantiles,
    quantilesTDigestState(0.50, 0.95, 0.99)(upstream_response_time) AS upstream_time_quantiles,
    sumState(toUInt64(range_requested)) AS range_requests,
    sumState(toUInt64(is_bot)) AS bot_requests
FROM hotspot.requests_raw
GROUP BY bucket, org, server, http_host, repo, status_class, request_method;

CREATE OR REPLACE VIEW hotspot.repo_5m AS
SELECT
    bucket,
    org,
    server,
    http_host,
    repo,
    status_class,
    request_method,
    countMerge(requests) AS requests,
    sumMerge(bytes) AS bytes,
    uniqCombined64Merge(unique_clients) AS unique_clients,
    quantilesTDigestMerge(0.50, 0.95, 0.99)(request_time_quantiles)[1] AS request_time_p50,
    quantilesTDigestMerge(0.50, 0.95, 0.99)(request_time_quantiles)[2] AS request_time_p95,
    quantilesTDigestMerge(0.50, 0.95, 0.99)(request_time_quantiles)[3] AS request_time_p99,
    quantilesTDigestMerge(0.50, 0.95, 0.99)(upstream_time_quantiles)[2] AS upstream_time_p95,
    sumMerge(range_requests) AS range_requests,
    sumMerge(bot_requests) AS bot_requests
FROM hotspot.repo_5m_state
GROUP BY bucket, org, server, http_host, repo, status_class, request_method;

CREATE OR REPLACE VIEW hotspot.repo_5m_totals AS
SELECT
    bucket,
    org,
    server,
    http_host,
    repo,
    countMerge(requests) AS requests,
    sumMerge(bytes) AS bytes,
    uniqCombined64Merge(unique_clients) AS unique_clients,
    quantilesTDigestMerge(0.50, 0.95, 0.99)(request_time_quantiles)[1] AS request_time_p50,
    quantilesTDigestMerge(0.50, 0.95, 0.99)(request_time_quantiles)[2] AS request_time_p95,
    quantilesTDigestMerge(0.50, 0.95, 0.99)(request_time_quantiles)[3] AS request_time_p99,
    quantilesTDigestMerge(0.50, 0.95, 0.99)(upstream_time_quantiles)[2] AS upstream_time_p95,
    sumMerge(range_requests) AS range_requests,
    sumMerge(bot_requests) AS bot_requests
FROM hotspot.repo_5m_state
GROUP BY bucket, org, server, http_host, repo;

CREATE TABLE IF NOT EXISTS hotspot.object_1h_state
(
    bucket DateTime('UTC') CODEC(DoubleDelta, ZSTD(3)),
    org LowCardinality(String),
    server LowCardinality(String),
    repo LowCardinality(String),
    path String,
    status_class LowCardinality(String),
    requests AggregateFunction(count),
    bytes AggregateFunction(sum, UInt64),
    unique_clients AggregateFunction(uniqCombined64, FixedString(64)),
    range_requests AggregateFunction(sum, UInt64)
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(bucket)
ORDER BY (org, server, bucket, repo, path, status_class)
TTL bucket + INTERVAL 90 DAY DELETE
SETTINGS default_compression_codec = 'ZSTD(3)';

CREATE MATERIALIZED VIEW IF NOT EXISTS hotspot.object_1h_mv
TO hotspot.object_1h_state
AS SELECT
    toDateTime(toStartOfHour(event_time), 'UTC') AS bucket,
    org,
    server,
    repo,
    path,
    status_class,
    countState() AS requests,
    sumState(body_bytes_sent) AS bytes,
    uniqCombined64State(client_key) AS unique_clients,
    sumState(toUInt64(range_requested)) AS range_requests
FROM hotspot.requests_raw
GROUP BY bucket, org, server, repo, path, status_class;

CREATE OR REPLACE VIEW hotspot.object_1h AS
SELECT
    bucket,
    org,
    server,
    repo,
    path,
    status_class,
    countMerge(requests) AS requests,
    sumMerge(bytes) AS bytes,
    uniqCombined64Merge(unique_clients) AS unique_clients,
    sumMerge(range_requests) AS range_requests
FROM hotspot.object_1h_state
GROUP BY bucket, org, server, repo, path, status_class;

CREATE OR REPLACE VIEW hotspot.object_1h_totals AS
SELECT
    bucket,
    org,
    server,
    repo,
    path,
    countMerge(requests) AS requests,
    sumMerge(bytes) AS bytes,
    uniqCombined64Merge(unique_clients) AS unique_clients,
    sumMerge(range_requests) AS range_requests
FROM hotspot.object_1h_state
GROUP BY bucket, org, server, repo, path;
