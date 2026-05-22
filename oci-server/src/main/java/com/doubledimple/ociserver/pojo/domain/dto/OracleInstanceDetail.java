package com.doubledimple.ociserver.pojo.domain.dto;

import com.oracle.bmc.core.model.Instance;
import com.oracle.bmc.core.model.Shape;
import lombok.Data;

/**
 * @author doubleDimple
 * @date 2024:09:22日 21:33
 */
@Data
public class OracleInstanceDetail {

    private long tenantId;
    private String publicIp;
    private String image;
    private String shape;
    private Boolean success;
    private String userName;
    private String region;
    private String architecture;
    private String rootPasswd;

    private Long addCount;

    private Shape.BillingType billingType;

    private Instance instance;

    private String privateIp;

    private User user;

}
