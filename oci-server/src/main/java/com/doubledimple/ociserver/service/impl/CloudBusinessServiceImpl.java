package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ocicommon.enums.CloudTypeEnum;
import com.doubledimple.ociserver.pojo.request.CostQueryRequest;
import com.doubledimple.ociserver.pojo.response.CloudCostItem;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.CloudBusinessService;
import com.doubledimple.ociserver.service.CostService;
import com.doubledimple.ociserver.service.factory.CloudCostServiceFactory;
import com.oracle.bmc.usageapi.model.UsageSummary;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/**
 * @version 1.0.0
 * @ClassName CloudBusinessServiceImpl
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-11-30 09:52
 */
@Service
@Slf4j
public class CloudBusinessServiceImpl implements CloudBusinessService {

    @Resource
    private CloudCostServiceFactory cloudCostServiceFactory;

    @Resource
    private TenantRepository tenantRepository;

    @Override
    public ApiResponse queryDailyCost(CostQueryRequest costQueryRequest) {

        Tenant tenant = tenantRepository.findById(Long.valueOf(costQueryRequest.getTenantId()))
                .orElseThrow(() -> new RuntimeException("未找到对应租户"));

        CloudTypeEnum cloudTypeEnum = CloudTypeEnum.getCloudTypeEnum(tenant.getCloudType());
        if (cloudTypeEnum == null) {
            log.warn("未找到对应云厂商: {}", tenant.getCloudType());
            return ApiResponse.success(Collections.emptyList());
        }
        CostService costService = cloudCostServiceFactory.get(cloudTypeEnum);
        if (costService == null) {
            log.warn("未找到对应云厂商的成本服务: {}", tenant.getCloudType());
            return ApiResponse.success(Collections.emptyList());
        }

        List<?> rawList = costService.queryCustomCost(tenant, costQueryRequest.getStartDate(), costQueryRequest.getEndDate());
        return ApiResponse.success(convertRawList(rawList, cloudTypeEnum));
    }

    /**
     * 将不同云厂商底层返回格式，统一转为 CloudCostItem
     */
    private List<CloudCostItem> convertRawList(List<?> rawList, CloudTypeEnum cloudTypeEnum) {

        List<CloudCostItem> result = new ArrayList<>();

        switch (cloudTypeEnum) {

            case ORACLE_CLOUD:
                convertOci(rawList, result);
                break;

            case GOOGLE_CLOUD:
                // convertAws(rawList, result);
                break;

            case AZURE_CLOUD:
                // convertTencent(rawList, result);
                break;
            case AMAZON_CLOUD:
                // convertTencent(rawList, result);
                break;

            default:
                log.warn("未实现的云厂商类型: {}", cloudTypeEnum);
        }
        result.sort(Comparator.comparing(item ->
                LocalDate.parse(item.getDay(), DateTimeFormatter.ofPattern("yyyy-MM-dd"))
        ));
        return result;
    }

    @SuppressWarnings("unchecked")
    private void convertOci(List<?> rawList, List<CloudCostItem> result) {

        for (UsageSummary u : (List<UsageSummary>) rawList) {

            CloudCostItem item = new CloudCostItem();

            item.setCloudType(CloudTypeEnum.ORACLE_CLOUD.getType());
            item.setResourceId(u.getResourceId());
            item.setResourceType(detectResourceTypeById(u.getResourceId()));
            item.setSkuName(u.getSkuName());

            // 格式化 yyyy-MM-dd
            String date = u.getTimeUsageStarted()
                    .toInstant()
                    .atZone(ZoneId.of("UTC"))
                    .toLocalDate()
                    .toString();

            item.setDay(date);
            item.setCost(
                    u.getComputedAmount() == null
                            ? BigDecimal.ZERO
                            : u.getComputedAmount()
            );

            result.add(item);
        }
    }

    private String detectResourceTypeById(String resourceId) {
        if (resourceId == null) return "unknown";

        if (resourceId.startsWith("ocid1.instance")) return "instance";
        if (resourceId.startsWith("ocid1.bootvolume")) return "boot-volume";
        if (resourceId.startsWith("ocid1.volume")) return "block-volume";
        if (resourceId.startsWith("ocid1.vnic")) return "vnic";
        if (resourceId.startsWith("ocid1.vcn")) return "vcn";
        if (resourceId.startsWith("ocid1.loadbalancer")) return "load-balancer";

        // 监控类（非 OCID）
        if (resourceId.contains("health")) return "monitoring";
        if (resourceId.contains("monitoring")) return "monitoring";

        return "other";
    }
}
