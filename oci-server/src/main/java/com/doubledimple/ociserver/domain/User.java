package com.doubledimple.ociserver.domain;

import lombok.Data;

/**
 * @author doubleDimple
 * @date 2024:09:22日 11:58
 */
@Data
public class User {
    private String userId;
    private String userName;
    private String fingerprint;
    private String tenancy;
    private String region;
    private String keyFile;
    private float ocpus = 1F;
    private float memory = 1F;
    private Long disk = 50L;
    private String architecture;
    private int interval;
    private String rootPassword;
    private String operationSystem = "Ubuntu";

}
