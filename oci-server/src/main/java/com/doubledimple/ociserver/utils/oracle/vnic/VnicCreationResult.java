package com.doubledimple.ociserver.utils.oracle.vnic;

import com.oracle.bmc.core.model.VnicAttachment;
import lombok.Data;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/**
* @Description:  VNIC创建结果模型
* @Param:
* @return:
* @Author: doubleDimpLe
* @Date: 7/16/25 4:35 PM
*/
@Data
public class VnicCreationResult {
    private String vnicId;
    private String vnicDisplayName;
    private String privateIp;
    private String publicIp;
    private String subnetId;
    private String attachmentId;
    private VnicAttachment.LifecycleState lifecycleState;
    private List<String> ipv6Addresses;
    private List<String> ipv6Ids;
    private boolean success;
    private String errorMessage;
    private Instant createdAt;

    private Boolean isPrimary;

    private String instanceId;
    private String instanceName;

    public VnicCreationResult() {
        this.ipv6Addresses = new ArrayList<>();
        this.ipv6Ids = new ArrayList<>();
        this.success = false;
        this.createdAt = Instant.now();
    }
}
