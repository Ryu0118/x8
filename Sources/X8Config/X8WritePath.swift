/// How this invocation writes the cache.
///
/// There is deliberately no public-URL case: anonymous writes would let anyone
/// poison the cache.
package enum X8WritePath: Equatable, Sendable {
    /// Signed PutObject through the configuration's `api`.
    case api

    /// Writes are rejected before any I/O.
    case none
}
