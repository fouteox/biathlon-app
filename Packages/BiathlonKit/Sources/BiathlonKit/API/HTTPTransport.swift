import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Sends a request for a client. Tests pass canned responses instead of the network.
public typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

extension URLSession {
    /// Sends the clients' requests over this session.
    public var transport: HTTPTransport {
        { request in try await self.data(for: request) }
    }
}
