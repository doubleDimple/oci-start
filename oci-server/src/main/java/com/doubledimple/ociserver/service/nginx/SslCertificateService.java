package com.doubledimple.ociserver.service.nginx;

import com.doubledimple.dao.entity.SslCertificate;
import com.doubledimple.ociserver.pojo.request.nginx.CertificateDTO;
import com.doubledimple.ociserver.pojo.request.nginx.SslCertificateRequestDto;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

import java.util.List;
import java.util.Map;

public interface SslCertificateService {

    /**
     * 申请SSL证书
     */
    SslCertificate requestCertificate(SslCertificateRequestDto dto);

    /**
     * 手动续期证书
     */
    void renewCertificate(Long certificateId);

    /**
     * 删除证书
     */
    void deleteCertificate(Long certificateId);

    /**
     * 切换自动续期
     */
    void toggleAutoRenew(Long certificateId, Boolean enabled);

    /**
     * 获取证书列表
     */
    Page<SslCertificate> getCertificates(Pageable pageable);

    /**
     * 检查即将过期的证书
     */
    List<SslCertificate> checkExpiringCertificates();

    /**
     * 自动续期处理
     */
    void processAutoRenewal();

    /**
     * 下载证书文件
     */
    Map<String, Object> downloadCertificate(Long certificateId) throws Exception;

    public List<CertificateDTO> findCertificatesByDomain(String domain);

    /**
     * 同步通知 ProxyConfig 该证书的状态已变更（VALID/ERROR），由 ACME 异步流程回调使用
     */
    void onCertificateStatusChanged(Long certificateId);
}
