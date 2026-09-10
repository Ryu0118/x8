# Cache metrics

``X8CacheMetricsStore`` aggregates completed CAS and Action Cache operations
for one proxy lifetime. Reads distinguish hits, misses, provider errors, and
corrupt records; writes count successfully stored bytes separately from read
bytes. The store is actor-isolated so concurrent protocol requests update one
consistent snapshot.

``X8CacheMetricsSnapshotFile`` persists the aggregate when a proxy session
completes or is shut down. The standalone executable's diagnostic reader loads
that last completed snapshot; it does not inspect a running service or add a
second control protocol to the cache socket. Snapshot reads and writes are
asynchronous. Percentiles use a bounded latency sample window to keep a
long-lived service's memory usage predictable.

Metrics describe remote-cache traffic observed by X8. An Xcode build-system
decision such as “up to date” is not a cache hit unless the proxy also observed
the corresponding storage hit.
