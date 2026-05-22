package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociserver.pojo.request.CostQueryRequest;
import com.doubledimple.ociserver.pojo.response.CloudCostItem;
import com.doubledimple.ocicommon.param.ApiResponse;

import java.util.List;

public interface CloudBusinessService {


    ApiResponse queryDailyCost(CostQueryRequest costQueryRequest);


}
