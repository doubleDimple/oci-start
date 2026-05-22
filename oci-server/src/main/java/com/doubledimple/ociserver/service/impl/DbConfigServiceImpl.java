package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.DbConfig;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.DbConfigRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ocicommon.template.MessageTemplate;
import com.doubledimple.ocicommon.utils.DateTimeUtils;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.DbConfigService;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.utils.oracle.db.OciDbUtils;
import com.oracle.bmc.mysql.model.DbSystem;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static com.doubledimple.ociserver.utils.oracle.db.OciDbUtils.bindPublicIpForMysql;
import static com.doubledimple.ociserver.utils.oracle.db.OciDbUtils.getDbSystemDetail;
import static com.doubledimple.ociserver.utils.oracle.db.OciDbUtils.terminateMysqlDbSystem;

/**
 * @version 1.0.0
 * @ClassName DbConfigServiceImpl
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-12-31 22:58
 */
@Service
@Slf4j
public class DbConfigServiceImpl implements DbConfigService {

    @Resource
    private DbConfigRepository dbConfigRepository;

    @Resource
    private TenantRepository tenantRepository;

    @Resource
    private MessageFactory messageFactory;

    @Resource(name = "delayedTaskExecutor")
    private ScheduledExecutorService scheduledExecutorService;


    @Override
    @Transactional
    public void save(DbConfig dbConfig) {
        dbConfig.setCreateAt(LocalDateTime.now());
        dbConfig.setUpdatedAt(LocalDateTime.now());
        dbConfigRepository.save(dbConfig);
    }


    @Override
    public ApiResponse findByTenantId(Long tenantId) {
        Tenant tenant = tenantRepository.findById(tenantId).get();
        List<DbConfig> dbConfigList = dbConfigRepository.findByTenantIdAndCloudTypeAndDbType(tenantId, tenant.getCloudType(), 1);
        return ApiResponse.success(dbConfigList);
    }

    @Override
    @Transactional
    public ApiResponse syncMysqlFromCloud(Long tenantId) {
        Optional<Tenant> tenantOptional = tenantRepository.findById(tenantId);
        if (!tenantOptional.isPresent()) {
            return ApiResponse.error("未找到对应的租户信息");
        }
        Tenant tenant = tenantOptional.get();
        try {
            List<DbConfig> dbConfigList = OciDbUtils.queryMysqlInstance(tenant);
            if (dbConfigList == null || dbConfigList.isEmpty()) {
                return ApiResponse.success("未检测到运行中的 MySQL 实例");
            }
            for (DbConfig cloudConfig : dbConfigList) {
                DbConfig existingConfig = dbConfigRepository.findByTenantIdAndDbIdAndCloudType(tenantId, cloudConfig.getDbId(),1);

                if (existingConfig != null) {
                    existingConfig.setDbName(cloudConfig.getDbName());
                    existingConfig.setDbPrivateUrl(cloudConfig.getDbPrivateUrl());
                    //existingConfig.setDbPublicUrl(cloudConfig.getDbPublicUrl());
                    existingConfig.setDbPort(cloudConfig.getDbPort());
                    existingConfig.setDbPassword(cloudConfig.getDbPassword());
                    existingConfig.setDbVersion(cloudConfig.getDbVersion());
                    existingConfig.setDataStorageSizeInGBs(cloudConfig.getDataStorageSizeInGBs());
                    existingConfig.setDatabaseMode(cloudConfig.getDatabaseMode());
                    existingConfig.setDisplayName(cloudConfig.getDisplayName());
                    existingConfig.setShapeName(cloudConfig.getShapeName());
                    existingConfig.setAvailabilityDomain(cloudConfig.getAvailabilityDomain());
                    existingConfig.setHighlyAvailable(cloudConfig.getHighlyAvailable());
                    existingConfig.setUpdatedAt(LocalDateTime.now());
                    existingConfig.setCreateAt(LocalDateTime.now());

                    dbConfigRepository.save(existingConfig);
                } else {
                    cloudConfig.setTenantId(tenantId);
                    cloudConfig.setCreateAt(LocalDateTime.now());
                    cloudConfig.setUpdatedAt(LocalDateTime.now());
                    cloudConfig.setCloudType(tenant.getCloudType());
                    cloudConfig.setDbType(1);
                    dbConfigRepository.save(cloudConfig);
                }
            }
            return ApiResponse.success("同步成功，共处理 " + dbConfigList.size() + " 个实例");
        } catch (Exception e) {
            log.error("同步 OCI MySQL 实例失败, tenantId: {}", tenantId, e);
            return ApiResponse.error("同步失败: " + e.getMessage());
        }
    }

