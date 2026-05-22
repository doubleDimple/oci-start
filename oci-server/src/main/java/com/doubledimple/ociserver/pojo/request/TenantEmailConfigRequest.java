package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName TenantEmailConfigRequest
 * @Description TODO
 * @Author renyx
 * @Date 2025-09-27 10:40
 */
@Data
public class TenantEmailConfigRequest extends BaseRequest{

    private long id;

    private String tenantId;
}
