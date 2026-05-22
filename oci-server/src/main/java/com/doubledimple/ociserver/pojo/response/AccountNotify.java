package com.doubledimple.ociserver.pojo.response;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName AccountNotify
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-04-07 17:38
 */
@Data
public class AccountNotify{
    //总账号数据
    private int totalAccount;
    //异常账号数据
    private int inActiveAccount;
    private int activeAccount;
    private String inActiveAccountNames = "NONE";
}
