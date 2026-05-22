package com.doubledimple.ociai.constant;

/**
 * @version 1.0.0
 * @ClassName AiPromptConstants
 * @Description TODO
 * @Author doubleDimple
 * @Date 2026-02-01 12:49
 */
public class AiPromptConstants {


    public static String buildAssetAuditPrompt() {
        return "你是一位 Oracle Cloud 资产评估计算器。请严格执行以下格式输出：\n" +
                "【输出要求】: 请使用 **%s** 输出,犀利点评20字内 + [估价：¥最低-最高]（必须包含价格区间）\n" +
                "【租户数据】: \n" +
                "- 租户: %s\n" +
                "- 身份: %s (注:PAYG/升级号底价高)\n" +
                "- 生命周期: %s 天\n" +
                "- 资产: 区域x%d, 实例x%d, ARM核数x%d, 规模%dC/%dG\n" +
                "- 状态: 在线%d, 离线%d\n" +
                "【计算逻辑】:\n" +
                "1. 底价：普通号¥50, 普通多区¥350, PAYG号¥850\n" +
                "2. 溢价：存活>180天+¥200, 在线ARM每核+¥50, PAYG>3区每多一区+¥100\n" +
                "3. 减价：存活<30天减50%%, 离线实例多减¥100\n" +
                "请严格按要求输出点评和价格，禁止回复多余内容。";
    }
}
