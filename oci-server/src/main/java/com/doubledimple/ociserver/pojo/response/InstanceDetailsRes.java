package com.doubledimple.ociserver.pojo.response;

import lombok.Data;

import javax.persistence.*;
import java.util.Date;

/**
 * @author doubleDimple
 * @date 2024:11:03日 15:31
 */
@Data
public class InstanceDetailsRes {

    private String id;
    private long tenantId;
    private String tenantIdStr;
    private String instanceId;
    private String displayName;
    private String shape;
    private String state;
    // CPU和内存信息
    private Integer ocpus;            // CPU核心数
    private Integer memoryInGBs;      // 内存大小(GB)
    // 存储信息
    private Long bootVolumeSizeInGBs; // 引导卷大小(GB)
    //private BlockVolume blockVolumes; // 附加的数据卷
    // 网络信息
    private String publicIps;
    private String privateIps;
    // 其他信息
    private String availabilityDomain;
    private String compartmentId;
    //private Map<String, String> freeformTags;
    //所属组户名
    private String userName;

    private String remark;

    private String bootVolumeName;

    private String bootVolumeId;

    private Date createTime;

    private String timeCreated;

    private String ipv6Addresses;

    private String tenancyName;

    private String vpusPerGB; // 引导卷VPU性能值

    private int cloudType = 1;

    /**
     * 架构类型全称
     */
    @Column(name = "processorDescription")
    private String processorDescription = "NONE";

    /**
     * 架构类型简称
     */
    private String architecture = "NONE";

    private String cpuAndMem = "/";

    private String regionName;

    private int sysImageBackup;

    //该实例延迟时间ms
    private long connTime = 0;

    //开启ping检测标志0:关闭 1:开启
    private int enablePing = 0;

    //在线离线标志 0:离线 1:在线
    private int onLineEnable = 1;

    //上次测试状态 0:离线 1:在线
    private int lastOnLineEnable = 1;

    //离线通知标志 0:未通知 1:已通知
    private int offlineNotify = 0;

    //恢复通知标志 0:未通知 1:已通知
    private int resumeNotify = 0;

    /**
     * 新增字段 1: 是否已安装监控探针
     * 默认 false
     */
    @Column(name = "monitor_installed")
    private Boolean monitorInstalled = false;

    /**
     * 新增字段 2: 最后一次上报心跳的时间
     * 用于判断机器是否离线
     */
    @Column(name = "last_heartbeat")
    private Date lastHeartbeat;

    @Transient
    private String regionCode;

    @Transient
    private String flagUrl;
}