    /**
    * @Description: syncSingleMysqlFromCloud
    * @Param: [java.lang.Long]
    * @return: com.doubledimple.ociserver.pojo.response.base.ApiResponse
    * @Author: doubleDimple
    * @Date: 1/1/26 9:34 AM
    */
    @Override
    @Transactional
    public ApiResponse syncSingleMysqlFromCloud(Long id) {
        Optional<DbConfig> dbConfigOptional = dbConfigRepository.findById(id);
        if (dbConfigOptional.isPresent()){
            DbConfig dbConfig = dbConfigOptional.get();
            Tenant tenant = tenantRepository.findById(dbConfig.getTenantId()).get();
            DbConfig dbSystemUpdate = getDbSystemDetail(tenant, dbConfig);
            dbSystemUpdate.setId(dbConfig.getId());
            dbSystemUpdate.setUpdatedAt(LocalDateTime.now());
            dbConfigRepository.save(dbSystemUpdate);
        }
        return ApiResponse.success();
    }

    @Override
    public ApiResponse bindPublicIp(Long id) {
        try {
            Optional<DbConfig> dbConfigOptional = dbConfigRepository.findById(id);
            if (dbConfigOptional.isPresent()){
                DbConfig dbConfig = dbConfigOptional.get();
                if (StringUtils.isNotBlank(dbConfig.getDbPublicUrl())){
                    return ApiResponse.success("该实例已绑定公网IP");
                }
                Long tenantId = dbConfig.getTenantId();
                Tenant tenant = tenantRepository.findById(tenantId).get();
                String publicIpForMysql = bindPublicIpForMysql(tenant, dbConfig);
                dbConfig.setDbPublicUrl(publicIpForMysql);
                dbConfigRepository.save(dbConfig);
            }
            return ApiResponse.success();
        } catch (Exception e) {
            log.error("bing public ip error, dbId: {} faile:{}", id, e.getMessage(),e);
            return ApiResponse.error("绑定公网IP失败");
        }
    }

    @Override
    @Transactional
    public ApiResponse createMysql(Long tenantId) {
        try {
            Optional<Tenant> tenantOptional = tenantRepository.findById(tenantId);
            if (tenantOptional.isPresent()){
                Tenant tenant = tenantOptional.get();
                DbConfig dbConfig = OciDbUtils.createMysql(tenant);
                if (dbConfig == null) {
                    return ApiResponse.error("创建mysql失败,请稍后再试");
                }
                dbConfig.setCreateAt(LocalDateTime.now());
                dbConfig.setUpdatedAt(LocalDateTime.now());
                dbConfigRepository.save(dbConfig);
                startAsyncMysqlPolling(tenant, dbConfig.getId());
            }
            return ApiResponse.success("实例创建正在执行中,请等待15-20分钟后,刷新页面查看结果");
        } catch (Exception e) {
            log.error("create mysql error, tenantId: {} fail:{}", tenantId, e.getMessage(),e);
            return ApiResponse.error("创建数据库失败");
        }
    }

    private void startAsyncMysqlPolling(Tenant tenant, Long configId) {
        AtomicInteger attempts = new AtomicInteger(0);
        AtomicReference<ScheduledFuture<?>> futureRef = new AtomicReference<>();
        Runnable pollTask = () -> {
            try {
                attempts.incrementAndGet();

                DbConfig dbConfig = dbConfigRepository.findById(configId).orElse(null);

                if (dbConfig == null || attempts.get() > 60) {
                    log.warn("MySQL 轮询任务由于超时或记录不存在而终止, ID: {}", configId);
                    cancelTask(futureRef.get());
                    return;
                }
                DbConfig dbSystemDetail = OciDbUtils.getDbSystemDetail(tenant, dbConfig);
                String currentState = dbSystemDetail.getDbStatus();

                log.debug("轮询 MySQL 状态 - 租户: {}, 当前状态: {}, 尝试次数: {}",
                        tenant.getTenancyName(), currentState, attempts.get());

                if (DbSystem.LifecycleState.Active.getValue().equalsIgnoreCase(currentState)) {
                    dbConfig.setDbStatus(DbSystem.LifecycleState.Active.getValue());
                    dbConfig.setDbPrivateUrl(dbSystemDetail.getDbPrivateUrl());
                    dbConfig.setDbPort(dbSystemDetail.getDbPort());
                    dbConfig.setUpdatedAt(LocalDateTime.now());

                    String publicIp = OciDbUtils.bindPublicIpForMysql(tenant, dbSystemDetail);
                    dbConfig.setDbPublicUrl(publicIp);

                    dbConfigRepository.save(dbConfig);
                    sendSuccessTelegramMessage(tenant, dbConfig);

                    log.debug("MySQL 实例已就绪，正在停止轮询任务。");
                    cancelTask(futureRef.get());
                    return;
                }

                if (DbSystem.LifecycleState.Failed.getValue().equalsIgnoreCase(currentState)) {
                    dbConfig.setDbStatus(DbSystem.LifecycleState.Failed.getValue());
                    dbConfigRepository.save(dbConfig);
                    log.error("MySQL 实例创建失败 (FAILED)，终止轮询。");
                    cancelTask(futureRef.get());
                }

            } catch (Exception e) {
                log.error("轮询任务运行中发生未知异常", e);
                cancelTask(futureRef.get());
            }
        };

        //
        ScheduledFuture<?> future = scheduledExecutorService.scheduleAtFixedRate(pollTask, 10, 30, TimeUnit.SECONDS);
        futureRef.set(future);
    }

