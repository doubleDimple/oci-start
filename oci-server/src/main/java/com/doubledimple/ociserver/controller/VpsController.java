package com.doubledimple.ociserver.controller;

import cn.hutool.json.JSONUtil;
import com.doubledimple.ociserver.pojo.response.InstanceDetailsRes;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.utils.PingUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;

import static com.doubledimple.ociserver.utils.DesktopUtils.isMobileRequest;

/**
 * @version 1.0.0
 * @ClassName VpsController
 * @Description TODO
 * @Author renyx
 * @Date 2025-09-14 16:22
 */
@Controller
@RequestMapping("/vps/instances")
@Slf4j
public class VpsController extends BaseController{


    @Resource
    OracleInstanceService oracleInstanceService;

    @GetMapping("/list")
    public String listUsers(@RequestParam(defaultValue = "1000") int size,
                            @RequestParam(defaultValue = "0") int page,
                            @RequestParam(required = false) String tenantId,
                            HttpServletRequest request,
                            Model model) {
        Page<InstanceDetailsRes> userPage;
        int adjustedPage = page;
        userPage = oracleInstanceService.getAllInstances(page, size,tenantId);


        log.debug("oci 获取到的数据是:{}", JSONUtil.parse(userPage.getContent()));
        model.addAttribute("instanceDetailsRes", userPage.getContent());
        model.addAttribute("currentPage", adjustedPage); // 当前页码
        model.addAttribute("totalPages", userPage.getTotalPages()); // 总页数
        model.addAttribute("totalElements", userPage.getTotalElements()); // 总记录数
        model.addAttribute("size", size); // 每页大小
        model.addAttribute("activePage", "vps-instances");

        // 将instanceId添加到模型中，以便在前端页面使用
        if (tenantId != null) {
            model.addAttribute("selectedInstanceId", tenantId);
        }

        return "vps_list";
    }

    /**
    * @Description: 批量启用ping测试
    * @Param: []
    * @return: com.doubledimple.ociserver.pojo.response.base.ApiResponse
    * @Author: doubelemple
    * @Date: 9/21/25 4:22 PM
    */
    @PostMapping("enablePing")
    @ResponseBody
    public ApiResponse enablePing() {
        return oracleInstanceService.enablePing(1);
    }

    /**
    * @Description: 批量停用ping 测试
    * @Param: []
    * @return: com.doubledimple.ociserver.pojo.response.base.ApiResponse
    * @Author: doubleDimple
    * @Date: 9/21/25 4:23 PM
    */
    @PostMapping("disablePing")
    @ResponseBody
    public ApiResponse disablePing() {
        return oracleInstanceService.disablePing(1);
    }

    //手动批量ping测试
    @PostMapping("ping")
    @ResponseBody
    public ApiResponse ping() {
        return oracleInstanceService.batchPing(1);
    }

    //根据ip获取金纬度
    @PostMapping("getLatLon")
    @ResponseBody
    public ApiResponse getLatLon(String ip) {
        double[] latLonByGeoIP = PingUtil.getLatLonByGeoIP(ip);
        return ApiResponse.success(latLonByGeoIP);
    }
}
