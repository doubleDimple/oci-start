package com.doubledimple.ociserver.controller.db;

import com.doubledimple.ociserver.controller.BaseController;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.DbConfigService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;

import javax.annotation.Resource;
import java.util.Map;

/**
 * @version 1.0.0
 * @ClassName DbController
 * @Description TODO
 * @Author renyx
 * @Date 2026-01-01 07:19
 */
@Slf4j
@Controller
@RequestMapping("/tenants")
public class DbController extends BaseController {


    @Resource
    private DbConfigService dbConfigService;

    /**
     * 获取数据库详细配置信息
     */
    @GetMapping("/mysql-info")
    @ResponseBody
    public ApiResponse getMysqlInfo(@RequestParam("tenantId") Long tenantId) {
        return dbConfigService.findByTenantId(tenantId);
    }

    /**
     * 从 Oracle Cloud 同步拉取数据库实例信息
     */
    @PostMapping("/sync-mysql")
    @ResponseBody
    public ApiResponse syncMysqlFromCloud(@RequestParam("tenantId") Long tenantId) {
        return dbConfigService.syncMysqlFromCloud(tenantId);
    }

    /**
     * 执行数据库操作 (创建/重启/终止)
     */
    @PostMapping("/mysql-create")
    @ResponseBody
    public ApiResponse createMysql(@RequestParam("tenantId") Long tenantId) {
        return dbConfigService.createMysql(tenantId);
    }

    @PostMapping("/sync-single-mysql")
    @ResponseBody
    public ApiResponse syncSingleMysql(@RequestParam("id") Long id) {
        return dbConfigService.syncSingleMysqlFromCloud(id);
    }

    /**
     * 为特定的 MySQL 实例绑定公网 IP
     * @param id db_configs 表的主键 ID
     */
    @PostMapping("/bind-public-ip")
    @ResponseBody
    public ApiResponse bindPublicIp(@RequestParam("id") Long id) {
        return dbConfigService.bindPublicIp(id);
    }

    @PostMapping("/mysql-action")
    @ResponseBody
    public ApiResponse handleMysqlAction(@RequestBody Map<String, Object> payload) {
        return dbConfigService.handleMysqlAction(payload);
    }

    @PostMapping("/mysql-reset-auth")
    @ResponseBody
    public ApiResponse resetMysqlAuth(@RequestParam("id") Long id, @RequestParam("tenantId") Long tenantId) {
        return dbConfigService.resetMysqlAuth(id, tenantId);
    }
}
