package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName BootVolumeUpdateRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-12-23 20:17
 */
@Data
public class BootVolumeUpdateRequest {
    private Long vpusPerGB;

    private String tenantId;

    private String displayName;

    private Long instanceDetailId;
}
