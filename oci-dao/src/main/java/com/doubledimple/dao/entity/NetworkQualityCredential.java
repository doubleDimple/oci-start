package com.doubledimple.dao.entity;

import lombok.Getter;
import lombok.Setter;
import javax.persistence.*;

/** No toString: even the hash must not be included in routine entity logging. */
@Getter
@Setter
@Entity
@Table(name = "network_quality_credential", indexes = {
        @Index(name = "nq_credential_hash", columnList = "token_hash", unique = true),
        @Index(name = "nq_credential_pending", columnList = "pending_hash", unique = true)})
public class NetworkQualityCredential {
    @Id
    private Long instanceId;
    @Column(name = "token_hash", length = 64)
    private String tokenHash;
    @Column(name = "pending_hash", length = 64)
    private String pendingHash;
    @Column(length = 36)
    private String pendingGeneration;
    private Long pendingExpiresAt;
    @Column(nullable = false, length = 36)
    private String generation;
    private Long lastSeen;
    @Column(length = 16)
    private String agentVersion;
    @Column(length = 64)
    private String capabilities;
}
