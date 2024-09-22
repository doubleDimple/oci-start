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
    private int ocpus;
    private int memory;
    private int disk;
    private String architecture;
    private int interval;
    private String rootPassword;

}
