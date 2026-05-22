package com.doubledimple.ociserver.service.nginx;

import com.doubledimple.dao.entity.ProxyConfig;
import com.doubledimple.ociserver.pojo.request.nginx.ProxyConfigCreateDto;
import com.doubledimple.ociserver.pojo.request.nginx.ProxyConfigUpdateDto;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

import java.util.List;

public interface ProxyConfigService {

    /**
     * 创建反向代理配置
     */
    ProxyConfig createProxyConfig(ProxyConfigCreateDto dto);

    /**
     * 更新反向代理配置
     */
    ProxyConfig updateProxyConfig(ProxyConfigUpdateDto dto);

    /**
     * 删除反向代理配置
     */
    void deleteProxyConfig(Long id);

    /**
     * 获取反向代理配置列表
     */
    Page<ProxyConfig> getProxyConfigs(Pageable pageable);

    /**
     * 根据ID获取配置
     */
    ProxyConfig getProxyConfigById(Long id);

    /**
     * 应用SSL配置
     */
    void applySslConfig(Long proxyId, String email);

    /**
     * 修复配置
     */
    void fixProxyConfig(Long id);

    /**
     * 获取所有配置用于生成Nginx配置
     */
    List<ProxyConfig> getAllActiveConfigs();

    public void toggleProxyConfig(Long id, Boolean enabled);

    public boolean testConnection(Long id);

    /**
     * 当某证书状态发生变化（申请成功/失败）时，把所有引用它的 Proxy 的 sslStatus
     * 同步成相应状态（VALID -> CONFIGURED，ERROR -> ERROR）
     */
    void syncProxySslStatusByCertificate(Long sslCertificateId);
}
