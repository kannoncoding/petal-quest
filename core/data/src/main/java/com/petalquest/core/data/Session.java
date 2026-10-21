package com.petalquest.core.data;

import java.net.URI;

/** Secrets intentionally have no toString implementation. Never log this object. */
public final class Session {
    public final String userId;
    public final String endpointId;
    public final String token;
    public final String refreshToken;
    public final long expiresAtEpochSeconds;
    final String generation;

    public Session(String userId, String endpointId, String token, String refreshToken, long expiresAtEpochSeconds) {
        this(userId, endpointId, token, refreshToken, expiresAtEpochSeconds, java.util.UUID.randomUUID().toString());
    }

    Session(String userId, String endpointId, String token, String refreshToken, long expiresAtEpochSeconds, String generation) {
        this.userId = required(userId, "userId");
        this.endpointId = normalizeEndpoint(endpointId);
        this.token = required(token, "token");
        this.refreshToken = required(refreshToken, "refreshToken");
        if (expiresAtEpochSeconds <= 0) throw new IllegalArgumentException("Invalid session expiration");
        this.expiresAtEpochSeconds = expiresAtEpochSeconds;
        this.generation = required(generation, "session generation");
    }

    public boolean isExpired() { return System.currentTimeMillis() / 1000 >= expiresAtEpochSeconds; }
    public String getGeneration() { return generation; }

    static String required(String value, String label) {
        if (value == null || value.trim().isEmpty()) throw new IllegalArgumentException(label + " is required");
        return value;
    }

    public static String normalizeEndpoint(String value) {
        try {
            URI uri = new URI(required(value, "endpointId")).normalize();
            if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null ||
                uri.getUserInfo() != null || uri.getQuery() != null || uri.getFragment() != null)
                throw new IllegalArgumentException("Endpoint must be an HTTPS service URL");
            String path = uri.getPath() == null ? "" : uri.getPath().replaceAll("/+$", "");
            return new URI("https", null, uri.getHost().toLowerCase(java.util.Locale.ROOT),
                uri.getPort() == 443 ? -1 : uri.getPort(), path, null, null).toString();
        } catch (java.net.URISyntaxException e) { throw new IllegalArgumentException("Invalid service URL", e); }
    }
}
