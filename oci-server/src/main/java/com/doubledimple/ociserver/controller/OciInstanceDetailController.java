package com.doubledimple.ociserver.controller;

import cn.hutool.json.JSONUtil;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.pojo.response.InstanceDetailsRes;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;

import javax.annotation.Resource;

/**
 * api的实例详情页面
 * @author doubleDimple
 * @date 2024:11:10日 00:46
 */
@Controller
@RequestMapping("/instanceDetail")
@Slf4j
public class OciInstanceDetailController  extends BaseController{


    @Resource
    OracleInstanceService oracleInstanceService;


    /**
    * @Description: 查询某个api实例下的实例列表
    * @Param: [java.lang.String, int, int, org.springframework.ui.Model]
    * @return: java.lang.String
    * @Author doubleDimple
    * @Date: 2/22/25 10:19 AM
    */
    @GetMapping("/bootList")
    public String listInstancesPage(
            @RequestParam(required = true) String tenantId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            Model model) {

        Page<InstanceDetailsRes> instancePage = oracleInstanceService.getInstancePageByTenantId(tenantId, page, size);
        log.info("获取到的实例数据: {}", JSONUtil.parse(instancePage.getContent()));

        model.addAttribute("instanceDetailsRes", instancePage.getContent());
        model.addAttribute("currentPage", page);
        model.addAttribute("totalPages", instancePage.getTotalPages());
        model.addAttribute("activePage", "api-management");
        model.addAttribute("tenantId", tenantId);

        return "oci_instance_detail";
    }



}
