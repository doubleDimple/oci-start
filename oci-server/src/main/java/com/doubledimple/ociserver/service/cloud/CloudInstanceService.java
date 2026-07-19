package com.doubledimple.ociserver.service.cloud;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.CloudTypeEnum;

import java.util.List;

/**
 * 多云实例策略接口。
 * 新增云厂商：实现本接口 + Spring 注册，无需改 Factory / 同步主流程。
 */
public interface CloudInstanceService {

    CloudTypeEnum getCloudType();

    CloudCapability capability();

    /**
     * 拉取云端实例映射为中立 InstanceDetails（不落库）。
     */
    List<InstanceDetails> listRemote(Tenant tenant) throws Exception;

    /**
     * 同步到 instance_detail：upsert + merge 本地字段。
     */
    void syncToLocal(Tenant tenant);

    void start(InstanceDetails local, Tenant tenant) throws Exception;

    void stop(InstanceDetails local, Tenant tenant) throws Exception;

    void reboot(InstanceDetails local, Tenant tenant) throws Exception;

    void terminate(InstanceDetails local, Tenant tenant) throws Exception;

    /**
     * @return 新公网 IP，失败抛异常
     */
    String changePublicIp(InstanceDetails local, Tenant tenant) throws Exception;

    /**
     * 直接创建（不走 OCI 抢机循环）。不支持时 capability 声明后抛 UnsupportedOperationException。
     */
    void create(Tenant tenant, CreateInstanceCommand cmd) throws Exception;
}
