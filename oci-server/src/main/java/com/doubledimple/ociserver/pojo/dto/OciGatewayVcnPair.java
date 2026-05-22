package com.doubledimple.ociserver.pojo.dto;

import com.oracle.bmc.core.model.InternetGateway;
import com.oracle.bmc.core.model.Vcn;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * @version 1.0.0
 * @ClassName OciGatewayVcnPair
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-12-13 21:12
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class OciGatewayVcnPair {

    private  InternetGateway internetGateway;
    private  Vcn vcn;
}
