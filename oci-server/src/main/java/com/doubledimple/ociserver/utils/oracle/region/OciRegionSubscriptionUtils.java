package com.doubledimple.ociserver.utils.oracle.region;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.oci.SubscriptionStatus;
import com.doubledimple.ociserver.pojo.response.BatchSubscriptionResult;
import com.doubledimple.ociserver.pojo.response.RegionSubscriptionResult;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.identity.Identity;
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.CreateRegionSubscriptionDetails;
import com.oracle.bmc.identity.model.Region;
import com.oracle.bmc.identity.model.RegionSubscription;
import com.oracle.bmc.identity.requests.CreateRegionSubscriptionRequest;
import com.oracle.bmc.identity.requests.ListRegionSubscriptionsRequest;
import com.oracle.bmc.identity.requests.ListRegionsRequest;
import com.oracle.bmc.identity.responses.CreateRegionSubscriptionResponse;
import com.oracle.bmc.identity.responses.ListRegionSubscriptionsResponse;
import com.oracle.bmc.identity.responses.ListRegionsResponse;
import com.oracle.bmc.model.BmcException;
import lombok.extern.slf4j.Slf4j;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;
import com.doubledimple.ociserver.config.ProxyContext;

/**
 * OCI区域订阅管理工具类
 * 提供区域查询、订阅、批量管理等功能
 *
 * @author doubleDimple
 * @date 2025-07-13
 */
@Slf4j
public class OciRegionSubscriptionUtils {


