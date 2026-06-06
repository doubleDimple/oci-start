package com.doubledimple.ociserver.controller;

import cn.hutool.json.JSONUtil;
import com.doubledimple.dao.entity.CloudSshConn;
import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.CloudSshConnRepository;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ociserver.pojo.request.DDRequest;
import com.doubledimple.ociserver.pojo.request.SysImageBackupRequest;
import com.doubledimple.ociserver.service.QuickDdService;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.pojo.request.IpSwitchRequest;
import com.doubledimple.ociserver.pojo.request.ServerMetricsDTO;
import com.doubledimple.ociserver.pojo.request.UpdateConfigRequest;
import com.doubledimple.ociserver.pojo.request.UpdateNameRequest;
import com.doubledimple.ociserver.pojo.request.UpdateRemarkRequest;
import com.doubledimple.ociserver.pojo.request.UpdateVolumeDefRequest;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.pojo.response.InstanceDetailsRes;
import com.doubledimple.ociserver.service.MetricsService;
import com.doubledimple.ociserver.service.VerifyService;
import com.oracle.bmc.core.ComputeClient;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.data.domain.Page;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.*;

import static com.doubledimple.ociserver.utils.DesktopUtils.isMobileRequest;


/**
 * @author doubleDimple
 * @date 2024:11:10日 00:46
 */
@Controller
@RequestMapping("/oci")
@Slf4j
public class OciController  extends BaseController{


    @Resource
    OracleInstanceService oracleInstanceService;

    @Resource
    MetricsService metricsService;

    @Resource
    VerifyService verifyService;

    @Resource
    CloudSshConnRepository cloudSshConnRepository;

    @Resource
    QuickDdService quickDdService;

    @Resource
    OracleInstanceDetailRepository oracleInstanceDetailRepository;

    @Resource
    TenantRepository tenantRepository;

    @GetMapping("/list")
    public String listUsers(@RequestParam(defaultValue = "10") int size,
                            @RequestParam(defaultValue = "0") int page,
                            @RequestParam(required = false) String tenantId,
                            HttpServletRequest request,
                            Model model) {
        Page<InstanceDetailsRes> userPage;
        int adjustedPage = page;
        userPage = oracleInstanceService.getAllInstances(page, size,tenantId);


        log.debug("oci 获取到的数据是:{}", JSONUtil.parse(userPage.getContent()));
        model.addAttribute("instanceDetailsRes", userPage.getContent());
        model.addAttribute("currentPage", adjustedPage);
        model.addAttribute("totalPages", userPage.getTotalPages());
        model.addAttribute("totalElements", userPage.getTotalElements());
        model.addAttribute("size", size);
        model.addAttribute("activePage", "api-ociMachineList");
        if (tenantId != null) {
            model.addAttribute("selectedInstanceId", tenantId);
        }
        return "oci_machine_list";

    }

    @GetMapping("/list/json")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> listJson(
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(required = false) String tenantId) {
        Page<InstanceDetailsRes> userPage = oracleInstanceService.getAllInstances(page, size, tenantId);
        Map<String, Object> result = new HashMap<>();
        result.put("content", userPage.getContent());
        result.put("currentPage", page);
        result.put("totalPages", userPage.getTotalPages());
        result.put("totalElements", userPage.getTotalElements());
        result.put("size", size);
        return ResponseEntity.ok(result);
    }

