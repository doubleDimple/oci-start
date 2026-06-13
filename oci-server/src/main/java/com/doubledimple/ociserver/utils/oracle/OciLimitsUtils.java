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
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

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
     * 获取租户在当前区域的全量配额信息（所有服务）。
     * <p>
     * 流程：
     * 1. 列出所有支持限额的服务
     * 2. 逐服务分页查询 LimitValues，只保留 value > 0 的限额
     * 3. 对每个非零限额，通过 GetResourceAvailability 获取已用/可用量
     *    - 区域级限额（availabilityDomain = null）：直接查询
     *    - AD 级限额：逐 AD 查询后求和
     *
     * @return Map&lt;serviceName, List&lt;{name, total, used, available}&gt;&gt;，按服务分组
     */
    public static Map<String, List<Map<String, Object>>> getAllServiceQuotas(Tenant tenant) {
        return getAllServiceQuotas(tenant, java.util.Arrays.asList("compute", "block-storage", "object-storage"));
    }

    public static Map<String, List<Map<String, Object>>> getAllServiceQuotas(Tenant tenant, List<String> targetServices) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        Map<String, List<Map<String, Object>>> result = new LinkedHashMap<>();

        try (LimitsClient limitsClient = LimitsClient.builder().build(provider);
             IdentityClient identityClient = IdentityClient.builder().build(provider)) {

            String compartmentId = provider.getTenantId();

            // 获取所有 AD（供 AD 级别的限额聚合使用）
            List<AvailabilityDomain> ads = identityClient.listAvailabilityDomains(
                    ListAvailabilityDomainsRequest.builder()
                            .compartmentId(compartmentId)
                            .build()).getItems();

            for (String svcName : targetServices) {

                // [0]=total, [1]=used, [2]=available
                Map<String, long[]> adLimits = new LinkedHashMap<>();      // AD 级限额（跨 AD 累加）
                Map<String, long[]> regionalLimits = new LinkedHashMap<>(); // 区域级限额

                // ── Pass 1：逐 AD 查询限额值 + 可用性，合并在同一 AD 循环 ──
                for (AvailabilityDomain ad : ads) {
                    Set<String> adLimitNames = new LinkedHashSet<>();
                    String nextPage = null;
                    do {
                        ListLimitValuesResponse lvResp = limitsClient.listLimitValues(
                                ListLimitValuesRequest.builder()
                                        .compartmentId(compartmentId)
                                        .serviceName(svcName)
                                        .availabilityDomain(ad.getName())
                                        .page(nextPage)
                                        .build());
                        for (LimitValueSummary lv : lvResp.getItems()) {
                            if (lv.getValue() == null || lv.getValue() <= 0) continue;
                            adLimits.computeIfAbsent(lv.getName(), k -> new long[3]);
                            adLimits.get(lv.getName())[0] += lv.getValue();
                            adLimitNames.add(lv.getName());
                        }
                        nextPage = lvResp.getOpcNextPage();
                    } while (nextPage != null);

                    // 同一 AD 循环内获取可用性，避免二次遍历 AD
                    for (String limitName : adLimitNames) {
                        try {
                            ResourceAvailability ra = limitsClient.getResourceAvailability(
                                    GetResourceAvailabilityRequest.builder()
                                            .compartmentId(compartmentId)
                                            .serviceName(svcName)
                                            .limitName(limitName)
                                            .availabilityDomain(ad.getName())
                                            .build()).getResourceAvailability();
                            if (ra.getUsed() != null)      adLimits.get(limitName)[1] += ra.getUsed();
                            if (ra.getAvailable() != null) adLimits.get(limitName)[2] += ra.getAvailable();
                        } catch (Exception ignored) {
                        }
                    }
                }

                // ── Pass 2：查询区域级限额（不带 AD 过滤，跳过 AD 级条目）──
                String nextPage = null;
                do {
                    ListLimitValuesResponse lvResp = limitsClient.listLimitValues(
                            ListLimitValuesRequest.builder()
                                    .compartmentId(compartmentId)
                                    .serviceName(svcName)
                                    .page(nextPage)
                                    .build());
                    for (LimitValueSummary lv : lvResp.getItems()) {
                        if (lv.getValue() == null || lv.getValue() <= 0) continue;
                        if (lv.getAvailabilityDomain() != null) continue; // AD 级已在 Pass1 处理
                        regionalLimits.put(lv.getName(), new long[]{lv.getValue(), 0L, lv.getValue()});
                    }
                    nextPage = lvResp.getOpcNextPage();
                } while (nextPage != null);

                for (String limitName : regionalLimits.keySet()) {
                    try {
                        ResourceAvailability ra = limitsClient.getResourceAvailability(
                                GetResourceAvailabilityRequest.builder()
                                        .compartmentId(compartmentId)
                                        .serviceName(svcName)
                                        .limitName(limitName)
                                        .build()).getResourceAvailability();
                        if (ra.getUsed() != null)      regionalLimits.get(limitName)[1] = ra.getUsed();
                        if (ra.getAvailable() != null) regionalLimits.get(limitName)[2] = ra.getAvailable();
                    } catch (Exception e) {
                        log.debug("获取区域级 {}/{} 可用性失败: {}", svcName, limitName, e.getMessage());
                    }
                }

                // ── 合并结果 ──
                List<Map<String, Object>> quotaItems = new ArrayList<>();
                adLimits.forEach((name, d) -> {
                    if (d[0] <= 0) return;
                    Map<String, Object> item = new LinkedHashMap<>();
                    item.put("name", name);
                    item.put("total", d[0]);
                    item.put("used", d[1]);
                    item.put("available", d[2] > 0 ? d[2] : Math.max(0L, d[0] - d[1]));
                    quotaItems.add(item);
                });
                regionalLimits.forEach((name, d) -> {
                    Map<String, Object> item = new LinkedHashMap<>();
                    item.put("name", name);
                    item.put("total", d[0]);
                    item.put("used", d[1]);
                    item.put("available", d[2]);
                    quotaItems.add(item);
                });

                // 将 *-bytes 限额转换为 GB（÷ 1073741824），并重命名为 *-gb
                for (Map<String, Object> item : quotaItems) {
                    String n = (String) item.get("name");
                    if (n != null && n.endsWith("-bytes")) {
                        item.put("name", n.replace("-bytes", "-gb"));
                        item.put("total",     ((Long) item.get("total"))     / 1073741824L);
                        item.put("used",      ((Long) item.get("used"))      / 1073741824L);
                        item.put("available", ((Long) item.get("available")) / 1073741824L);
                    }
                }

                if (!quotaItems.isEmpty()) {
                    result.put(svcName, quotaItems);
                }
            }
        } catch (Exception e) {
            log.error("获取全量配额失败: {}", e.getMessage(), e);
        }
        return result;
    }

    /**
     * 查询单个服务的配额，供前端按需按服务查询（避免一次性查三个服务太慢）。
     *
     * @param serviceName 服务名，如 "compute"、"block-storage"、"object-storage"
     * @return List&lt;{name, total, used, available}&gt;
     */
    public static List<Map<String, Object>> getSingleServiceQuotas(Tenant tenant, String serviceName) {
        Map<String, List<Map<String, Object>>> all = getAllServiceQuotas(tenant,
                java.util.Collections.singletonList(serviceName));
        return all.getOrDefault(serviceName, new ArrayList<>());
    }

    /**
     * 服务器端分页查询单服务配额，使用 hasNextPage 设计避免统计总条数。
     * <p>
     * 分两步执行：
     * <ol>
     *   <li>Step 1（可早退出）：单次 listLimitValues（不传 availabilityDomain）收集不重复的非零限额名，
     *       OCI 返回的结果同时包含 AD 级（lv.getAvailabilityDomain() != null）和区域级条目。
     *       只需收集到 {@code (page+1)*pageSize + 1} 条即可判断是否有下一页，无需遍历全量。</li>
     *   <li>Step 2（按页）：只对当页 pageSize 条目调用 getResourceAvailability 获取精确数据。</li>
     * </ol>
     *
     * @return Map 包含 items / page / pageSize / hasNextPage
     */
    public static Map<String, Object> getSingleServiceQuotasPaged(
            Tenant tenant, String serviceName, int page, int pageSize) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        // 只需比当前页末尾多取 1 条，即可判断是否存在下一页
        int needed = (page + 1) * pageSize + 1;

        try (LimitsClient limitsClient = LimitsClient.builder().build(provider);
             IdentityClient identityClient = IdentityClient.builder().build(provider)) {

            String compartmentId = provider.getTenantId();

            // Step 1: 单次 listLimitValues（无 AD 过滤）收集不重复非零限额名，达到 needed 后早退出
            // LinkedHashMap 保留首次出现顺序；value=true 表示 AD 级，false 表示区域级
            Map<String, Boolean> limitIsAD = new LinkedHashMap<>();
            boolean hasNextPage = false;

            String ociNextPage = null;
            outer:
            do {
                ListLimitValuesResponse resp = limitsClient.listLimitValues(
                        ListLimitValuesRequest.builder()
                                .compartmentId(compartmentId)
                                .serviceName(serviceName)
                                .page(ociNextPage)
                                .build());
                for (LimitValueSummary lv : resp.getItems()) {
                    if (lv.getValue() == null || lv.getValue() <= 0) continue;
                    if (!limitIsAD.containsKey(lv.getName())) {
                        limitIsAD.put(lv.getName(), lv.getAvailabilityDomain() != null);
                        if (limitIsAD.size() >= needed) {
                            hasNextPage = true;
                            break outer; // 已足够判断，提前结束
                        }
                    }
                }
                ociNextPage = resp.getOpcNextPage();
            } while (ociNextPage != null);

            // 取当前页的名称切片
            int from = page * pageSize;
            List<String> allNames = new ArrayList<>(limitIsAD.keySet());
            if (from >= allNames.size()) {
                Map<String, Object> result = new LinkedHashMap<>();
                result.put("items", new ArrayList<>());
                result.put("page", (long) 0);
                result.put("pageSize", (long) pageSize);
                result.put("hasNextPage", false);
                return result;
            }
            List<String> pageNames = allNames.subList(from, Math.min(from + pageSize, allNames.size()));

            // Step 2: 只对当页条目调用 getResourceAvailability
            List<AvailabilityDomain> ads = identityClient.listAvailabilityDomains(
                    ListAvailabilityDomainsRequest.builder()
                            .compartmentId(compartmentId).build()).getItems();

            List<Map<String, Object>> items = new ArrayList<>();
            for (String limitName : pageNames) {
                boolean isAD = Boolean.TRUE.equals(limitIsAD.get(limitName));
                long totalVal = 0L, used = 0L, available = 0L;

                if (isAD) {
                    long aggUsed = 0L, aggAvail = 0L;
                    for (AvailabilityDomain ad : ads) {
                        try {
                            ResourceAvailability ra = limitsClient.getResourceAvailability(
                                    GetResourceAvailabilityRequest.builder()
                                            .compartmentId(compartmentId)
                                            .serviceName(serviceName)
                                            .limitName(limitName)
                                            .availabilityDomain(ad.getName())
                                            .build()).getResourceAvailability();
                            if (ra.getUsed() != null) aggUsed += ra.getUsed();
                            if (ra.getAvailable() != null) aggAvail += ra.getAvailable();
                        } catch (Exception ignored) {}
                    }
                    totalVal = aggUsed + aggAvail;
                    used = aggUsed;
                    available = aggAvail;
                } else {
                    try {
                        ResourceAvailability ra = limitsClient.getResourceAvailability(
                                GetResourceAvailabilityRequest.builder()
                                        .compartmentId(compartmentId)
                                        .serviceName(serviceName)
                                        .limitName(limitName)
                                        .build()).getResourceAvailability();
                        used = ra.getUsed() != null ? ra.getUsed() : 0L;
                        available = ra.getAvailable() != null ? ra.getAvailable() : 0L;
                        totalVal = used + available;
                    } catch (Exception ignored) {}
                }

                String displayName = limitName;
                if (limitName.endsWith("-bytes")) {
                    displayName = limitName.replace("-bytes", "-gb");
                    totalVal /= 1073741824L;
                    used /= 1073741824L;
                    available /= 1073741824L;
                }

                Map<String, Object> item = new LinkedHashMap<>();
                item.put("name", displayName);
                item.put("total", totalVal);
                item.put("used", used);
                item.put("available", available);
                items.add(item);
            }

            Map<String, Object> result = new LinkedHashMap<>();
            result.put("items", items);
            result.put("page", (long) page);
            result.put("pageSize", (long) pageSize);
            result.put("hasNextPage", hasNextPage);
            return result;

        } catch (Exception e) {
            log.error("分页获取服务 {} 配额失败: {}", serviceName, e.getMessage(), e);
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("items", new ArrayList<>());
            result.put("page", (long) page);
            result.put("pageSize", (long) pageSize);
            result.put("hasNextPage", false);
            return result;
        }
    }

    /**
     * 针对 AD 级别的配额（如 AMD free tier），跨所有 AD 汇总 total/used/available。
     * 某些限额（例如 vm-standard-e2-1-micro-count）在不传 availabilityDomain 时 OCI 返回 400，
     * 必须逐 AD 查询后累加。
     *
     * @return Map 包含 "total"、"used"、"available"，若全部失败则三项均为 0
     */
    public static Map<String, Long> getAggregatedAvailability(Tenant tenant, String serviceName, String limitName) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        long totalUsed = 0L, totalAvailable = 0L;
        try (IdentityClient identityClient = IdentityClient.builder().build(provider);
             LimitsClient limitsClient = LimitsClient.builder().build(provider)) {

            List<AvailabilityDomain> ads = identityClient.listAvailabilityDomains(
                    ListAvailabilityDomainsRequest.builder()
                            .compartmentId(provider.getTenantId())
                            .build()).getItems();

            for (AvailabilityDomain ad : ads) {
                try {
                    GetResourceAvailabilityRequest req = GetResourceAvailabilityRequest.builder()
                            .compartmentId(provider.getTenantId())
                            .serviceName(serviceName)
                            .limitName(limitName)
                            .availabilityDomain(ad.getName())
                            .build();
                    ResourceAvailability avail = limitsClient.getResourceAvailability(req).getResourceAvailability();
                    if (avail.getUsed() != null) totalUsed += avail.getUsed();
                    if (avail.getAvailable() != null) totalAvailable += avail.getAvailable();
                } catch (Exception e) {
                    log.warn("查询 AD [{}] 资源 [{}] 可用性失败: {}", ad.getName(), limitName, e.getMessage());
                }
            }
        } catch (Exception e) {
            log.error("聚合查询资源 [{}] 可用性失败: {}", limitName, e.getMessage());
        }
        Map<String, Long> result = new HashMap<>();
        result.put("total", totalUsed + totalAvailable);
        result.put("used", totalUsed);
        result.put("available", totalAvailable);
        return result;
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
