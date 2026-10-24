package com.doubledimple.ociserver.controller;

import com.doubledimple.ociserver.pojo.request.CostQueryRequest;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.CloudBusinessService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseBody;

import javax.annotation.Resource;

/**
 * @version 1.0.0
 * @ClassName OciCostController
 * @Description TODO
 * @Author renyx
 * @Date 2025-11-30 10:33
 */
@Controller
@RequestMapping("/cost")
@Slf4j
public class OciCostController extends BaseController{

    @Resource
    CloudBusinessService cloudBusinessService;

    //查询账号的花费
    @PostMapping("/query")
    @ResponseBody
    public ApiResponse queryCost(@RequestBody CostQueryRequest costQueryRequest){
        return cloudBusinessService.queryDailyCost(costQueryRequest);
    }
}
