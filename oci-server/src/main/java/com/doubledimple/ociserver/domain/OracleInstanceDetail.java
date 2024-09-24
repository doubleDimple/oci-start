package com.doubledimple.ociserver.domain;

import lombok.Data;

/**
 * @author doubleDimple
 * @date 2024:09:22日 21:33
 */
@Data
public class OracleInstanceDetail {

    private String publicIp;
    private String image;
    private String shape;
    private String userName;
}
