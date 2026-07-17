package com.doubledimple.ociserver.utils.oracle;

import com.alibaba.fastjson2.JSON;
import com.doubledimple.dao.entity.Tenant;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.identity.model.RegionSubscription;
import com.oracle.bmc.ospgateway.SubscriptionServiceClient;
import com.oracle.bmc.ospgateway.model.Subscription;
import com.oracle.bmc.ospgateway.model.SubscriptionSummary;
import com.oracle.bmc.ospgateway.requests.GetSubscriptionRequest;
import com.oracle.bmc.ospgateway.requests.ListSubscriptionsRequest;
import com.oracle.bmc.ospgateway.responses.GetSubscriptionResponse;
import com.oracle.bmc.ospgateway.responses.ListSubscriptionsResponse;
import lombok.extern.slf4j.Slf4j;

import java.util.List;
import java.util.Optional;

import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProvider;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.queryRegions;
import com.doubledimple.ociserver.config.ProxyContext;

/**
 * @version 1.0.0
 * @ClassName OciGateWayUtils
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-05-24 11:36
 */
@Slf4j
public class OciGateWayUtils {

    /**
     * 获取账号类型信息
     * @param tenant 租户信息
     * @return AccountTypeInfo 包含账号类型和计划类型的信息，如果获取失败则返回null
     */
    public static Subscription getAccountTypeInfo(Tenant tenant) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        List<RegionSubscription> regionSubscriptions = queryRegions(provider);
        Optional<RegionSubscription> first = regionSubscriptions.stream()
                .filter(subscription -> Boolean.TRUE.equals(subscription.getIsHomeRegion()))
                .findFirst();
        if (!first.isPresent()) return null;
        RegionSubscription regionSubscription = first.get();
        try (SubscriptionServiceClient subscriptionServiceClient = SubscriptionServiceClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            // 首先获取订阅列表
            ListSubscriptionsRequest listRequest = ListSubscriptionsRequest.builder()
                    .compartmentId(provider.getTenantId())
                    .ospHomeRegion(regionSubscription.getRegionName())
                    .build();
            ListSubscriptionsResponse listResponse = subscriptionServiceClient.listSubscriptions(listRequest);
            List<SubscriptionSummary> items = listResponse.getSubscriptionCollection().getItems();
            if (items.isEmpty()) {
                log.warn("未找到任何订阅信息");
                return null;
            }

            // 获取第一个订阅的详细信息
            String subscriptionId = items.get(0).getId();

            GetSubscriptionRequest getRequest = GetSubscriptionRequest.builder()
                    .subscriptionId(subscriptionId)
                    .compartmentId(provider.getTenantId())
                    .ospHomeRegion(regionSubscription.getRegionName())
                    .build();

            GetSubscriptionResponse response = subscriptionServiceClient.getSubscription(getRequest);
            Subscription subscription = response.getSubscription();

            log.debug("成功获取账号类型信息 - 账户订阅信息: {}",
                    JSON.toJSONString(subscription));

            return subscription;

        } catch (Exception e) {
            log.warn("获取账号类型信息失败: {}", e.getMessage());
            return null;
        }
    }
}
