package com.doubledimple.ociserver.controller.nginx;

import com.doubledimple.dao.entity.NginxConfig;
import com.doubledimple.dao.entity.ProxyConfig;
import com.doubledimple.dao.entity.SslCertificate;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociserver.controller.BaseController;
import com.doubledimple.ociserver.pojo.request.nginx.CertificateDTO;
import com.doubledimple.ociserver.pojo.request.nginx.ProxyConfigCreateDto;
import com.doubledimple.ociserver.pojo.request.nginx.ProxyConfigUpdateDto;
import com.doubledimple.ociserver.pojo.request.nginx.SslCertificateRequestDto;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.nginx.NginxConfigService;
import com.doubledimple.ociserver.service.nginx.ProxyConfigService;
import com.doubledimple.ociserver.service.nginx.SslCertificateService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;

import javax.servlet.http.HttpServletRequest;
import javax.validation.Valid;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static com.doubledimple.ociserver.utils.DesktopUtils.isMobileRequest;

/**
 * @version 1.0.0
 * @ClassName NginxController
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-09-23 11:28
 */
@Slf4j
@Controller
@RequestMapping("/ssl")
@RequiredArgsConstructor
public class NginxController extends BaseController {

    private final ProxyConfigService proxyConfigService;
    private final SslCertificateService sslCertificateService;
    private final NginxConfigService nginxConfigService;

    /**
     * SSL管理页面
     */
    @GetMapping("/nginx/management")
    public String managementPage(@RequestParam(required = false) Integer cloudType,
                                 HttpServletRequest request,
                                 Model model) {
        model.addAttribute("activePage", "nginx-management");
        return "nginx_config";
    }

    // =================== 反向代理配置API ===================

    /**
     * 创建反向代理配置
     */
    @PostMapping("/proxy/create")
    @ResponseBody
    public ApiResponse createProxy(@Valid @RequestBody ProxyConfigCreateDto dto) {
        try {
            proxyConfigService.createProxyConfig(dto);

            // 自动生成新的Nginx配置
            nginxConfigService.generateNginxConfig();

            return ApiResponse.success("反向代理配置创建成功");
        } catch (Exception e) {
            log.error("创建反向代理配置失败", e);
            return ApiResponse.error("创建代理失败,请稍后再试");
        }
    }

