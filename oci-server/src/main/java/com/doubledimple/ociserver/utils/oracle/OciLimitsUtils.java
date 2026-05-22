package com.doubledimple.ociserver.utils.oracle;

import com.doubledimple.dao.entity.Tenant;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.AvailabilityDomain;
import com.oracle.bmc.identity.requests.ListAvailabilityDomainsRequest;
import com.oracle.bmc.identity.responses.ListAvailabilityDomainsResponse;
import com.oracle.bmc.limits.model.LimitDefinitionSummary;
import com.oracle.bmc.limits.model.LimitValueSummary;
import com.oracle.bmc.limits.model.ResourceAvailability;
import com.oracle.bmc.limits.requests.GetResourceAvailabilityRequest;
import com.oracle.bmc.limits.requests.ListLimitDefinitionsRequest;
import com.oracle.bmc.limits.requests.ListLimitValuesRequest;
import com.oracle.bmc.limits.responses.GetResourceAvailabilityResponse;
import com.oracle.bmc.limits.responses.ListLimitDefinitionsResponse;
import com.oracle.bmc.limits.responses.ListLimitValuesResponse;
import com.oracle.bmc.limits.responses.ListServicesResponse;
import com.oracle.bmc.limits.LimitsClient;
import lombok.extern.slf4j.Slf4j;

import java.util.ArrayList;
import java.util.List;

import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProvider;

/**
 * @version 1.0.0
 * @ClassName OciLimitsUtils
 * @Description 限额资源
 * @Author doubleDimple
 * @Date 2026-03-12 10:37
 */
@Slf4j
public class OciLimitsUtils {

    public static final String ARM_CORE_FREE_QUOTA_NAME = "standard-a1-core-count";
    public static final String ARM_MEM_FREE_QUOTA_NAME = "standard-a1-memory-count";

    //amd可开启的配额(amd只能开免费的1+1)
    public static final String AMD_CORE_FREE_QUOTA_NAME = "standard-e2-micro-core-count";

    //AMD可开启的总数量
    public static final String AMD_VM_FREE_COUNT_NAME = "vm-standard-e2-1-micro-count";

