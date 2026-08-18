package io.misar.reach;

/**
 * Thrown when a counted plan cap is hit.
 *
 * <p>MisarReach answers 402 with {@code upgrade: true} when a cap is reached —
 * searches, results, autopilot runs, deals, seats, channels — and names the
 * offending counter. Retrying cannot help until the cap resets or the plan
 * changes.
 *
 * <p>Distinct from the 503 {@code retry: true} the server sends when it could
 * not <em>check</em> the quota: that one is retried, so "we do not know" is
 * never mistaken for "you are over your limit".
 */
public class UpgradeRequiredException extends MisarReachException {

    private final String feature;
    private final Integer limit;
    private final Integer current;
    private final String upgradeUrl;

    public UpgradeRequiredException(
            int status, String message, String feature, Integer limit, Integer current, String upgradeUrl) {
        super(status, message);
        this.feature = feature;
        this.limit = limit;
        this.current = current;
        this.upgradeUrl = upgradeUrl;
    }

    /** The counter that was exhausted, e.g. {@code lead_searches}. */
    public String getFeature() {
        return feature;
    }

    /** The cap on the current plan. */
    public Integer getLimit() {
        return limit;
    }

    /** Usage against that cap when the call was refused. */
    public Integer getCurrent() {
        return current;
    }

    /** Absolute URL to the billing page. */
    public String getUpgradeUrl() {
        return upgradeUrl;
    }
}
