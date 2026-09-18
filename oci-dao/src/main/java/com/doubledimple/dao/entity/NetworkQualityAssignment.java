package com.doubledimple.dao.entity;

import lombok.Getter;
import lombok.Setter;
import javax.persistence.*;

@Getter
@Setter
@Entity
@Table(name = "network_quality_assignment", uniqueConstraints = @UniqueConstraint(name = "nq_task_instance", columnNames = {"task_id", "instance_id"}),
        indexes = {@Index(name = "nq_assignment_instance", columnList = "instance_id"), @Index(name = "nq_assignment_expiry", columnList = "lease_expires_at")})
public class NetworkQualityAssignment {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(name = "task_id", nullable = false)
    private Long taskId;
    @Column(name = "instance_id", nullable = false)
    private Long instanceId;
    @Column(nullable = false)
    private Long nextDue;
    @Column(nullable = false)
    private Boolean requested = false;
    @Column(length = 36)
    private String executionId;
    @Column(length = 36)
    private String credentialGeneration;
    private Long revision;
    @Column(name = "lease_expires_at")
    private Long leaseExpiresAt;
    private Long latestSampleId;
}
