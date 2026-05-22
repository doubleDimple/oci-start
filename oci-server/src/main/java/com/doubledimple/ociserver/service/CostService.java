package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.CloudTypeEnum;

import java.util.List;

public interface CostService {

    /**
     * 查询昨日费用
     */
    List<?> queryYesterdayCost(Tenant tenant);

    /**
     * 查询本月截至今天的费用
     */
    List<?> queryCurrentMonthCost(Tenant tenant);

    /**
     * 查询上月费用
     */
    List<?> queryLastMonthCost(Tenant tenant);

    /**
     * 自定义日期范围费用
     */
    List<?> queryCustomCost(Tenant tenant, String start, String end);


    CloudTypeEnum getCloudType();

    List<?> queryCurrentMonthCostSimple(Tenant tenant);
}