    /**
     * 获取支持限额管理的所有服务列表
     * 例如: 'compute', 'block-storage', 'virtual-network'
     */
    public static List<com.oracle.bmc.limits.model.ServiceSummary> listServices(Tenant tenant) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (LimitsClient limitsClient = LimitsClient.builder().build(provider)) {
            com.oracle.bmc.limits.requests.ListServicesRequest request = com.oracle.bmc.limits.requests.ListServicesRequest.builder()
                    .compartmentId(provider.getTenantId())
                    .build();

            ListServicesResponse response = limitsClient.listServices(request);
            return response.getItems();
        } catch (Exception e) {
            log.error("获取支持限额的服务列表失败: {}", e.getMessage());
            return new ArrayList<>();
        }
    }

    /**
     * 查询特定服务的限额定义
     * 了解哪些资源是可以申请提升的
     */
    public static List<LimitDefinitionSummary> listLimitDefinitions(Tenant tenant, String serviceName) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (LimitsClient limitsClient = LimitsClient.builder().build(provider)) {
            ListLimitDefinitionsRequest request = ListLimitDefinitionsRequest.builder()
                    .compartmentId(provider.getTenantId())
                    .serviceName(serviceName)
                    .build();

            ListLimitDefinitionsResponse response = limitsClient.listLimitDefinitions(request);
            return response.getItems();
        } catch (Exception e) {
            log.error("获取服务 {} 的限额定义失败: {}", serviceName, e.getMessage());
            return new ArrayList<>();
        }
    }

    /**
     * 获取当前的限额值 (Limit Values)
     * 例如查询当前区域 ARM 核心的总限额
     */
    public static List<LimitValueSummary> getLimitValues(Tenant tenant, String serviceName) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (LimitsClient limitsClient = LimitsClient.builder().build(provider)) {
            ListLimitValuesRequest request = ListLimitValuesRequest.builder()
                    .compartmentId(provider.getTenantId())
                    .serviceName(serviceName)
                    .build();

            ListLimitValuesResponse response = limitsClient.listLimitValues(request);
            return response.getItems();
        } catch (Exception e) {
            log.error("查询服务 {} 的限额值失败: {}", serviceName, e.getMessage());
            return new ArrayList<>();
        }
    }

    /**
     * 获取特定资源的实时可用性 (Resource Availability)
     * 能够看到：总限额是多少，已经使用了多少，还剩多少
     * * @param serviceName 例如 "compute"
     * @param limitName 例如 "standard-a1-memory-count" (ARM 内存) 或 "standard-a1-core-count" (ARM 核心)
     */
    public static ResourceAvailability getResourceAvailability(Tenant tenant, String serviceName, String limitName) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (LimitsClient limitsClient = LimitsClient.builder().build(provider)) {
            GetResourceAvailabilityRequest request = GetResourceAvailabilityRequest.builder()
                    .compartmentId(provider.getTenantId())
                    .serviceName(serviceName)
                    .limitName(limitName)
                    .build();

            GetResourceAvailabilityResponse response = limitsClient.getResourceAvailability(request);
            ResourceAvailability availability = response.getResourceAvailability();

            log.info("资源 [{}] 状态: 总限额: {}, 已使用: {}, 剩余可用: {}",
                    limitName, availability.getFractionalUsage(), availability.getUsed(), availability.getAvailable());

            return availability;
        } catch (Exception e) {
            log.error("获取资源 {} 的可用性失败: {}", limitName, e.getMessage());
            return null;
        }
    }

    /**
     * 检查是否有足够的资源来创建实例
     * 比如在抢机器脚本运行前，先调用此方法
     */
    public static boolean hasEnoughResource(Tenant tenant, String serviceName, String limitName, Long requiredAmount) {
        ResourceAvailability availability = getResourceAvailability(tenant, serviceName, limitName);
        if (availability == null || availability.getAvailable() == null) {
            return false;
        }
        return availability.getAvailable() >= requiredAmount;
    }

    /**
     * 获取指定服务在当前区域所有 AD 下的具体限额数值
     * 这样你就能看到 AMD/ARM 在 AD-1, AD-2 各自的配额
     * @param serviceName 例如 "compute"
     */
    public static void fetchAllResourceLimits(Tenant tenant, String serviceName) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

        try (LimitsClient limitsClient = LimitsClient.builder().build(provider)) {
            String nextPage = null;
            log.info("--- 开始全量扫描服务 [{}] 的限额 ---", serviceName);

            do {
                ListLimitValuesRequest request = ListLimitValuesRequest.builder()
                        .compartmentId(provider.getTenantId())
                        .serviceName(serviceName)
                        .page(nextPage)
                        .build();

                ListLimitValuesResponse response = limitsClient.listLimitValues(request);

                for (LimitValueSummary limit : response.getItems()) {
                    String ad = limit.getAvailabilityDomain() != null ? limit.getAvailabilityDomain() : "Regional";
                    Long value = limit.getValue();
                    if (limit.getName().contains("micro") || value > 0L) {
                        log.info("资源标识: {} | AD: {} | 限额: {}",
                                limit.getName(), ad, value);
                    }
                }
                nextPage = response.getOpcNextPage();

            } while (nextPage != null);

        } catch (Exception e) {
            log.error("全量获取限额失败", e);
        }
    }


    /**
     * 专门查询并过滤具有可用 ARM (A1) 配额的可用性域
     * 只有 standard-a1-core-count 和 standard-a1-memory-count 同时 > 0 才会返回
     *
     * @param identityClient 身份客户端
     * @param limitsClient   限额客户端
     * @param compartmentId  租户 ID (Root Compartment)
     * @return 只有具备 ARM 资源的 AD 列表
     */
    public static List<AvailabilityDomain> getAvailableArmAds(
            IdentityClient identityClient,
            LimitsClient limitsClient,
            String compartmentId) throws Exception {

        // 1. 获取所有 AD
        ListAvailabilityDomainsResponse listAdsResponse =
                identityClient.listAvailabilityDomains(ListAvailabilityDomainsRequest.builder()
                        .compartmentId(compartmentId)
                        .build());

        List<AvailabilityDomain> allAds = listAdsResponse.getItems();
        List<AvailabilityDomain> validArmAds = new ArrayList<>();
        log.info("开始扫描区域内所有 AD 的 ARM (A1) 配额...");
        for (AvailabilityDomain ad : allAds) {
            String adName = ad.getName();
            Long availableCores = getAvailableQuantity(limitsClient, compartmentId, adName, "standard-a1-core-count");
            if (availableCores != null && availableCores > 0) {
                Long availableMemory = getAvailableQuantity(limitsClient, compartmentId, adName, "standard-a1-memory-count");
                if (availableMemory != null && availableMemory > 0) {
                    log.info("AD: {} 具备 ARM 资源能力 (剩余核心: {}, 剩余内存: {}GB)", adName, availableCores, availableMemory);
                    validArmAds.add(ad);
                } else {
                    log.warn("AD: {} 核心充足但内存配额为 0，已排除", adName);
                }
            } else {
                log.warn("AD: {} 核心配额为 0，已排除", adName);
            }
        }
        return validArmAds;
    }

    /**
     * 扫描并过滤具有可用“免费”配额的可用性域
     * 支持 ARM (A1) 和 AMD (E2.Micro) 的配额预检
     * @param tenant   租户
     * @param freeResource
     *  ARM (true: 查 A1, false: 查 AMD)
     *                 free arm:1
     *                 free amd:2
     *                 paid: 0
     * @return 具备对应免费配额的 AD 列表
     */
    public static List<AvailabilityDomain> getSafeFreeAds(Tenant tenant, Integer freeResource) {
        List<AvailabilityDomain> validAds = new ArrayList<>();
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        String compartmentId = provider.getTenantId();
        try (IdentityClient identityClient = IdentityClient.builder().build(provider);
             LimitsClient limitsClient = LimitsClient.builder().build(provider)) {

            ListAvailabilityDomainsResponse listAdsResponse =
                    identityClient.listAvailabilityDomains(ListAvailabilityDomainsRequest.builder()
                            .compartmentId(compartmentId)
                            .build());

            List<AvailabilityDomain> allAds = listAdsResponse.getItems();
            if (freeResource == 0) {
                return allAds;
            }
            boolean isArm = freeResource == 1;
            String type = isArm ? "ARM (A1)" : "AMD (E2.Micro)";
            log.info("--- 开始扫描租户 [{}] 的 {} 免费配额 ---", tenant.getTenantId(), type);
            for (AvailabilityDomain ad : allAds) {
                String adName = ad.getName();
                boolean isAvailable = false;
                if (isArm) {
                    Long coreAvail = getAvailableQuantity(limitsClient, compartmentId, adName, ARM_CORE_FREE_QUOTA_NAME);
                    Long memAvail = getAvailableQuantity(limitsClient, compartmentId, adName, ARM_MEM_FREE_QUOTA_NAME);
                    if (coreAvail > 0 && memAvail > 0) {
                        log.info("AD: {} 具备 ARM 免费余量 (核: {}, 内存: {}GB)", adName, coreAvail, memAvail);
                        isAvailable = true;
                    }
                } else {
                    // AMD 核心和实例数
                    Long amdCoreAvail = getAvailableQuantity(limitsClient, compartmentId, adName, AMD_CORE_FREE_QUOTA_NAME);
                    Long amdInstAvail = getAvailableQuantity(limitsClient, compartmentId, adName, AMD_VM_FREE_COUNT_NAME);
                    if (amdCoreAvail > 0 || amdInstAvail > 0) {
                        log.info("AD: {} 具备 AMD 免费余量", adName);
                        isAvailable = true;
                    }
                }
                if (isAvailable) {
                    validAds.add(ad);
                } else {
                    log.warn("AD: {} 无 {} 余额，已排除", adName, type);
                }
            }
        } catch (Exception e) {
            log.error("扫描租户 [{}] 免费配额时发生异常: {}", tenant.getTenantId(), e.getMessage());
        }

        return validAds;
    }

    /**
     * 内部辅助函数：获取特定资源的剩余可用数量
     */
    private static Long getAvailableQuantity(LimitsClient limitsClient, String compartmentId, String adName, String limitName) {
        try {
            GetResourceAvailabilityRequest request = GetResourceAvailabilityRequest.builder()
                    .compartmentId(compartmentId)
                    .serviceName("compute")
                    .limitName(limitName)
                    .availabilityDomain(adName)
                    .build();

            GetResourceAvailabilityResponse response = limitsClient.getResourceAvailability(request);
            return response.getResourceAvailability().getAvailable();
        } catch (Exception e) {
            log.error("查询 AD: {} 的资源 [{}] 失败: {}", adName, limitName, e.getMessage());
            return 0L;
        }
    }
}
