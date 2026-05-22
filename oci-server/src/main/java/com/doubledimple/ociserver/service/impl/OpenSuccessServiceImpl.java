package com.doubledimple.ociserver.service.impl;

import cn.hutool.json.JSONUtil;
import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import com.doubledimple.dao.entity.BootInstance;
import com.doubledimple.dao.entity.RegisterDetail;
import com.doubledimple.dao.entity.SystemConfig;
import com.doubledimple.dao.repository.BootInstanceRepository;
import com.doubledimple.dao.repository.RegisterDetailRepository;
import com.doubledimple.dao.repository.SystemConfigRepository;
import com.doubledimple.ocicommon.enums.oci.AccountTypeSubEnum;
import com.doubledimple.ocicommon.enums.oci.PlanTypeSubEnum;
import com.doubledimple.ocicommon.param.OpenInstanceNotify;
import com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.service.BootTotalInstanceService;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.service.InstanceDetailsService;
import com.doubledimple.ociserver.service.OpenApiService;
import com.doubledimple.ociserver.service.OpenSuccessService;
import com.doubledimple.ociserver.utils.oracle.OciObjectStorageUtil;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.ospgateway.model.Subscription;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.context.ApplicationContext;
import org.springframework.context.annotation.Lazy;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import java.util.Collections;
import java.util.Optional;

import static com.doubledimple.ociserver.utils.oracle.OciObjectStorageUtil.BUCKET_NAME;

/**
 * @version 1.0.0
 * @ClassName OpenSuccessServiceImpl
 * @Description
 * @Author doubleDimple
 * @Date 2025-03-30 13:20
 */
@Service
@Slf4j
public class OpenSuccessServiceImpl implements OpenSuccessService {

    @Resource
    BootInstanceRepository bootInstanceRepository;

    @Resource
    BootTotalInstanceService bootTotalInstanceService;

    @Resource
    MessageFactory messageFactory;

    @Resource
    OpenApiService openApiService;

    @Resource
    InstanceDetailsService instanceDetailsService;

    @Resource
    @Lazy
    private SystemConfigRepository systemConfigRepository;

    @Resource
    RegisterDetailRepository registerDetailRepository;

    @Resource
    ApplicationContext applicationContext;

    @Override
    public void doSuccess(User user, OracleInstanceDetail instanceData, SimpleAuthenticationDetailsProvider provider) {
        Long tenantId = null;
        instanceData.setUserName(user.getUserName());
        OpenSuccessServiceImpl self = applicationContext.getBean(OpenSuccessServiceImpl.class);

        // 1) 轻量 DB 更新（事务内只做 DB 写，不再夹带 OCI API 调用，避免事务长时间持有连接）
        BootInstance newBoot = null;
        try {
            newBoot = self.saveInstanceDbStats(user, instanceData);
        } catch (ObjectOptimisticLockingFailureException e) {
            log.warn("检测到并发更新冲突，记录已由其他任务处理，跳过本次更新: {}", user.getBootId());
        } catch (Exception e) {
            log.error("核心数据更新失败: {}", e.getMessage(), e);
        }

        // 2) 兜底：即使上面 DB 写失败，也要通过 bootId 拿到 newBoot，保证通知不被遗漏
        if (newBoot == null) {
            try {
                newBoot = bootInstanceRepository.findById(user.getBootId()).orElse(null);
            } catch (Exception e) {
                log.error("兜底查询 BootInstance 失败: bootId={}, reason:{}", user.getBootId(), e.getMessage(), e);
            }
        }
        if (newBoot != null) {
            tenantId = newBoot.getTenantId();
        }

        // 3) OCI 元数据同步（独立失败，不影响通知发送）
        try {
            instanceData.setAddCount(newBoot != null ? newBoot.getAddCount() : 0);
            instanceDetailsService.doSyncInstance(user, instanceData, provider);
        } catch (Exception e) {
            log.error("doSyncInstance 同步实例详情失败: bootId={}, reason:{}", user.getBootId(), e.getMessage(), e);
        }

        // 4) 对象存储上传（独立失败，不影响通知发送）
        try {
            String jsonString = new JSONObject()
                    .fluentPut("instanceId", instanceData.getInstance().getId())
                    .fluentPut("initPublicIp", instanceData.getPublicIp())
                    .fluentPut("initUser", "root")
                    .fluentPut("initPassword", user.getRootPassword())
                    .toJSONString();
            OciObjectStorageUtil.uploadJsonStringForBucketName(null, provider, BUCKET_NAME, instanceData.getInstance().getId(), jsonString);
        } catch (Exception e) {
            log.error("对象存储上传失败: bootId={}, reason:{}", user.getBootId(), e.getMessage(), e);
        }

        // 5) 通知：与持久化解耦，只要拿到 newBoot 就走幂等去重 + TG 发送
        if (newBoot == null) {
            log.error("无法定位 BootInstance(bootId={})，跳过通知发送", user.getBootId());
            return;
        }

        int result;
        try {
            result = bootInstanceRepository.markNotificationAsSent(newBoot.getId());
        } catch (Exception e) {
            log.error("标记通知去重失败: bootId={}, reason:{}", newBoot.getId(), e.getMessage(), e);
            return;
        }
        if (result <= 0) {
            log.warn("任务 {} 的通知处理，本次跳过", newBoot.getId());
            return;
        }

        log.info("成功获取任务 {} 的通知，开始发送消息...", newBoot.getId());
        if (user.getHelpFlag() != 2) {
            try {
                messageFactory.getType(MessageEnum.TELEGRAM).sendMessage(instanceData);
            } catch (Exception e) {
                log.error("消息 发送失败: {}", e.getMessage());
            }
        }
        try {
            this.executeFinalNotify(user, instanceData, tenantId);
        } catch (Exception e) {
            log.error("通知 API 异常: {}", e.getMessage());
        }
    }

