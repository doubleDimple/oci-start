package com.doubledimple.ociserver.service;

import com.doubledimple.ociserver.pojo.request.MfaConfig;

import javax.servlet.http.HttpServletRequest;

/**
 * 验证接口
 */
public interface VerifyService {

    //生成验证码,
    public String generateVerificationCode();

    //发送验证码
    public void sendVerifyCodeForInstance(String instanceId);

    /**
     *
     * @param instanceId 存储的key
     * @param targetCode 输入的验证码
     * @return
     */
    public void checkCodeForInstance(String instanceId,String targetCode);

    boolean isMessageEnabled();

    void sendVerificationCodeForLogin(String username, HttpServletRequest  request);

    public void checkCodeForLogin(String userName,String targetCode);


    /**
     * 发送密码重置验证码
     * @param username 用户名
     */
    void sendVerificationCodeForPasswordReset(String username,HttpServletRequest  request);

    /**
     * 验证密码重置验证码
     * @param username 用户名
     * @param verificationCode 验证码
     * @return 重置token
     */
    String verifyCodeForPasswordReset(String username, String verificationCode,HttpServletRequest  request);


    void sendVerifyCodeForExport(String username, HttpServletRequest request);

    void checkCodeForExport(String username, String verificationCode);

    /**
     * 执行密码重置
     * @param username 用户名
     * @param resetToken 重置token
     * @return 新密码
     */
    String resetPassword(String username, String resetToken);

    MfaConfig getMfaConfig();
}
