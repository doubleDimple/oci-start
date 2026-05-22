package com.doubledimple.ocicommon.param;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName OpenInstanceNotify
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-30 12:37
 */
@Data
public class OpenInstanceNotify {

    private String region;
    private String architecture;
    private String data;
    private Long count;
    private String accountTypeName;
    private String secret;

}
