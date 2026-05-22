package com.doubledimple.ociserver.service.nginx;

import com.doubledimple.dao.entity.NginxConfig;
import com.doubledimple.dao.entity.SslCertificate;
import com.doubledimple.ocicommon.param.ApiResponse;

import java.util.Map;

public interface NginxConfigService {

    /**
     * 生成新的Nginx配置
     */
    NginxConfig generateNginxConfig();

    /**
     * 获取当前配置
     */
    NginxConfig getCurrentConfig();

    /**
     * 获取最新配置
     */
    NginxConfig getLatestConfig();

    /**
     * 应用配置
     */
    void applyConfig(Long configId);

    /**
     * 测试配置
     */
    boolean testConfig(Long configId);

    /**
     * 重载Nginx
     */
    void reloadNginx();

    /**
     * 获取配置对比
     */
    String getConfigDiff();

    /**
     * 检查OpenResty状态
     */
    Map<String, Object> checkOpenRestyStatus();

    /**
     * 启动OpenResty服务
     */
    void startOpenRestyService();

    /**
     * 通过API操作nginx配置
     */
    void updateNginxConfigViaApi(String configContent);

    /**
     * 上传SSL证书到OpenResty
     */
    ApiResponse uploadSslCertificateToOpenResty(SslCertificate sslCertificate);
}
