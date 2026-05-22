package com.doubledimple.ociserver.pojo.response;

import lombok.Data;

import java.util.List;

/**
 * @version 1.0.0
 * @ClassName AccountCheckRes
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-12-22 02:04
 */
@Data
public class AccountCheckRes {
    private int totalAccounts;
    private int activeAccounts;
    private int inactiveAccounts;
    private List<String> inactiveAccountNames;

    // 构造器
    public AccountCheckRes(int totalAccounts, int activeAccounts, int inactiveAccounts, List<String> inactiveAccountNames) {
        this.totalAccounts = totalAccounts;
        this.activeAccounts = activeAccounts;
        this.inactiveAccounts = inactiveAccounts;
        this.inactiveAccountNames = inactiveAccountNames;
    }

    // Getters and Setters
}
