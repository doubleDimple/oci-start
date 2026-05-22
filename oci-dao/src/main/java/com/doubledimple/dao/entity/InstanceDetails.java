package com.doubledimple.dao.entity;

import lombok.Data;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Table;
import java.util.Date;
import java.util.List;
import org.hibernate.annotations.CreationTimestamp;

/**
 * @author doubleDimple
 * @date 2024:11:03日 15:31
 */
@Data
@Entity
@Table(name = "instance_detail")
public class InstanceDetails {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private long tenantId;
    private String instanceId;
    private String displayName;
    private String shape;
    private String state;
    /**
    * CPU核心数
    */
    private Integer ocpus;
    /**
    * 内存大小(GB)
    */
    private Integer memoryInGBs;
    /**
    * 引导卷大小(GB)
    */
    private Long bootVolumeSizeInGBs;

    /**
    * 附加的数据卷
    */
    //private BlockVolume blockVolumes;
    // 网络信息
    private String publicIps;
    private String privateIps;
    // 其他信息
    private String availabilityDomain;
    private String compartmentId;
    private String bootVolumeId;
    //private Map<String, String> freeformTags;

    private String remark;

    private String bootVolumeName;

    /**
    * 引导卷VPU性能值
    */
    private String vpusPerGB;

    @Column(columnDefinition = "TEXT")
    private String ipv6Addresses;

    // 使用时转换
    // 存储：String.join(",", list)
    // 取出：Arrays.asList(vnicIds.split(","))
    @Column(columnDefinition = "TEXT")
    private String vnicIds;
    /**
    * ssh连接的用户名
    */
    @Column(name = "username")
    private String username = "";

    /**
     * ssh连接的端口
     */
    @Column(name = "port")
    private Integer port = 22;

    @Column(name = "password")
    private String password = "";

    /**
     * 架构类型全称
     */
    @Column(name = "processorDescription")
    private String processorDescription = "NONE";

    /**
     * 架构类型简称
     */
    private String architecture = "NONE";

    /**
     * 云厂商类型
     * @see com.doubledimple.ocicommon.enums.CloudTypeEnum
     */
    @Column(name = "cloud_type", columnDefinition = "INTEGER DEFAULT 1")
    private int cloudType = 1;


    /**
     * 系统是否备份
     * 0:未备份  1:已备份
     */
    @Column(name = "sys_image_backup", columnDefinition = "INTEGER DEFAULT 0")
    private int sysImageBackup = 0;

    //该实例延迟时间ms
    @Column(nullable = false, columnDefinition = "bigint default 0")
    private Long connTime = 0L;

    //开启ping检测标志0:关闭 1:开启
    @Column(nullable = false, columnDefinition = "INTEGER DEFAULT 0")
    private Integer enablePing = 0;

    //在线离线标志 0:离线 1:在线
    @Column(nullable = false, columnDefinition = "INTEGER DEFAULT 1")
    private Integer onLineEnable = 1;

    //上次测试状态 0:离线 1:在线
    //上次是离线,本次是在线,就是恢复
    //上次是在线,本次是离线,就是断线
    @Column(nullable = false, columnDefinition = "INTEGER DEFAULT 1")
    private Integer lastOnLineEnable = 1;

    //离线通知标志 0:未通知 1:已通知
    @Column(nullable = false, columnDefinition = "INTEGER DEFAULT 0")
    private Integer offlineNotify = 0;

    //恢复通知标志 0:未通知 1:已通知
    @Column(nullable = false, columnDefinition = "INTEGER DEFAULT 0")
    private Integer resumeNotify = 0;

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

    /**
     * 记录入库时间，自动填充，不可更新
     */
    @CreationTimestamp
    @Column(name = "create_time", updatable = false)
    private Date createTime;

    //0:不发送通知,1:发送恢复通知,2:发送离线通知,
    public int check(boolean pingResult) {
        // 根据ping结果确定当前在线状态
        int currentOnlineStatus = pingResult ? 1 : 0;

        int notifyType = 0;

        // 检查状态变化
        if (this.lastOnLineEnable == 0 && currentOnlineStatus == 1) {
            // 恢复：上次离线，本次在线
            notifyType = 1;
            this.offlineNotify = 0;  // 重置离线通知标志
            this.resumeNotify = 0;   // 准备发送恢复通知
        } else if (this.lastOnLineEnable == 1 && currentOnlineStatus == 0) {
            // 离线：上次在线，本次离线
            notifyType = 2;
            this.resumeNotify = 0;   // 重置恢复通知标志
            this.offlineNotify = 0;  // 准备发送离线通知
        }

        // 更新状态
        this.lastOnLineEnable = this.onLineEnable;  // 保存上次状态
        this.onLineEnable = currentOnlineStatus;    // 更新当前状态

        return notifyType;
    }

    /**
     * 标记通知已发送
     * @param notifyType 1:恢复通知 2:离线通知
     */
    public void markNotificationSent(int notifyType) {
        if (notifyType == 1) {
            this.resumeNotify = 1;
        } else if (notifyType == 2) {
            this.offlineNotify = 1;
        }
    }

    /**
     * 检查是否需要发送通知（避免重复通知）
     * @param notifyType 通知类型
     * @return true:需要发送 false:不需要发送
     */
    public boolean shouldSendNotification(int notifyType) {
        if (notifyType == 1) {
            return this.resumeNotify == 0; // 恢复通知未发送
        } else if (notifyType == 2) {
            return this.offlineNotify == 0; // 离线通知未发送
        }
        return false;
    }


}
