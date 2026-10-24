package com.doubledimple.ocimonitor.service.quality;

/** One-use installation material. Deliberately has no generated toString. */
public final class AgentCredentialReceipt {
    private final String instanceId;
    private final String token;
    public AgentCredentialReceipt(String instanceId, String token) {
        this.instanceId = instanceId;
        this.token = token;
    }
    public String getInstanceId() { return instanceId; }
    public String getToken() { return token; }
}
