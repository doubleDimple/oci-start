package com.doubledimple.ociserver.pojo.response;

import lombok.Data;

/**
 * @author doubleDimple
 * @date 2024:11:01日 23:28
 */
@Data
public class OtpResponse2 {

    private String otpCode;

    public OtpResponse2(String otpCpde){
        this.otpCode = otpCpde;
    }
}
