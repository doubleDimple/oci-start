package com.doubledimple.ociserver.utils.oracle;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.utils.DateTimeUtils;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.usageapi.UsageapiClient;
import com.oracle.bmc.usageapi.model.RequestSummarizedUsagesDetails;
import com.oracle.bmc.usageapi.model.UsageSummary;
import com.oracle.bmc.usageapi.requests.RequestSummarizedUsagesRequest;
import com.oracle.bmc.usageapi.responses.RequestSummarizedUsagesResponse;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Calendar;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static com.doubledimple.ocicommon.utils.DateTimeUtils.getStartOfToday;
import static com.doubledimple.ocicommon.utils.DateTimeUtils.getStartOfYesterday;

/**
 * @version 2.0
 * @Description Oracle Cloud 成本统计工具（支持昨日、本月、上月、自定义日期、按实例CPU/MEM/DISK）
 * @Author doubleDimple
 */
@Slf4j
public class CostUtils {



    private static final List<String> GROUP_BY_SKU =
            Arrays.asList("resourceId", "skuName");

    private static final List<String> GROUP_BY_SKU_DEFAULT =
            Collections.emptyList();


    // ============================================================
    //                      通用查询函数
    // ============================================================

    /**
     * OCI 通用费用查询
     */
    public static List<UsageSummary> queryCost(
            Tenant tenant,
            Date startUtc,
            Date endUtc,
            List<String> groupBy,
            RequestSummarizedUsagesDetails.Granularity granularity
    ) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);

        if (granularity == null) {
            granularity = RequestSummarizedUsagesDetails.Granularity.Daily;
        }
        try (UsageapiClient client = UsageapiClient.builder().build(provider)) {

            RequestSummarizedUsagesDetails details =
                    RequestSummarizedUsagesDetails.builder()
                            .tenantId(tenant.getTenancy())
                            .timeUsageStarted(startUtc)
                            .timeUsageEnded(endUtc)
                            .granularity(granularity)
                            .groupBy(groupBy)
                            .build();

            RequestSummarizedUsagesRequest request =
                    RequestSummarizedUsagesRequest.builder()
                            .requestSummarizedUsagesDetails(details)
                            .build();

            RequestSummarizedUsagesResponse response = client.requestSummarizedUsages(request);

            if (response == null ||
                    response.getUsageAggregation() == null ||
                    response.getUsageAggregation().getItems() == null) {
                return Collections.emptyList();
            }

            return response.getUsageAggregation().getItems();
        }catch (Exception e){
            log.error("CostUtils queryCost query fail: {}", e.getMessage());
            return Collections.emptyList();
        }
    }

    /** 昨日总费用 */
    public static List<UsageSummary> queryYesterdayCost(Tenant tenant) {
        DateTimeUtils.DateRange range = DateTimeUtils.getYesterdayUtcRange();
        return queryCost(tenant, range.getStartUtc(), range.getEndUtc(), GROUP_BY_SKU,null);
    }

    /** 今日到当前费用 */
    public static List<UsageSummary> queryTodayCost(Tenant tenant) {
        DateTimeUtils.DateRange range = DateTimeUtils.getTodayUtcRange();
        return queryCost(tenant, range.getStartUtc(), range.getEndUtc(), GROUP_BY_SKU,null);
    }

    /** 本月费用（1号~今天） */
    public static List<UsageSummary> queryCurrentMonthCost(Tenant tenant) {
        DateTimeUtils.DateRange range = DateTimeUtils.getCurrentMonthUtcRange();
        return queryCost(tenant, range.getStartUtc(), range.getEndUtc(), GROUP_BY_SKU,RequestSummarizedUsagesDetails.Granularity.Monthly);
    }

    public static List<UsageSummary> queryCurrentMonthCostSimple(Tenant tenant) {
        DateTimeUtils.DateRange range = DateTimeUtils.getCurrentMonthUtcRange();
        return queryCost(tenant, range.getStartUtc(), range.getEndUtc(), GROUP_BY_SKU_DEFAULT,RequestSummarizedUsagesDetails.Granularity.Monthly);
    }

    /** 上月费用（整月） */
    public static List<UsageSummary> queryLastMonthCost(Tenant tenant) {
        DateTimeUtils.DateRange range = DateTimeUtils.getLastMonthUtcRange();
        return queryCost(tenant, range.getStartUtc(), range.getEndUtc(), GROUP_BY_SKU,RequestSummarizedUsagesDetails.Granularity.Monthly);
    }

    /** 自定义区间费用 */
    public static List<UsageSummary> queryCustomCost(Tenant tenant, String startStr, String endStr) {
        DateTimeUtils.DateRange range = DateTimeUtils.getCustomUtcRange(startStr, endStr);
        return queryCost(tenant, range.getStartUtc(), range.getEndUtc(), GROUP_BY_SKU,null);
    }
}