    @Transactional(rollbackFor = Exception.class)
    public BootInstance saveInstanceDbStats(User user, OracleInstanceDetail instanceData) {
        bootTotalInstanceService.updatePublicIp(user.getBootId(), 2, instanceData.getPublicIp());
        return bootInstanceRepository.findById(user.getBootId()).map(bootInstance -> {
            instanceData.setAddCount(bootInstance.getAddCount());
            return bootInstance;
        }).orElse(null);
    }

    private void executeFinalNotify(User user, OracleInstanceDetail instanceData, Long tenantId) {
        OpenInstanceNotify notify = new OpenInstanceNotify();
        notify.setRegion(user.getRegion());
        notify.setArchitecture(user.getArchitecture());
        notify.setCount(instanceData.getAddCount());
        String typeName = "未知";
        if (tenantId != null) {
            Optional<RegisterDetail> byTenantId = registerDetailRepository.findByTenantId(String.valueOf(tenantId));
            if (byTenantId.isPresent()){
                RegisterDetail registerDetail = byTenantId.get();
                Subscription.AccountType accountType = registerDetail.getAccountType();
                Subscription.PlanType planType = registerDetail.getPlanType();
                typeName = AccountTypeSubEnum.getByCode(accountType.getValue()) + PlanTypeSubEnum.getByCode(planType.getValue());
            }
        }
        notify.setAccountTypeName(typeName);
        String secret = systemConfigRepository.findByKey("task.notification.secret")
                .map(SystemConfig::getValue).orElse("");
        notify.setSecret(secret);
        openApiService.notify(notify);
    }

    @Override
    @Transactional(isolation = Isolation.READ_COMMITTED)
    public boolean ensureStatusUpdated(User user, OracleInstanceDetail instanceData) {
        try {
            int updatedRows = bootInstanceRepository.updateBootInstanceStatusAndIpIfNotEqual(
                    user.getBootId(), 2, instanceData.getPublicIp());
            if (updatedRows > 0) {
                log.debug("状态已更新 - BootId: {}", user.getBootId());
                return true;
            } else {
                log.debug("状态已是最新 - BootId: {}", user.getBootId());
                return false;
            }
        } catch (Exception e) {
            log.error("状态更新失败 - BootId: {}, 错误: {}",
                    user.getBootId(), e.getMessage(), e);
            return false;
        }
    }
}
