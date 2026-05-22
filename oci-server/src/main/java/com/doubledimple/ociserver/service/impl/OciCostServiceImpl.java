package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.CloudTypeEnum;
import com.doubledimple.ociserver.service.CostService;
import com.doubledimple.ociserver.utils.oracle.CostUtils;
import org.springframework.stereotype.Service;

import java.util.List;

/**
 * @version 1.0.0
 * @ClassName OciCostService
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-11-30 08:25
 */
@Service
public class OciCostServiceImpl implements CostService {


    @Override
    public CloudTypeEnum getCloudType() {
        return CloudTypeEnum.ORACLE_CLOUD;
    }

    @Override
    public List<?> queryCurrentMonthCostSimple(Tenant tenant) {
        return CostUtils.queryCurrentMonthCostSimple(tenant);
    }

    @Override
    public List<?> queryYesterdayCost(Tenant tenant) {
        return CostUtils.queryYesterdayCost(tenant);
    }

    @Override
    public List<?> queryCurrentMonthCost(Tenant tenant) {
        return CostUtils.queryCurrentMonthCost(tenant);
    }

    @Override
    public List<?> queryLastMonthCost(Tenant tenant) {
        return CostUtils.queryLastMonthCost(tenant);
    }

    @Override
    public List<?> queryCustomCost(Tenant tenant, String start, String end) {
        return CostUtils.queryCustomCost(tenant, start, end);
    }

}
