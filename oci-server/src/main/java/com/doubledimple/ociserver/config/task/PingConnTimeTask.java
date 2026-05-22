package com.doubledimple.ociserver.config.task;

import cn.hutool.json.JSONUtil;
import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ocicommon.param.PingResult;
import com.doubledimple.ocicommon.utils.PingUtil;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.pojo.request.TenancyDetail;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.utils.oracle.OciClassLoader;
import com.oracle.bmc.identity.model.RegionSubscription;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.CollectionUtils;

import javax.annotation.Resource;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.stream.Collectors;

import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_VPS_OFFLINE_TEMPLATE;
import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_VPS_ONLINE_TEMPLATE;

/**
 * @version 1.0.0
 * 加载区域
 */
@Service
@Slf4j
public class PingConnTimeTask {

    @Resource
    private TenantRepository tenantRepository;

    @Resource
    private MessageFactory messageFactory;

    @Resource
    private OracleInstanceDetailRepository oracleInstanceDetailRepository;

    @Resource
    private ThreadPoolExecutor taskExecutor;


    //执行ping测试
    @Transactional
    public void pingConnTime() {
        List<InstanceDetails> byEnablePingAndCloudType = oracleInstanceDetailRepository.findByEnablePingAndCloudType(1, 1);
        doBatchPing(byEnablePingAndCloudType);
    }


    @Transactional
    public void batchPing() {
        List<InstanceDetails> byEnablePingAndCloudType = oracleInstanceDetailRepository.findByCloudType(1);
        doBatchPing(byEnablePingAndCloudType);
    }

    /*private void doBatchPing(List<InstanceDetails> byEnablePingAndCloudType) {
        if (!CollectionUtils.isEmpty(byEnablePingAndCloudType)){
            log.debug("开始执行ping测试...");
            for (InstanceDetails instanceDetails : byEnablePingAndCloudType) {
                PingResult pingResult = PingUtil.ping(instanceDetails.getPublicIps());
                int notifyType = instanceDetails.check(pingResult.isReachable());
                if (notifyType > 0 && instanceDetails.shouldSendNotification(notifyType)) {
                    if (notifyType == 1) {
                        sendRecoveryNotification(instanceDetails);
                        instanceDetails.markNotificationSent(1);
                    } else if (notifyType == 2) {
                        sendOfflineNotification(instanceDetails);
                        instanceDetails.markNotificationSent(2);
                    }
                }
                oracleInstanceDetailRepository.save(instanceDetails);
            }
        }
    }*/

    private void doBatchPing(List<InstanceDetails> byEnablePingAndCloudType) {
        if (CollectionUtils.isEmpty(byEnablePingAndCloudType)) {
            return;
        }

        log.debug("开始执行多线程 Ping 测试，任务数: {}", byEnablePingAndCloudType.size());

        // 1. 创建异步任务列表
        List<CompletableFuture<InstanceDetails>> futures = byEnablePingAndCloudType.stream()
                .map(instance -> CompletableFuture.supplyAsync(() -> {
                    try {
                        PingResult pingResult = PingUtil.ping(instance.getPublicIps());
                        int notifyType = instance.check(pingResult.isReachable());
                        if (notifyType > 0 && instance.shouldSendNotification(notifyType)) {
                            if (notifyType == 1) {
                                sendRecoveryNotification(instance);
                                instance.markNotificationSent(1);
                            } else if (notifyType == 2) {
                                sendOfflineNotification(instance);
                                instance.markNotificationSent(2);
                            }
                        }
                        return instance;
                    } catch (Exception e) {
                        log.error("实例 [{}] Ping 检测异常", instance.getDisplayName(), e);
                        return null;
                    }
                }, taskExecutor))
                .collect(Collectors.toList());
        CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();

        List<InstanceDetails> updatedList = futures.stream()
                .map(CompletableFuture::join)
                .filter(Objects::nonNull)
                .collect(Collectors.toList());

        if (!updatedList.isEmpty()) {
            oracleInstanceDetailRepository.saveAll(updatedList);
            log.debug("本轮 Ping 测试完成，批量更新数据库 {} 条记录", updatedList.size());
        }
    }

    private void sendOfflineNotification(InstanceDetails instanceDetails) {
        log.debug("发送离线通知...");
        Optional<Tenant> byId = tenantRepository.findById(instanceDetails.getTenantId());
        if (byId.isPresent()){
            Tenant tenant = byId.get();
            String nowTime = java.time.LocalDateTime.now()
                    .format(java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
            messageFactory.getType(MessageEnum.TELEGRAM)
                    .sendMessageTemplate(String.format(MESSAGE_VPS_OFFLINE_TEMPLATE,
                            tenant.getUserName(),
                            RegionEnum.getRegionCode(tenant.getRegion()),
                            instanceDetails.getPublicIps(),
                            instanceDetails.getDisplayName(),nowTime));

        }
    }

    private void sendRecoveryNotification(InstanceDetails instanceDetails) {
        log.info("发送恢复通知...");
        Optional<Tenant> byId = tenantRepository.findById(instanceDetails.getTenantId());
        if (byId.isPresent()){
            Tenant tenant = byId.get();
            messageFactory.getType(MessageEnum.TELEGRAM)
                    .sendMessageTemplate(String.format(MESSAGE_VPS_ONLINE_TEMPLATE,
                            tenant.getUserName(),
                            RegionEnum.getRegionCode(tenant.getRegion()),
                            instanceDetails.getPublicIps(),
                            instanceDetails.getDisplayName()));

        }
    }
}



