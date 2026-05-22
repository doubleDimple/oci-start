package com.doubledimple.ociserver.pojo.dto;

import com.oracle.bmc.core.model.Shape;
import lombok.Data;

import java.util.List;

/**
 * @version 1.0.0
 * @ClassName OciComputerDto
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-10-29 14:02
 */
@Data
public class OciComputerDto {

    private String bootIdStr;
    private String compartmentIdRoot;
    private Shape.BillingType billingType;

    private List<AvailabilityDomainName> availabilityDomainNameList;

    @Data
    public static class AvailabilityDomainName{
        private String availabilityDomainName;
        private List<OciShape> ociShapeList;
    }

    @Data
    public static class OciShape{
        private String shapeName;
        private String compartmentId;
        private String availabilityDomainName;
        private String imageId;
        private String subnetId;
        private String networkSecurityGroupId;
        private Shape.BillingType billingType;
    }
}