    /**
     * 获取所有可用区域列表
     *
     * @param tenant 租户信息
     * @return 所有可用区域列表
     */
    public static List<Region> getAllAvailableRegions(Tenant tenant) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        return getAllAvailableRegions(provider);
    }

    /**
     * 获取所有可用区域列表（内部方法）
     */
    private static List<Region> getAllAvailableRegions(SimpleAuthenticationDetailsProvider provider) {
        try (Identity identityClient = IdentityClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            ListRegionsRequest listRegionsRequest = ListRegionsRequest.builder().build();
            ListRegionsResponse response = identityClient.listRegions(listRegionsRequest);

            log.debug("获取到 {} 个可用区域", response.getItems().size());
            return response.getItems();
        } catch (Exception e) {
            log.error("获取可用区域列表失败", e);
            return new ArrayList<>();
        }
    }

    /**
     * 获取当前已订阅的区域列表
     *
     * @param tenant 租户信息
     * @return 已订阅的区域列表
     */
    public static List<RegionSubscription> getSubscribedRegions(Tenant tenant) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        return getSubscribedRegions(provider);
    }


    /**
     * 获取当前已订阅的区域列表（内部方法）
     */
    private static List<RegionSubscription> getSubscribedRegions(SimpleAuthenticationDetailsProvider provider) {
        try (Identity identityClient = IdentityClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            ListRegionSubscriptionsRequest request = ListRegionSubscriptionsRequest.builder()
                    .tenancyId(provider.getTenantId())
                    .build();

            ListRegionSubscriptionsResponse response = identityClient.listRegionSubscriptions(request);

            log.debug("当前已订阅 {} 个区域", response.getItems().size());
            return response.getItems();
        } catch (Exception e) {
            log.error("获取已订阅区域列表失败", e);
            return new ArrayList<>();
        }
    }

    /**
     * 获取未订阅的区域列表
     *
     * @param tenant 租户信息
     * @return 未订阅的区域列表
     */
    public static List<Region> getUnsubscribedRegions(Tenant tenant) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        return getUnsubscribedRegions(provider);
    }

    /**
     * 获取未订阅的区域列表
     *
     * @param user 用户信息
     * @return 未订阅的区域列表
     */
    public static List<Region> getUnsubscribedRegions(com.doubledimple.ociserver.pojo.domain.dto.User user) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(user);
        return getUnsubscribedRegions(provider);
    }

    /**
     * 获取未订阅的区域列表（内部方法）
     */
    private static List<Region> getUnsubscribedRegions(SimpleAuthenticationDetailsProvider provider) {
        List<Region> allRegions = getAllAvailableRegions(provider);
        List<RegionSubscription> subscribedRegions = getSubscribedRegions(provider);

        Set<String> subscribedRegionKeys = subscribedRegions.stream()
                .map(RegionSubscription::getRegionKey)
                .collect(Collectors.toSet());

        List<Region> unsubscribedRegions = allRegions.stream()
                .filter(region -> !subscribedRegionKeys.contains(region.getKey()))
                .collect(Collectors.toList());

        log.info("发现 {} 个未订阅的区域", unsubscribedRegions.size());
        return unsubscribedRegions;
    }

    /**
     * 订阅单个区域
     *
     * @param tenant 租户信息
     * @param regionKey 区域标识符
     * @return 订阅结果
     */
    public static RegionSubscriptionResult subscribeToRegion(Tenant tenant, String regionKey) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        return subscribeToRegion(provider, regionKey);
    }


    /**
     * 订阅单个区域（内部方法）
     */
    private static RegionSubscriptionResult subscribeToRegion(SimpleAuthenticationDetailsProvider provider, String regionKey) {
        log.info("开始订阅区域: {}", regionKey);

        try (Identity identityClient = IdentityClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            // 1. 检查区域是否已经订阅
            List<RegionSubscription> subscribedRegions = getSubscribedRegions(provider);
            boolean alreadySubscribed = subscribedRegions.stream()
                    .anyMatch(subscription -> subscription.getRegionKey().equals(regionKey));

            if (alreadySubscribed) {
                log.info("区域 {} 已经订阅", regionKey);
                return new RegionSubscriptionResult(true, "区域已经订阅", regionKey, regionKey);
            }

            // 2. 检查区域是否存在
            List<Region> availableRegions = getAllAvailableRegions(provider);
            Optional<Region> targetRegion = availableRegions.stream()
                    .filter(region -> region.getKey().equals(regionKey))
                    .findFirst();

            if (!targetRegion.isPresent()) {
                String message = "区域 " + regionKey + " 不存在或不可用";
                log.error(message);
                return new RegionSubscriptionResult(false, message, regionKey, regionKey);
            }

            // 3. 创建订阅请求
            CreateRegionSubscriptionDetails subscriptionDetails = CreateRegionSubscriptionDetails.builder()
                    .regionKey(regionKey)
                    .build();

            CreateRegionSubscriptionRequest request = CreateRegionSubscriptionRequest.builder()
                    .tenancyId(provider.getTenantId())
                    .createRegionSubscriptionDetails(subscriptionDetails)
                    .build();

            // 4. 发送订阅请求
            CreateRegionSubscriptionResponse response = identityClient.createRegionSubscription(request);
            RegionSubscription subscription = response.getRegionSubscription();

            log.info("区域 {} 订阅请求已发送，订阅ID: {}", regionKey, subscription.getRegionKey());

            // 5. 等待订阅激活
            RegionSubscriptionResult result = waitForSubscriptionActivation(provider, regionKey, 30);
            result.setSubscriptionId(subscription.getRegionKey());

            return result;

        } catch (BmcException e) {
            String message = String.format("订阅区域 %s 失败 (状态码: %d)", regionKey, e.getStatusCode());
            log.error(message, e);
            return new RegionSubscriptionResult(false, message, regionKey, regionKey);
        } catch (Exception e) {
            String message = String.format("订阅区域 %s 时发生异常: %s", regionKey, e.getMessage());
            log.error(message, e);
            return new RegionSubscriptionResult(false, message, regionKey, regionKey);
        }
    }

    /**
     * 批量订阅区域
     *
     * @param tenant 租户信息
     * @param regionKeys 要订阅的区域标识符列表
     * @return 批量订阅结果
     */
    public static BatchSubscriptionResult batchSubscribeToRegions(Tenant tenant, List<String> regionKeys) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        return batchSubscribeToRegions(provider, regionKeys);
    }


    /**
     * 批量订阅区域（内部方法）
     */
    private static BatchSubscriptionResult batchSubscribeToRegions(SimpleAuthenticationDetailsProvider provider, List<String> regionKeys) {
        log.info("开始批量订阅 {} 个区域", regionKeys.size());

        BatchSubscriptionResult batchResult = new BatchSubscriptionResult();

        for (String regionKey : regionKeys) {
            try {
                RegionSubscriptionResult result = subscribeToRegion(provider, regionKey);
                batchResult.addResult(result);

                log.info("区域 {} 订阅结果: {}", regionKey, result.isSuccess() ? "成功" : "失败");

                // 在请求之间添加短暂延迟，避免API限流
                Thread.sleep(1000);

            } catch (Exception e) {
                RegionSubscriptionResult failedResult = new RegionSubscriptionResult(
                        false, "订阅过程中发生异常: " + e.getMessage(), regionKey, regionKey);
                batchResult.addResult(failedResult);
                log.error("批量订阅区域 {} 时发生异常", regionKey, e);
            }
        }

        log.info("批量订阅完成: {}", batchResult);
        return batchResult;
    }

    /**
     * 订阅所有未订阅的区域
     *
     * @param tenant 租户信息
     * @return 批量订阅结果
     */
    public static BatchSubscriptionResult subscribeToAllUnsubscribedRegions(Tenant tenant) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        return subscribeToAllUnsubscribedRegions(provider);
    }


    /**
     * 订阅所有未订阅的区域（内部方法）
     */
    private static BatchSubscriptionResult subscribeToAllUnsubscribedRegions(SimpleAuthenticationDetailsProvider provider) {
        List<Region> unsubscribedRegions = getUnsubscribedRegions(provider);
        List<String> regionKeys = unsubscribedRegions.stream()
                .map(Region::getKey)
                .collect(Collectors.toList());

        log.info("准备订阅所有未订阅的区域，共 {} 个", regionKeys.size());

        return batchSubscribeToRegions(provider, regionKeys);
    }

    /**
     * 等待区域订阅激活
     *
     * @param provider 认证提供者
     * @param regionKey 区域标识符
     * @param maxWaitMinutes 最大等待时间（分钟）
     * @return 订阅结果
     */
    private static RegionSubscriptionResult waitForSubscriptionActivation(SimpleAuthenticationDetailsProvider provider,
                                                                          String regionKey, int maxWaitMinutes) {
        log.info("等待区域 {} 订阅激活，最大等待时间: {} 分钟", regionKey, maxWaitMinutes);

        final int maxAttempts = maxWaitMinutes * 2; // 每30秒检查一次
        final int waitIntervalSeconds = 30;

        for (int attempt = 1; attempt <= maxAttempts; attempt++) {
            try {
                List<RegionSubscription> subscriptions = getSubscribedRegions(provider);
                Optional<RegionSubscription> targetSubscription = subscriptions.stream()
                        .filter(subscription -> subscription.getRegionKey().equals(regionKey))
                        .findFirst();

                if (targetSubscription.isPresent()) {
                    RegionSubscription subscription = targetSubscription.get();
                    RegionSubscription.Status status = subscription.getStatus();

                    log.info("区域 {} 当前状态: {}, 检查次数: {}/{}", regionKey, status, attempt, maxAttempts);

                    if ("READY".equals(status.getValue())) {
                        String message = String.format("区域 %s 已成功激活", regionKey);
                        log.info(message);
                        RegionSubscriptionResult result = new RegionSubscriptionResult(true, message, regionKey, subscription.getRegionName());
                        result.setStatus(SubscriptionStatus.READY);
                        return result;
                    } else if ("FAILED".equals(status.getValue())) {
                        String message = String.format("区域 %s 订阅失败", regionKey);
                        log.error(message);
                        RegionSubscriptionResult result = new RegionSubscriptionResult(false, message, regionKey, subscription.getRegionName());
                        result.setStatus(SubscriptionStatus.FAILED);
                        return result;
                    }
                }

                // 等待后继续检查
                Thread.sleep(waitIntervalSeconds * 1000L);

            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                String message = "等待区域订阅激活过程被中断";
                log.warn(message);
                return new RegionSubscriptionResult(false, message, regionKey, regionKey);
            } catch (Exception e) {
                log.warn("检查区域订阅状态时发生异常: {}", e.getMessage());
            }
        }

        String message = String.format("等待区域 %s 激活超时（%d 分钟）", regionKey, maxWaitMinutes);
        log.warn(message);
        return new RegionSubscriptionResult(false, message, regionKey, regionKey);
    }

    /**
     * 检查区域是否已订阅
     *
     * @param tenant 租户信息
     * @param regionKey 区域标识符
     * @return 是否已订阅
     */
    public static boolean isRegionSubscribed(Tenant tenant, String regionKey) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        return isRegionSubscribed(provider, regionKey);
    }

    /**
     * 检查区域是否已订阅（内部方法）
     */
    private static boolean isRegionSubscribed(SimpleAuthenticationDetailsProvider provider, String regionKey) {
        List<RegionSubscription> subscriptions = getSubscribedRegions(provider);
        return subscriptions.stream()
                .anyMatch(subscription -> subscription.getRegionKey().equals(regionKey));
    }

    /**
     * 获取区域订阅状态
     *
     * @param tenant 租户信息
     * @param regionKey 区域标识符
     * @return 订阅状态，如果未订阅则返回null
     */
    public static String getRegionSubscriptionStatus(Tenant tenant, String regionKey) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        return getRegionSubscriptionStatus(provider, regionKey);
    }


    /**
     * 获取区域订阅状态（内部方法）
     */
    private static String getRegionSubscriptionStatus(SimpleAuthenticationDetailsProvider provider, String regionKey) {
        List<RegionSubscription> subscriptions = getSubscribedRegions(provider);
        RegionSubscription.Status status = subscriptions.stream()
                .filter(subscription -> subscription.getRegionKey().equals(regionKey))
                .map(RegionSubscription::getStatus)
                .findFirst()
                .orElse(null);
        return status.getValue();
    }

    /**
     * 打印区域订阅摘要信息
     *
     * @param tenant 租户信息
     */
    public static void printRegionSubscriptionSummary(Tenant tenant) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        printRegionSubscriptionSummary(provider);
    }


    /**
     * 打印区域订阅摘要信息（内部方法）
     */
    private static void printRegionSubscriptionSummary(SimpleAuthenticationDetailsProvider provider) {
        try {
            List<Region> allRegions = getAllAvailableRegions(provider);
            List<RegionSubscription> subscribedRegions = getSubscribedRegions(provider);
            List<Region> unsubscribedRegions = getUnsubscribedRegions(provider);

            log.info("================== 区域订阅摘要 ==================");
            log.info("总可用区域数: {}", allRegions.size());
            log.info("已订阅区域数: {}", subscribedRegions.size());
            log.info("未订阅区域数: {}", unsubscribedRegions.size());

            log.info("已订阅区域:");
            subscribedRegions.forEach(subscription ->
                    log.info("  - {}: {} (状态: {})",
                            subscription.getRegionKey(),
                            subscription.getRegionName(),
                            subscription.getStatus())
            );

            if (!unsubscribedRegions.isEmpty()) {
                log.info("未订阅区域:");
                unsubscribedRegions.forEach(region ->
                        log.info("  - {}: {}", region.getKey(), region.getName())
                );
            }

            log.info("================================================");
        } catch (Exception e) {
            log.error("打印区域订阅摘要时发生错误", e);
        }
    }
}
