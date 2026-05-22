package com.doubledimple.ociserver.pojo.response;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName PasswordPolicyDetail
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-08-24 20:43
 */
@Data
public class PasswordPolicyDetail {

    private String name;
    private boolean enablePasswordExpiry;
    private Integer expiryDays;
}
