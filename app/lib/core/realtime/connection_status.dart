/// Lifecycle of a single WebSocket session.
/// - `connecting`: initial dial in progress (no successful handshake yet).
/// - `connected`: handshake complete; frames can flow in both directions.
/// - `reconnecting`: previous session ended (server close, network drop)
///   and we are waiting on a backoff timer before re-dialing.
/// - `offline`: terminal — only emitted after `disconnect()`.
enum ConnectionStatus { connecting, connected, reconnecting, offline }
