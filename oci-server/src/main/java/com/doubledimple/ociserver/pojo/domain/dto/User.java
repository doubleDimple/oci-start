package com.doubledimple.ociserver.pojo.domain.dto;

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
    /**
     * 循环间隔秒数
     */
    private int interval;
    /**
     * 任务是否正在运行
     */
    private Boolean isRunning;
    /**
     * 是否抢到机器
     */
    private Boolean isSuccess;
    private String rootPassword;
    private String operationSystem = "Ubuntu";
    //bootInstance 主键
    private Long bootId;
    private String uniqueStrId;

    /**
    * tenant表主键
    */
    private long id;

    /**
    * 默认不是救机,如果是救机,设置为2,不执行通知逻辑
    */
    private int helpFlag =1 ;

    /**
    * 0 表示需要备份,1 表示不需要备份
    */
    private int backUp;

    private String imageId;
    //系统名称
    private String operatingSystem;
    // 系统版本，如 20.04
    private String operatingSystemVersion;

    private String bootIdStr;

}
