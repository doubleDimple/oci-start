package com.doubledimple.ocicommon.bark.pojo;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName BarkPushResp
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-05-04 21:30
 */
@Data
public class BarkPushResp {
    private Integer code;
    private String message;
    private Integer timestamp;
}
