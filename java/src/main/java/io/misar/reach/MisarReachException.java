package io.misar.reach;

/**
 * Thrown when the MisarReach API returns a non-2xx HTTP response, or when a
 * network-level error prevents the request from completing.
 *
 * <p>The API emits a standard error envelope
 * {@code { "error": { "code": "...", "message": "..." } }}; the extracted
 * message is exposed via {@link #getMessage()} and the HTTP status via
 * {@link #getStatus()}. For network errors the {@code status} is {@code 0}.
 */
public class MisarReachException extends Exception {

    private final int status;

    /**
     * @param status  HTTP status code (0 for network errors).
     * @param message Human-readable description.
     */
    public MisarReachException(int status, String message) {
        super("MisarReachException(" + status + "): " + message);
        this.status = status;
    }

    /**
     * @param status  HTTP status code (0 for network errors).
     * @param message Human-readable description.
     * @param cause   Underlying throwable.
     */
    public MisarReachException(int status, String message, Throwable cause) {
        super("MisarReachException(" + status + "): " + message, cause);
        this.status = status;
    }

    /**
     * Convenience constructor — wraps a non-HTTP exception (network errors).
     *
     * @param message Human-readable description.
     * @param cause   Underlying throwable.
     */
    public MisarReachException(String message, Throwable cause) {
        super("MisarReachException(0): " + message, cause);
        this.status = 0;
    }

    /** HTTP status code returned by the server, or {@code 0} for network errors. */
    public int getStatus() {
        return status;
    }
}
