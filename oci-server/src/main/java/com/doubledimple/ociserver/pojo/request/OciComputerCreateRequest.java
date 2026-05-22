package com.doubledimple.ociserver.pojo.request;

import com.doubledimple.ociserver.pojo.domain.dto.User;
import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName OciComputerCreateRequest
 * @Description TODO
 * @Author renyx
 * @Date 2025-10-29 13:40
 */
@Data
public class OciComputerCreateRequest {

    private String compartmentId;
    private String availabilityDomainName;
    private String shapeName;
    private String imageId;
    private String subnetId;
    private String networkSecurityGroupId;
    private String script;
    private User user;
}