    /**
     * 一键导出所有租户所有实例(含明文 Root 密码),按租户分组的纯文本文件。
     * 调用方需在前端给出强警告确认。
     */
    @GetMapping("/export")
    @ResponseBody
    public ResponseEntity<byte[]> exportInstances() {
        Map<Long, Tenant> tenantMap = new HashMap<>();
        for (Tenant t : tenantRepository.findAll()) {
            tenantMap.put(t.getId(), t);
        }

        List<InstanceDetails> instances = oracleInstanceDetailRepository.findAll();

        Map<Long, List<InstanceDetails>> grouped = new LinkedHashMap<>();
        for (InstanceDetails ins : instances) {
            grouped.computeIfAbsent(ins.getTenantId(), k -> new ArrayList<InstanceDetails>()).add(ins);
        }

        SimpleDateFormat ts = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
        SimpleDateFormat fts = new SimpleDateFormat("yyyyMMdd-HHmmss");
        Date now = new Date();

        StringBuilder sb = new StringBuilder(8192);
        sb.append("# OCI 实例导出\n");
        sb.append("# 导出时间: ").append(ts.format(now)).append("\n");
        sb.append("# 实例总数: ").append(instances.size()).append("\n");
        sb.append("# 租户总数: ").append(grouped.size()).append("\n");
        sb.append("# 提示: 文件含明文 Root 密码,请妥善保管,使用后建议删除\n");
        sb.append("\n");

        int tIdx = 1;
        for (Map.Entry<Long, List<InstanceDetails>> e : grouped.entrySet()) {
            Tenant t = tenantMap.get(e.getKey());
            String tenancyName = (t != null && StringUtils.isNotBlank(t.getTenancyName())) ? t.getTenancyName() : "(unknown)";
            String userName = (t != null) ? t.getUserName() : null;
            String region = (t != null) ? t.getRegion() : null;

            sb.append("================================================================\n");
            sb.append("租户 #").append(tIdx++).append(": ").append(tenancyName);
            if (StringUtils.isNotBlank(userName)) {
                sb.append(" / 用户: ").append(userName);
            }
            if (StringUtils.isNotBlank(region)) {
                sb.append(" / 区域: ").append(region);
            }
            sb.append(" (共 ").append(e.getValue().size()).append(" 台)\n");
            sb.append("================================================================\n");

            int iIdx = 1;
            for (InstanceDetails ins : e.getValue()) {
                sb.append("\n[").append(iIdx++).append("] ").append(dash(ins.getDisplayName())).append("\n");
                if (StringUtils.isNotBlank(ins.getRemark())) {
                    sb.append("  备注:      ").append(ins.getRemark()).append("\n");
                }
                sb.append("  状态:      ").append(dash(ins.getState())).append("\n");
                sb.append("  架构:      ").append(dash(ins.getArchitecture())).append("\n");
                sb.append("  CPU/MEM:   ").append(ins.getOcpus() != null ? ins.getOcpus() : "-").append("C")
                        .append(ins.getMemoryInGBs() != null ? ins.getMemoryInGBs() : "-").append("G\n");
                sb.append("  磁盘/VPU:  ").append(ins.getBootVolumeSizeInGBs() != null ? ins.getBootVolumeSizeInGBs() : "-")
                        .append("GB / ").append(dash(ins.getVpusPerGB())).append("\n");
                sb.append("  IPv4:      ").append(dash(ins.getPublicIps())).append("\n");
                sb.append("  Private:   ").append(dash(ins.getPrivateIps())).append("\n");
                if (StringUtils.isNotBlank(ins.getIpv6Addresses())) {
                    sb.append("  IPv6:      ").append(ins.getIpv6Addresses()).append("\n");
                }
                sb.append("  AD:        ").append(dash(ins.getAvailabilityDomain())).append("\n");
                sb.append("  SSH 用户:  ").append(StringUtils.isNotBlank(ins.getUsername()) ? ins.getUsername() : "root").append("\n");
                sb.append("  SSH 端口:  ").append(ins.getPort() != null ? ins.getPort() : 22).append("\n");
                sb.append("  Root 密码: ").append(StringUtils.isNotBlank(ins.getPassword()) ? ins.getPassword() : "(未设置)").append("\n");
                if (ins.getCreateTime() != null) {
                    sb.append("  创建时间:  ").append(ts.format(ins.getCreateTime())).append("\n");
                }
            }
            sb.append("\n");
        }

        byte[] body = sb.toString().getBytes(StandardCharsets.UTF_8);
        String filename = "oci-instances-" + fts.format(now) + ".txt";

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.parseMediaType("text/plain; charset=utf-8"));
        headers.setContentDispositionFormData("attachment", filename);
        headers.setContentLength(body.length);
        return new ResponseEntity<>(body, headers, 200);
    }

    private static String dash(String s) {
        return StringUtils.isBlank(s) ? "-" : s;
    }

    /**
     * 显示SSH终端页面
     * @param instanceId 实例ID
     */
    @GetMapping("/terminal")
    public String showTerminal(@RequestParam String instanceId, Model model) {
        // 获取实例详情
        InstanceDetails instanceByInstanceId = oracleInstanceService.getInstanceById(Long.valueOf(instanceId));
        if (instanceByInstanceId == null) {
            throw new RuntimeException("实例不存在");
        }

        // 添加实例信息到模型
        model.addAttribute("instance", instanceByInstanceId);
            model.addAttribute("instanceId", instanceId);
        model.addAttribute("instanceIp", instanceByInstanceId.getPublicIps());  // 公网IP
        model.addAttribute("instanceName", instanceByInstanceId.getDisplayName());  // 实例名称

        // 设置侧边栏激活菜单
        model.addAttribute("activePage", "api-management");

        return "ssh_terminal";
    }
    /**
    * @Description: 实例救援页面
    * @Param: [java.lang.String, org.springframework.ui.Model]
    * @return: java.lang.String
    * @Author doubleDimple
    * @Date: 4/16/25 2:51 PM
    */
    @GetMapping("/sysHelp")
    public String sysHelp(@RequestParam String instanceId, Model model) {
        // 获取实例详情
        InstanceDetails instanceByInstanceId = oracleInstanceService.getInstanceById(Long.valueOf(instanceId));
        if (instanceByInstanceId == null) {
            throw new RuntimeException("实例不存在");
        }

        // 添加实例信息到模型
        model.addAttribute("instance", instanceByInstanceId);
        model.addAttribute("instanceId", instanceId);
        model.addAttribute("instanceIp", instanceByInstanceId.getPublicIps());  // 公网IP
        model.addAttribute("instanceName", instanceByInstanceId.getDisplayName());  // 实例名称

        // 设置侧边栏激活菜单
        model.addAttribute("activePage", "api-management");

        return "sys_help";
    }

    @GetMapping("/metricsPage")
    public String metricsPage(Model model) {
        List<ServerMetricsDTO> servers = metricsService.getAllServerMetrics();
        model.addAttribute("servers", servers);
        model.addAttribute("activePage", "api-metricsPage");
        return "metrics_page2";
    }

    @GetMapping("/changeIp")
    public ResponseEntity<?> changeIp(@RequestParam("tenantId") Long instanceDetailId){
        return oracleInstanceService.changePublicIp(instanceDetailId);
    }


    @PostMapping("/changeSpecIp")
    public ResponseEntity<?> changeSpecIp(@RequestBody IpSwitchRequest ipSwitchRequest){
        return oracleInstanceService.switchToSpecificIpRange(ipSwitchRequest);
    }


    /**
    * 系统备份
    */
    @PostMapping("/sysImageBackUp")
    public ResponseEntity<?> sysImageBackUp(@RequestBody SysImageBackupRequest sysImageBackupRequest){
        return oracleInstanceService.sysImageBackUp(sysImageBackupRequest);
    }


    @PostMapping("/enableIpv6")
    @ResponseBody
    public Map<String, Object> enableIpv6(@RequestBody Map<String, String> requestBody) {
        Map<String, Object> result = new HashMap<>();
        Long tenantId = Long.valueOf(requestBody.get("tenantId"));

        try {
            //String ipv6Address = oracleInstanceService.enableIpv6(tenantId);
            String ipv6Address = oracleInstanceService.enableOrRefreshIpv6(tenantId,true);
            result.put("status", "success");
            result.put("message", "IPv6开启成功");

            Map<String, String> details = new HashMap<>();
            details.put("ipv6Address", ipv6Address);
            result.put("details", details);
        } catch (Exception e) {
            result.put("status", "error");
            result.put("message", "IPv6开启失败: " + e.getMessage());
        }
        return result;

    }


    /**
     * 生成并发送验证码
     */
    @PostMapping("/sendVerificationCode")
    public ResponseEntity<Map<String, Object>> sendVerificationCode(@RequestBody Map<String, String> request) {
        Map<String, Object> response = new HashMap<>();

        try {
            String instanceId = request.get("instanceId");
            if (instanceId == null || instanceId.trim().isEmpty()) {
                throw new IllegalArgumentException("实例ID不能为空");
            }
            verifyService.sendVerifyCodeForInstance(instanceId);
            response.put("success", true);
            response.put("message", "验证码已发送");
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("发送验证码失败", e);
            response.put("success", false);
            response.put("message", "发送验证码失败: " + e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }

    /**
     * 验证码校验并终止实例
     */
    @PostMapping("/terminateInstance")
    public ResponseEntity<Map<String, Object>> terminateInstance(@RequestBody Map<String, String> request) {
        Map<String, Object> response = new HashMap<>();
        ComputeClient computeClient = null;

        try {
            String instanceId = request.get("instanceId");
            String verificationCode = request.get("verificationCode");

            if (instanceId == null || verificationCode == null) {
                throw new IllegalArgumentException("实例ID和验证码不能为空");
            }

            verifyService.checkCodeForInstance(instanceId,verificationCode);

            //调用service终止实例
            oracleInstanceService.killInstance(Long.valueOf(instanceId));

            // 记录操作日志
            log.debug("成功发送终止实例请求，实例ID: {}", instanceId);

            response.put("success", true);
            response.put("message", "实例终止请求已发送");

            return ResponseEntity.ok(response);

        } catch (IllegalArgumentException | IllegalStateException e) {
            log.warn("终止实例参数验证失败: {}", e.getMessage());
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);

        } catch (Exception e) {
            log.error("终止实例失败", e);
            response.put("success", false);
            response.put("message", "终止实例失败: " + e.getMessage());
            return ResponseEntity.badRequest().body(response);

        }
    }

    @PostMapping("/updateConfig")
    public ResponseEntity<ApiResponse> updateInstanceConfig(@RequestBody UpdateConfigRequest request) {
        try {
            // 参数验证
            if (request.getCpu() == null || request.getMemory() == null || request.getInstanceId() == null) {
                return ResponseEntity.badRequest()
                        .body(ApiResponse.error("参数不完整"));
            }

            // 验证值范围
            if (request.getCpu() < 1 || request.getCpu() > 24) {
                return ResponseEntity.badRequest()
                        .body(ApiResponse.error("CPU核心数必须在1-24之间"));
            }
            if (request.getMemory() < 1 || request.getMemory() > 256) {
                return ResponseEntity.badRequest()
                        .body(ApiResponse.error("内存大小必须在1-256GB之间"));
            }

            // 调用服务层进行配置更新
            oracleInstanceService.updateInstanceConfig(
                    request.getInstanceId(),
                    request.getCpu(),
                    request.getMemory()
            );

            return ResponseEntity.ok(ApiResponse.success("实例配置更新成功"));
        } catch (IllegalArgumentException e) {
            log.error("Invalid request parameters", e);
            return ResponseEntity.badRequest()
                    .body(ApiResponse.error(e.getMessage()));
        } catch (Exception e) {
            log.error("Failed to update instance configuration", e);
            return ResponseEntity.internalServerError()
                    .body(ApiResponse.error("配置更新失败：" + e.getMessage()));
        }
    }


    /**
    * @Description: 修改实例名称
    * @Param: [com.doubledimple.ociserver.request.UpdateNameRequest]
    * @return: org.springframework.http.ResponseEntity<java.util.Map<java.lang.String,java.lang.Object>>
    * @Author doubleDimple
    * @Date: 2/16/25 11:42 AM
    */
    @PostMapping("/updateName")
    public ResponseEntity<Map<String, Object>> updateInstanceName(@RequestBody UpdateNameRequest request) {
        Map<String, Object> response = new HashMap<>();

        try {
            if (StringUtils.isBlank(request.getInstanceId()) || StringUtils.isBlank(request.getNewName())) {
                response.put("success", false);
                response.put("message", "实例ID和新名称不能为空");
                return ResponseEntity.ok(response);
            }

            // 调用服务更新实例名称
            boolean updated = oracleInstanceService.updateInstanceName(request.getInstanceId(), request.getNewName());

            if (updated) {
                response.put("success", true);
                response.put("message", "实例名称更新成功");
            } else {
                response.put("success", false);
                response.put("message", "实例名称更新失败");
            }
        } catch (Exception e) {
            log.error("更新实例名称时发生错误", e);
            response.put("success", false);
            response.put("message", "系统错误：" + e.getMessage());
        }

        return ResponseEntity.ok(response);
    }

    /**
    * @Description: 引导卷进行修改
    * @Param: [UpdateBootVolumeRequest]
    * @return: org.springframework.http.ResponseEntity<?>
    * @Author: doubleDimple
    * @Date: 11/26/24 6:49 PM
    */
    @PostMapping("/updateBootVolume")
    public ResponseEntity<ApiResponse> updateBootVolume(@RequestBody UpdateVolumeDefRequest request) {
        try {
            // 参数验证
            if (request.getBootVolumeSize() < 47l) {
                return ResponseEntity.badRequest()
                        .body(ApiResponse.builder().success(false).message("引导卷大小不能小于47GB").build()
                );
            }
            if (request.isExpand()) {
                // 扩容逻辑
                return oracleInstanceService.handleExpansion(request.getInstanceId(), request.getBootVolumeSize());
            } else {
                // 缩小逻辑
                //return oracleInstanceService.handleShrink(request.getInstanceId(), request.getBootVolumeSize());
                return ResponseEntity.internalServerError()
                        .body(ApiResponse.builder().success(false).message("暂不支持引导卷缩小更改").build());

                /*ApiResponse apiResponse = bootVolumeService.handleShrink(request.getInstanceId(), request.getBootVolumeSize());
                return ResponseEntity.ok(apiResponse);*/

            }

        } catch (Exception e) {
            log.error("更新引导卷失败", e);
            return ResponseEntity.internalServerError()
                    .body(ApiResponse.builder().success(false).message("更新引导卷失败"+e.getMessage()).build());
        }
    }

    @PostMapping("/updateRemark")
    @ResponseBody
    public Map<String, Object> updateRemark(@RequestBody UpdateRemarkRequest request) {
        Map<String, Object> result = new HashMap<>();
        try {
            oracleInstanceService.updateRemark(request.getInstanceId(), request.getRemark());
            result.put("success", true);
            result.put("message", "备注更新成功");
        } catch (Exception e) {
            log.error("更新备注失败", e);
            result.put("success", false);
            result.put("message", "更新备注失败：" + e.getMessage());
        }
        return result;
    }

    /**
     * @Description: 启动实例
     * @Param: [requestBody]
     * @return: java.util.Map<java.lang.String,java.lang.Object>
     * @Author: doubleDimple
     * @Date: 3/14/25
     */
    @PostMapping("/startInstance")
    @ResponseBody
    public Map<String, Object> startInstance(@RequestBody Map<String, String> requestBody) {
        Map<String, Object> result = new HashMap<>();

        try {
            String instanceId = requestBody.get("instanceId");
            if (StringUtils.isBlank(instanceId)) {
                result.put("success", false);
                result.put("message", "实例ID不能为空");
                return result;
            }

            // 调用服务启动实例
            boolean success = oracleInstanceService.startInstance(instanceId);

            if (success) {
                result.put("success", true);
                result.put("message", "实例启动请求已发送，请稍后刷新查看状态");
            } else {
                result.put("success", false);
                result.put("message", "实例启动失败");
            }
        } catch (Exception e) {
            log.error("启动实例失败", e);
            result.put("success", false);
            result.put("message", "启动实例失败: " + e.getMessage());
        }

        return result;
    }

    /**
     * @Description: 停止实例
     * @Param: [requestBody]
     * @return: java.util.Map<java.lang.String,java.lang.Object>
     * @Author: doubleDimple
     * @Date: 3/14/25
     */
    @PostMapping("/stopInstance")
    @ResponseBody
    public Map<String, Object> stopInstance(@RequestBody Map<String, String> requestBody) {
        Map<String, Object> result = new HashMap<>();

        try {
            String instanceId = requestBody.get("instanceId");
            if (StringUtils.isBlank(instanceId)) {
                result.put("success", false);
                result.put("message", "实例ID不能为空");
                return result;
            }

            // 调用服务停止实例
            boolean success = oracleInstanceService.stopInstanceByInstanceId(instanceId);

            if (success) {
                result.put("success", true);
                result.put("message", "实例停止请求已发送，请稍后刷新查看状态");
            } else {
                result.put("success", false);
                result.put("message", "实例停止失败");
            }
        } catch (Exception e) {
            log.error("停止实例失败", e);
            result.put("success", false);
            result.put("message", "停止实例失败: " + e.getMessage());
        }

        return result;
    }

    /**
     * 保存或更新SSH连接配置
     */
    @PostMapping("/ssh/config")
    @ResponseBody
    public ApiResponse saveSshConfig(@RequestBody Map<String, Object> request) {
        try {
            // 基本参数验证
            String id = (String) request.get("instanceId");
            String username = (String) request.get("username");
            String port = (String) request.get("port");
            String password = (String) request.get("password");
            Integer portNew = Integer.valueOf(port);
            if (StringUtils.isBlank(id)) {
                return ApiResponse.error("实例ID不能为空");
            }
            if (StringUtils.isBlank(username)) {
                return ApiResponse.error("用户名不能为空");
            }
            if (portNew == null || portNew < 1 || portNew > 65535) {
                return ApiResponse.error("端口号无效");
            }

            // 更新实例详情
            InstanceDetails instance = oracleInstanceService.getInstanceById(Long.valueOf(id));
            if (instance == null) {
                return ApiResponse.error("未找到实例信息");
            }

            instance.setUsername(username);
            instance.setPort(portNew);
            instance.setPassword(password);
            oracleInstanceService.updateInstance(instance);

            return ApiResponse.builder()
                    .success(true)
                    .message("SSH配置保存成功")
                    .data(instance)
                    .build();

        } catch (Exception e) {
            log.error("保存SSH配置失败", e);
            return ApiResponse.error("保存SSH配置失败：" + e.getMessage());
        }
    }

    /**
     * 获取SSH连接配置
     */
    @GetMapping("/ssh/config/{instanceId}")
    @ResponseBody
    public ApiResponse getSshConfig(@PathVariable String instanceId) {
        try {
            if (StringUtils.isBlank(instanceId)) {
                return ApiResponse.error("实例ID不能为空");
            }

            InstanceDetails instance = oracleInstanceService.getInstanceById(Long.valueOf(instanceId));
            if (instance == null) {
                return ApiResponse.builder().success(true).message("未找到配置").data(null).build();
            }
            Optional<CloudSshConn> byInstanceId = cloudSshConnRepository.findByInstanceId(instance.getInstanceId());
            Map<String, Object> sshConfig = new HashMap<>();
            if (byInstanceId.isPresent()){
                // 构建返回数据
                String publicIps = instance.getPublicIps();
                CloudSshConn cloudSshConn = byInstanceId.get();
                sshConfig.put("username", cloudSshConn.getUsername());
                sshConfig.put("port", cloudSshConn.getPort());
                sshConfig.put("sshPassword", cloudSshConn.getPassword());
                sshConfig.put("host", publicIps);
                return ApiResponse.builder().success(true).message("获取配置成功").data(sshConfig).build();
            }else {
                return ApiResponse.error("获取SSH配置失败：请重新设置密码");
            }
        } catch (Exception e) {
            log.error("获取SSH配置失败", e);
            return ApiResponse.error("获取SSH配置失败：" + e.getMessage());
        }
    }

    @PostMapping("/instance/quickDD2")
    @ResponseBody
    public ApiResponse quickDD(@RequestBody DDRequest request) {
        return quickDdService.quickDd(request);
    }

    /**
     * 删除实例本地记录（不操作OCI云端）
     */
    @PostMapping("/deleteInstanceRecord")
    @ResponseBody
    public ApiResponse deleteInstanceRecord(@RequestBody Map<String, Object> body) {
        Long id = Long.valueOf(body.get("id").toString());
        return oracleInstanceService.deleteInstanceRecord(id);
    }

    @GetMapping(value = "/instance/quickDD", produces = "text/event-stream;charset=UTF-8")
    public SseEmitter quickDdSse(DDRequest request, HttpServletResponse resp) {
        // 关闭反向代理缓冲（如 Nginx）
        resp.setHeader("X-Accel-Buffering", "no");
        resp.setHeader("Cache-Control", "no-cache");
        return quickDdService.quickDdSse(request);
    }

}
