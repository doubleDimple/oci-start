package com.doubledimple.dao.entity;

import lombok.Getter;
import lombok.Setter;
import javax.persistence.*;

@Getter
@Setter
@Entity
@Table(name = "network_quality_task")
public class NetworkQualityTask {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Version
    private Long version;
    @Column(nullable = false, length = 80)
    private String name;
    @Column(name = "operator_name", nullable = false, length = 16)
    private String operator;
    @Column(nullable = false, length = 80)
    private String region;
    @Column(name = "probe_type", nullable = false, length = 8)
    private String type;
    @Column(nullable = false, length = 2048)
    private String target;
    @Column(nullable = false)
    private Integer intervalSeconds;
    @Column(nullable = false)
    private Integer sampleCount;
    @Column(nullable = false)
    private Boolean enabled;
    @Column(nullable = false)
    private Long createdAt;
    @Column(nullable = false)
    private Long updatedAt;
}