    /**
     * 更新反向代理配置
     */
    @PutMapping("/proxy/{id}")
    @ResponseBody
    public ApiResponse updateProxy(@PathVariable Long id, @Valid @RequestBody ProxyConfigUpdateDto dto) {
        try {
            dto.setId(id);
            ProxyConfig config = proxyConfigService.updateProxyConfig(dto);

            // 自动生成新的Nginx配置
            nginxConfigService.generateNginxConfig();

            return ApiResponse.success("反向代理配置更新成功");
        } catch (Exception e) {
            log.error("更新反向代理配置失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 获取代理配置详情
     */
    @GetMapping("/proxy/{id}")
    @ResponseBody
    public ApiResponse getProxyDetail(@PathVariable Long id) {
        try {
            ProxyConfig config = proxyConfigService.getProxyConfigById(id);
            return ApiResponse.success(config);
        } catch (Exception e) {
            log.error("获取代理配置详情失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 删除反向代理配置
     */
    @DeleteMapping("/proxy/{id}")
    @ResponseBody
    public ApiResponse deleteProxy(@PathVariable Long id) {
        try {
            proxyConfigService.deleteProxyConfig(id);

            // 自动生成新的Nginx配置
            nginxConfigService.generateNginxConfig();

            return ApiResponse.success("反向代理配置删除成功");
        } catch (Exception e) {
            log.error("删除反向代理配置失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 获取反向代理配置列表
     */
    @GetMapping("/proxy/list")
    @ResponseBody
    public ApiResponse getProxyList(@RequestParam(defaultValue = "0") int page,
                                    @RequestParam(defaultValue = "20") int size) {
        try {
            Pageable pageable = PageRequest.of(page, size, Sort.by("createTime").descending());
            Page<ProxyConfig> configs = proxyConfigService.getProxyConfigs(pageable);
            return ApiResponse.success(configs);
        } catch (Exception e) {
            log.error("获取反向代理配置列表失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 批量删除代理配置
     */
    @Transactional
    @DeleteMapping("/proxy/batch")
    @ResponseBody
    public ApiResponse batchDeleteProxy(@RequestBody List<Long> ids) {
        try {
            for (Long id : ids) {
                proxyConfigService.deleteProxyConfig(id);
            }
            nginxConfigService.generateNginxConfig();
            return ApiResponse.success("批量删除成功");
        } catch (Exception e) {
            log.error("批量删除失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 启用/禁用代理配置
     */
    @PutMapping("/proxy/{id}/toggle")
    @ResponseBody
    public ApiResponse toggleProxyConfig(@PathVariable Long id, @RequestBody Map<String, Boolean> request) {
        try {
            Boolean enabled = request.get("enabled");
            proxyConfigService.toggleProxyConfig(id, enabled);
            nginxConfigService.generateNginxConfig();
            return ApiResponse.success(enabled ? "配置已启用" : "配置已禁用");
        } catch (Exception e) {
            log.error("切换配置状态失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 测试代理连接
     */
    @PostMapping("/proxy/{id}/test-connection")
    @ResponseBody
    public ApiResponse testProxyConnection(@PathVariable Long id) {
        try {
            boolean connected = proxyConfigService.testConnection(id);
            if (connected) {
                return ApiResponse.success("连接测试成功");
            } else {
                return ApiResponse.error("无法连接到目标服务器");
            }
        } catch (Exception e) {
            log.error("连接测试失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 应用SSL配置
     */
    @PostMapping("/proxy/{id}/ssl")
    @ResponseBody
    public ApiResponse applySslConfig(@PathVariable Long id, @RequestParam String email) {
        try {
            proxyConfigService.applySslConfig(id, email);
            return ApiResponse.success("SSL配置申请成功");
        } catch (Exception e) {
            log.error("SSL配置失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 修复配置
     */
    @PostMapping("/proxy/{id}/fix")
    @ResponseBody
    public ApiResponse fixProxyConfig(@PathVariable Long id) {
        try {
            proxyConfigService.fixProxyConfig(id);
            return ApiResponse.success("配置修复成功");
        } catch (Exception e) {
            log.error("配置修复失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    // =================== SSL证书管理API ===================

    /**
     * 申请SSL证书
     */
    @PostMapping("/certificates/request")
    @ResponseBody
    public ApiResponse requestCertificate(@Valid @RequestBody SslCertificateRequestDto dto) {
        try {
            SslCertificate certificate = sslCertificateService.requestCertificate(dto);
            return ApiResponse.success("证书申请成功");
        } catch (Exception e) {
            log.error("证书申请失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 续期证书
     */
    @PostMapping("/certificates/{id}/renew")
    @ResponseBody
    public ApiResponse renewCertificate(@PathVariable Long id) {
        try {
            sslCertificateService.renewCertificate(id);
            return ApiResponse.success("证书续期成功");
        } catch (Exception e) {
            log.error("证书续期失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 删除证书
     */
    @DeleteMapping("/certificates/{id}")
    @ResponseBody
    public ApiResponse deleteCertificate(@PathVariable Long id) {
        try {
            sslCertificateService.deleteCertificate(id);
            return ApiResponse.success("证书删除成功");
        } catch (Exception e) {
            log.error("证书删除失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 切换自动续期
     */
    @PutMapping("/certificates/{id}/auto-renew")
    @ResponseBody
    public ApiResponse toggleAutoRenew(@PathVariable Long id, @RequestBody Map<String, Boolean> request) {
        try {
            Boolean enabled = request.get("enabled");
            sslCertificateService.toggleAutoRenew(id, enabled);
            return ApiResponse.success("自动续期设置更新成功");
        } catch (Exception e) {
            log.error("自动续期设置失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 获取证书列表
     */
    @GetMapping("/certificates/list")
    @ResponseBody
    public ApiResponse getCertificateList(@RequestParam(defaultValue = "0") int page,
                                          @RequestParam(defaultValue = "20") int size) {
        try {
            Pageable pageable = PageRequest.of(page, size, Sort.by("createTime").descending());
            Page<SslCertificate> certificates = sslCertificateService.getCertificates(pageable);
            return ApiResponse.success(certificates);
        } catch (Exception e) {
            log.error("获取证书列表失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 检查即将过期的证书
     */
    @GetMapping("/certificates/expiring")
    @ResponseBody
    public ApiResponse checkExpiringCertificates() {
        try {
            List<SslCertificate> expiring = sslCertificateService.checkExpiringCertificates();
            return ApiResponse.success(expiring);
        } catch (Exception e) {
            log.error("检查过期证书失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    // =================== Nginx配置管理API ===================

    /**
     * 生成Nginx配置
     */
    @PostMapping("/nginx/generate")
    @ResponseBody
    public ApiResponse generateNginxConfig() {
        try {
            NginxConfig config = nginxConfigService.generateNginxConfig();
            return ApiResponse.success("配置生成成功");
        } catch (Exception e) {
            log.error("生成Nginx配置失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 应用Nginx配置
     */
    @PostMapping("/nginx/{id}/apply")
    @ResponseBody
    public ApiResponse applyNginxConfig(@PathVariable Long id) {
        try {
            nginxConfigService.applyConfig(id);
            return ApiResponse.success("配置应用成功");
        } catch (Exception e) {
            log.error("应用Nginx配置失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 测试Nginx配置
     */
    @PostMapping("/nginx/{id}/test")
    @ResponseBody
    public ApiResponse testNginxConfig(@PathVariable Long id) {
        try {
            boolean isValid = nginxConfigService.testConfig(id);
            if (isValid) {
                return ApiResponse.success("配置测试通过");
            } else {
                return ApiResponse.error("配置测试失败");
            }
        } catch (Exception e) {
            log.error("测试Nginx配置失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 重载Nginx
     */
    @PostMapping("/nginx/reload")
    @ResponseBody
    public ApiResponse reloadNginx() {
        try {
            nginxConfigService.reloadNginx();
            return ApiResponse.success("Nginx重载成功");
        } catch (Exception e) {
            log.error("Nginx重载失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 获取配置对比
     */
    @GetMapping("/nginx/diff")
    @ResponseBody
    public ApiResponse getConfigDiff() {
        try {
            NginxConfig current = nginxConfigService.getCurrentConfig();
            NginxConfig latest = nginxConfigService.getLatestConfig();

            Map<String, Object> result = new HashMap<>();
            result.put("current", current);
            result.put("latest", latest);
            result.put("diff", nginxConfigService.getConfigDiff());

            return ApiResponse.success(result);
        } catch (Exception e) {
            log.error("获取配置对比失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 获取当前配置状态
     */
    @GetMapping("/nginx/status")
    @ResponseBody
    public ApiResponse getNginxStatus() {
        try {
            NginxConfig current = nginxConfigService.getCurrentConfig();
            NginxConfig latest = nginxConfigService.getLatestConfig();

            Map<String, Object> status = new HashMap<>();
            status.put("hasChanges", latest != null && (current == null || !current.getId().equals(latest.getId())));
            status.put("currentVersion", current != null ? current.getConfigVersion() : 0);
            status.put("latestVersion", latest != null ? latest.getConfigVersion() : 0);

            return ApiResponse.success(status);
        } catch (Exception e) {
            log.error("获取Nginx状态失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 检查OpenResty安装状态
     */
    @GetMapping("/openresty/status")
    @ResponseBody
    public ApiResponse checkOpenRestyStatus() {
        try {
            Map<String, Object> status = nginxConfigService.checkOpenRestyStatus();
            return ApiResponse.success(status);
        } catch (Exception e) {
            log.error("检查OpenResty状态失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 启动OpenResty服务
     */
    @PostMapping("/openresty/start")
    @ResponseBody
    public ApiResponse startOpenResty() {
        try {
            nginxConfigService.startOpenRestyService();
            return ApiResponse.success("OpenResty服务启动成功");
        } catch (Exception e) {
            log.error("启动OpenResty失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 获取最新配置
     */
    @GetMapping("/nginx/latest")
    @ResponseBody
    public ApiResponse getLatestNginxConfig() {
        try {
            NginxConfig latest = nginxConfigService.getLatestConfig();
            return ApiResponse.success(latest);
        } catch (Exception e) {
            log.error("获取最新配置失败", e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * 下载证书
     */
    @GetMapping("/certificates/{id}/download")
    public ResponseEntity<byte[]> downloadCertificate(@PathVariable Long id) {
        try {
            Map<String, Object> result = sslCertificateService.downloadCertificate(id);

            byte[] content = (byte[]) result.get("content");
            String fileName = (String) result.get("fileName");

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_OCTET_STREAM);
            headers.setContentDispositionFormData("attachment", fileName);
            headers.setContentLength(content.length);

            return ResponseEntity.ok()
                    .headers(headers)
                    .body(content);

        } catch (Exception e) {
            log.error("证书下载失败", e);
            return ResponseEntity.badRequest().build();
        }
    }

    /**
     * 根据域名匹配证书列表
     * @param domain 域名
     * @return 匹配的证书列表
     */
    @GetMapping("/certificates/match")
    @ResponseBody
    public ApiResponse match(@RequestParam String domain) {
        try {
            List<CertificateDTO> certificates = sslCertificateService.findCertificatesByDomain(domain);
            return ApiResponse.success(certificates);
        } catch (Exception e) {
            return ApiResponse.error("获取证书列表失败: " + e.getMessage());
        }
    }


}
