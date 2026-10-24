package com.doubledimple.dao.entity;

import lombok.Getter;
import lombok.Setter;
import javax.persistence.*;

@Getter
@Setter
@Entity
@Table(name = "network_quality_sample", indexes = {
        @Index(name = "nq_sample_window", columnList = "instance_id,task_id,updated_at"),
        @Index(name = "nq_sample_expiry", columnList = "updated_at")},
        uniqueConstraints = @UniqueConstraint(name = "nq_sample_execution", columnNames = "execution_id"))
public class NetworkQualitySample {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(name = "instance_id", nullable = false)
    private Long instanceId;
    @Column(name = "task_id", nullable = false)
    private Long taskId;
    @Column(nullable = false)
    private Long revision;
    @Column(name = "execution_id", nullable = false, length = 36)
    private String executionId;
    @Column(name = "updated_at", nullable = false)
    private Long updatedAt;
    @Column(nullable = false, length = 16)
    private String status;
    private Integer attempts;
    private Integer successful;
    private Double avgMs;
    private Double minMs;
    private Double maxMs;
    @Column(length = 32)
    private String errorCode;
    private Integer httpStatus;
}