    private void cancelTask(ScheduledFuture<?> future) {
        if (future != null && !future.isCancelled()) {
            future.cancel(false);
        }
    }

    private void sendSuccessTelegramMessage(Tenant tenant, DbConfig dbConfig) {
        String dbPublicUrl = dbConfig.getDbPublicUrl();
        //发送消息
        String mysqlSuccessMsg = String.format(MessageTemplate.MYSQL_CREATE_SUCCESS_TEMPLATE,
                DateTimeUtils.getCurrentDateTime(),
                tenant.getDefName(),
                dbConfig.getAvailabilityDomain(),
                dbConfig.getDbVersion(),
                dbConfig.getDbPrivateUrl(),
                (dbPublicUrl != null ? dbPublicUrl : "未开启"),
                dbConfig.getDbName(),
                dbConfig.getDbPassword(),
                dbConfig.getDbPort(),
                dbConfig.getDataStorageSizeInGBs()
        );
        messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplateText(mysqlSuccessMsg);
    }

    @Override
    @Transactional
    public ApiResponse handleMysqlAction(Map<String, Object> payload) {
        try {
            String action = (String) payload.get("action");
            String id = (String)payload.get("id");
            Long dbConfigId = Long.valueOf(id);
            Optional<DbConfig> dbConfigOptional = dbConfigRepository.findById(dbConfigId);
            DbConfig dbConfig = dbConfigOptional.get();
            Long tenantId = dbConfig.getTenantId();
            String dbId = dbConfig.getDbId();
            Optional<Tenant> tenantOptional = tenantRepository.findById(tenantId);

            switch (action.toLowerCase()) {
                case "delete":
                    boolean b = terminateMysqlDbSystem(tenantOptional.get(), dbId);
                    if (b){
                        dbConfigRepository.delete(dbConfig);
                    }
                    break;
                default:
                    return ApiResponse.error("未知的操作类型: " + action);
            }
        } catch (Exception e) {
            log.error("执行 MySQL 操作失败: ", e);
            return ApiResponse.error("云厂商接口调用失败: " + e.getMessage());
        }
        return ApiResponse.success();
    }

    @Override
    @Transactional
    public ApiResponse resetMysqlAuth(Long id, Long tenantId) {
        try {
            DbConfig dbConfig = dbConfigRepository.findById(id).orElse(null);
            if (dbConfig == null) return ApiResponse.error("记录不存在");

            Tenant tenant = tenantRepository.findById(tenantId).orElse(null);
            if (tenant == null) return ApiResponse.error("租户不存在");

            String newAdminUser = dbConfig.getDbName();
            String newAdminPass = OciDbUtils.generateSecurePassword();
            boolean success = OciDbUtils.resetMysqlUserAndPass(tenant, dbConfig.getDbId(), newAdminUser, newAdminPass);

            if (success) {
                dbConfig.setDbPassword(newAdminPass);
                dbConfig.setUpdatedAt(LocalDateTime.now());
                dbConfigRepository.save(dbConfig);
                sendAuthResetNotification(tenant, dbConfig);
                return ApiResponse.success("账密重置成功");
            } else {
                return ApiResponse.error("重置失败，请检查实例状态");
            }
        } catch (Exception e) {
            log.error("重置MySQL账密异常", e);
            return ApiResponse.error("重置失败: " + e.getMessage());
        }
    }

    private void sendAuthResetNotification(Tenant tenant, DbConfig dbConfig) {
        try {
            String authResetMsg = String.format(MessageTemplate.MYSQL_AUTH_RESET_SUCCESS_TEMPLATE,
                    DateTimeUtils.getCurrentDateTime(),
                    tenant.getTenancyName(),
                    dbConfig.getDisplayName(),
                    dbConfig.getDbName(),
                    dbConfig.getDbPassword()
            );
            messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplateText(authResetMsg);
            log.debug("MySQL 账密重置通知已发送，租户: {}, 实例: {}", tenant.getDefName(), dbConfig.getDisplayName());
        } catch (Exception e) {
            log.error("发送 MySQL 账密重置通知失败: {}", e.getMessage(), e);
        }
    }

}
