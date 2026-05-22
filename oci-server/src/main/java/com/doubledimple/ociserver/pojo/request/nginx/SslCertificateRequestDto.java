package com.doubledimple.ociserver.pojo.request.nginx;

import com.doubledimple.dao.entity.SslCertificate;
import lombok.Data;

import javax.validation.constraints.NotBlank;

/**
 * @version 1.0.0
 * @ClassName SslCertificateRequestDto
 * @Description
 * @Author doubleDimple
 * @Date 2025-09-23 14:25
 */
@Data
public class SslCertificateRequestDto {
    @NotBlank(message = "域名不能为空")
    private String domain;

    private String email;

    private String certificateType = "LETS_ENCRYPT";

    private String dnsProvider = "CLOUDFLARE";

    private String validationMethod = "dns";
    private Boolean autoRenew = true;
}
