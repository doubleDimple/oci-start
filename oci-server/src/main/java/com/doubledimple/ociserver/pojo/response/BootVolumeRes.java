package com.doubledimple.ociserver.pojo.response;

import com.oracle.bmc.core.model.BootVolume;
import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName BootVolumeResponse
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-12-23 19:59
 */
@Data
public class BootVolumeRes {
    private String id;
    private String displayName;
    private Long sizeInGBs;
    private Long vpusPerGB;

    private Long tenantId;
    private String instanceName;
    private String instanceId;
    private Long instanceDetailsId;
    private String status;
    private String compartmentId;
    private String regionCode;

    public static BootVolumeRes fromBootVolume(BootVolume bootVolume) {
        BootVolumeRes response = new BootVolumeRes();
        response.setId(bootVolume.getId());
        response.setDisplayName(bootVolume.getDisplayName());
        response.setSizeInGBs(bootVolume.getSizeInGBs());
        response.setVpusPerGB(bootVolume.getVpusPerGB());
        response.setStatus(bootVolume.getLifecycleState().getValue());
        return response;
    }
}
