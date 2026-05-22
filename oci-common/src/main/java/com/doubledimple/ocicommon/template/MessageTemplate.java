package com.doubledimple.ocicommon.template;

import com.doubledimple.ocicommon.utils.DateTimeUtils;

/**
 * @author doubleDimple
 * @date 2024:10:21日 21:31
 */
public class MessageTemplate {


    public static final String COMMON_LINKS ="Github: [Oci-Start](https://github.com/doubleDimple/oci-start)\n" +
            "频道: [OCI_NOTIFY](https://t.me/OCI_NOTIFY)";
    /**
     * 开机成功提醒模板
     */
    public static final String LEGACY_MESSAGE_TEMPLATE_SUBJECT = "开机成功通知";
    public static final String LEGACY_MESSAGE_TEMPLATE =
            "   🚀 ————ORACLE开机成功通知———— 🚀\n\n" +
            "状态: 已成功启动\n" +
            "时间: %s\n" +
            "用户: %s\n" +
            "实例信息:\n" +
            "-----------------------------------\n" +
            "架构类型: %s\n" +
            "实例区域: %s\n" +
            "访问地址: %s\n" +
            "访问用户: [root]\n" +
            "访问密码: %s \n" +
            "创建次数: %s\n" +
            "-----------------------------------\n" +
            "实例已经创建成功，请登录验证\n" +
            "#开机成功\n";

    public static final String GCP_LEGACY_MESSAGE_TEMPLATE =
            "   🚀 ————GCP开机成功通知———— 🚀\n\n" +
                    "状态: 已成功启动\n" +
                    "时间: %s\n\n" +
                    "实例信息:\n" +
                    "-----------------------------------\n" +
                    "架构类型: %s\n" +
                    "实例区域: %s\n" +
                    "实例名称: %s\n" +
                    "访问用户: [root]\n" +
                    "访问密码: %s \n" +
                    "-----------------------------------\n\n" +
                    "实例已经创建成功，请等待实例可用后更新查看ip\n" +
                    "#开机成功\n";



    /**
     * 开机配置成功提醒
     */
    public static final String MESSAGE_CONFIG_SUCCESS_TEMPLATE = "🎉 ————预开机通知———— 🎉\n" +
            "Oci-Start机器人提醒你：\n" +
            "租户【%s】的区域【%s】\n" +
            "🚀 已经开始抢机中，祝你好运！\n" +
            "#OciStart\n";

    /**
     * 开机配置停止提醒
     */
    public static final String MESSAGE_CONFIG_STOP_TEMPLATE = "————抢机停止———— \n" +
            "Oci-Start机器人提醒你：\n" +
            "租户【%s】的实例【%s】\n" +
            "已经停止抢机运行\n" +
            "#OciStart\n";


    public static final String MESSAGE_CONFIG_STOP_NO_AUTH_TEMPLATE_SUBJECT = "抢机停止";
    public static final String MESSAGE_CONFIG_STOP_NO_AUTH_TEMPLATE = "————"+ MESSAGE_CONFIG_STOP_NO_AUTH_TEMPLATE_SUBJECT+"————\n" +
            "Oci-Start机器人提醒你：\n" +
            "租户【%s】的实例【%s】\n" +
            "由于【%s】原因已经停止实例预创建\n" +
            "#OciStart\n";


    /**
     * 开机配置停止提醒
     */
    public static final String MESSAGE_CONFIG_STOP_INSTANCE_TEMPLATE_SUBJECT = "实例终止提醒";
    public static final String MESSAGE_CONFIG_STOP_INSTANCE_TEMPLATE = " ————"+ MESSAGE_CONFIG_STOP_INSTANCE_TEMPLATE_SUBJECT+"———— ️\n" +
            "Oci-Start机器人提醒你：\n" +
            "租户【%s】的实例【%s】\n" +
            "正在执行终止操作\n" +
            "验证码为:【%s】\n" +
            "❗ 安全提示：请勿泄漏验证码，防止实例被错误终止\n" +
            "#OciStart\n";

    public static final String MESSAGE_CONFIG_IP_SWITCH_TEMPLATE = " ————IP切换提醒———— ️\n" +
            "Oci-Start机器人提醒你：\n" +
            "时间: "+ DateTimeUtils.getCurrentDateTime() +"\n" +
            "租户【%s】的实例【%s】\n" +
            "执行IP切换操作成功\n" +
            "原IP地址：【%s】\n" +
            "新IP地址：【%s】\n" +
            "#IP切换\n";

    public static final String MESSAGE_CONFIG_DNS_AUTO_UPDATE_TEMPLATE = " ————DNS自动更新提醒———— ️\n" +
            "Oci-Start机器人提醒你：\n" +
            "时间: "+ DateTimeUtils.getCurrentDateTime() +"\n" +
            "租户【%s】的实例【%s】\n" +
            "检测到原地址已在DNS服务商配置\n" +
            "已自动帮你更新DNS记录\n" +
            "服务商：【%s】\n" +
            "原地址：【%s】\n" +
            "新地址：【%s】\n" +
            "状态值：【成功】✅\n" +
            "#DNS自动更新\n";

    public static final String MESSAGE_LOGIN_TEMPLATE = " ————登录提醒———— \n" +
            "Oci-Start机器人提醒你：\n" +
            "用户【%s】正在执行登录操作\n" +
            "\n" +
            "*验证码为:*\n" +
            "%s\n" +
            "\n" +
            "验证码有效期5分钟，请尽快认证\n" +
            "#登录\n";

    public static final String MESSAGE_LOGIN_TEMPLATE_V_2_SUBJECT = "登录提醒";
    public static final String MESSAGE_LOGIN_TEMPLATE_V_2 = "———— "+ MESSAGE_LOGIN_TEMPLATE_V_2_SUBJECT+" ————\n" +
            "Oci-Start 机器人提醒你：\n" +
            "来自：【%s】\n" +
            "用户 ***%s*** 正在执行登录操作\n" +
            "验证码为：<code>%s</code> \n" +
            "验证码有效期 5 分钟，请尽快认证\n" +
            "#登录\n";

    public static final String MESSAGE_MALICIOUS_LOGIN_TEMPLATE_V_2_SUBJECT = "异常登录警告";
    public static final String MESSAGE_MALICIOUS_LOGIN_TEMPLATE_V_2 = "———— "+ MESSAGE_MALICIOUS_LOGIN_TEMPLATE_V_2_SUBJECT+" ————\n" +
            "Oci-Start 机器人检测到疑似异常登录：\n" +
            "来自：%s\n" +
            "用户：***%s***\n" +
            "时间: "+ DateTimeUtils.getCurrentDateTime() +"\n" +
            "如果需要封禁该 IP ，请回复“/banIp_%s”。\n" +
            "如需解封,请执行“/unbanIp_%s”。\n" +
            "#安全告警\n";

    public static final String MESSAGE_WRONG_PASSWORD_TEMPLATE_V_2 = "———— 密码错误提醒 ————\n" +
            "Oci-Start 机器人提醒：\n" +
            "来自：%s\n" +
            "时间: " + DateTimeUtils.getCurrentDateTime() + "\n" +
            "建议: 若非本人操作，请及时封禁访问IP ，请回复“/banIp_%s”。\n" +
            "如需解封,请执行“/unbanIp_%s”。\n" +
            "#登录警告\n";





    /**
     * api 账号测试失联提醒
     */
    public static final String MESSAGE_CONFIG_DEAD_ACCOUNT_TEMPLATE_SUBJECT = "账号状态提醒";
    public static final String MESSAGE_CONFIG_DEAD_ACCOUNT_TEMPLATE = "————"+MESSAGE_CONFIG_DEAD_ACCOUNT_TEMPLATE_SUBJECT+"————\n" +
            "Oci-Start机器人提醒你：\n" +
            "总共测试:【%s】个账号\n" +
            "❌ 异常账号:【%s】个\n" +
            "以下API所属账号检测异常,请登录控制台查看具体账号情况\n" +
            "🔎 异常账号详情:\n" +
            "【%s】\n" +
            "#测活\n" + COMMON_LINKS;

    /**
     * api 账号测试成功提醒
     */
    public static final String MESSAGE_CONFIG_SUCCESS_ACCOUNT_TEMPLATE = "————账号状态提醒————\n" +
            "Oci-Start机器人提醒你：\n" +
            "截止今天,总共测试:【%s】个账号\n" +
            "恭喜你！所有账号都处于正常状态 ✅\n" +
            "🌟 请继续保持！加油！\n" +
            "#测活\n" + COMMON_LINKS;

    /**
     * 开机统计提醒
     */
    public static final String MESSAGE_CONFIG_TOTAL_TEMPLATE = " ————每日播报———— \n" +
            "Oci-Start机器人提醒你：\n" +
            "截至今天Oci-Start帮你账号的【%s】个区域进行了【%s】次抢机\n" +
            "成功【%s】次\n" +
            "轻舟已过万重山，加油！奥利给！✨\n" +
            "#OciStart\n" + COMMON_LINKS;

    /**
     * 流量超出预警告警模板
     */
    public static final String MESSAGE_TRAFFIC_EXCEED_ALERT_TEMPLATE_SUBJECT = "流量超出预警";
    public static final String MESSAGE_TRAFFIC_EXCEED_ALERT_TEMPLATE = "————"+MESSAGE_TRAFFIC_EXCEED_ALERT_TEMPLATE_SUBJECT+"———— \n" +
            "Oci-Start机器人提醒你：\n" +
            "租户：【%s】区域:【%s】\n" +
            "实例IP：【%s】\n" +
            "⚠️ 【%s】流量使用情况：\n" +
            "已用流量：【%.2f GB】\n" +
            "设定阈值：【%.2f GB】\n" +
            "超出阈值：【%.2f GB】\n" +
            "建议您注意流量使用，避免超出预算产生费用\n" +
            "#流量提醒\n";

    /**
     * 流量超出预警并自动关闭实例模板
     */
    public static final String MESSAGE_TRAFFIC_EXCEED_SHUTDOWN_TEMPLATE = "————流量超额自动关机————\n" +
            "Oci-Start机器人紧急提醒你：\n" +
            "租户：【%s】区域:【%s】\n" +
            "实例IP:【%s】\n" +
            "⚠️ 【%s】流量严重超出：\n" +
            "已用流量：【%.2f GB】\n" +
            "设定阈值：【%.2f GB】\n" +
            "超出阈值：【%.2f GB】\n" +
            "系统已自动关闭该实例以防止进一步的流量消耗\n" +
            "如需继续使用，请重新启动实例\n" +
            "#流量预警\n";

    /**
     * 实例救援成功通知模板
     */
    public static final String MESSAGE_RESCUE_SUCCESS_TEMPLATE_SUBJECT = "实例救援成功";
    public static final String MESSAGE_RESCUE_SUCCESS_TEMPLATE = " ————"+MESSAGE_RESCUE_SUCCESS_TEMPLATE_SUBJECT+"———— \n" +
            "Oci-Start机器人提醒你：\n" +
            "用户: %s\n\n" +
            "救援实例信息:\n" +
            "-----------------------------------\n" +
            "实例区域: %s\n" +
            "实例名称: %s\n" +
            "访问地址: %s\n" +
            "访问用户: root\n" +
            "访问密码: %s\n" +
            "-----------------------------------\n\n" +
            "✅ 实例已成功救援并重启\n" +
            "救援过程完成，请使用上述信息登录验证,如果密码不正确或者无法登录,请联系作者\n" +
            "安全提示：请登录后立即修改默认密码\n" +
            "#实例救援\n";


    public static final String MESSAGE_LOAD_BALANCER_SUCCESS_TEMPLATE = " ————负载均衡启用成功———— \n" +
            "Oci-Start机器人提醒你：\n" +
            "用户: %s\n\n" +
            "负载均衡信息:\n" +
            "-----------------------------------\n" +
            "实例区域: %s\n" +
            "实例名称: %s\n" +
            "访问地址: %s\n" +
            "访问用户: root\n" +
            "访问密码: 该实例原密码\n" +
            "-----------------------------------\n\n" +
            "✅ 负载均衡已成功启用\n" +
            "请使用新的负载均衡IP进行连接\n" +
            "#负载均衡\n";

    public static final String MESSAGE_LOAD_BALANCER_RESTORE_SUCCESS_TEMPLATE = " ————负载均衡还原成功———— \n" +
            "Oci-Start机器人提醒你：\n" +
            "用户: %s\n\n" +
            "实例恢复信息:\n" +
            "-----------------------------------\n" +
            "实例区域: %s\n" +
            "实例名称: %s\n" +
            "访问地址: %s\n" +
            "访问用户: root\n" +
            "访问密码: 该实例原密码\n" +
            "-----------------------------------\n\n" +
            "✅ 已成功还原到原始网络配置\n" +
            "请使用实例原IP进行连接\n" +
            "负载均衡器和相关网络资源已清理\n" +
            "#网络还原\n";


    /**
     * 获取完全融合的消息
     *
     * @param totalAccounts 总测试账号数
     * @param deadAccounts 异常账号数(0表示全部正常)
     * @param deadAccountDetails 异常账号详情(仅当有异常账号时使用)
     * @param regions 区域数
     * @param totalAttempts 总抢机次数
     * @param successCount 成功次数
     * @return 格式化后的消息
     */
    public static String getMessage(int totalAccounts, int deadAccounts, String deadAccountDetails,
                                    long regions, long totalAttempts, long successCount) {

        StringBuilder message = new StringBuilder();
        message.append("————Oci-Start每日提醒———— \n\n");
        // 账号测试情况
        message.append("📱 账号状态：\n");
        message.append("截止今日共测试【").append(totalAccounts).append("】个账号");

        if (deadAccounts > 0) {
            // 异常账号情况
            message.append("\n发现【").append(deadAccounts).append("】个异常账号");
            message.append("\n异常账号：【").append(deadAccountDetails).append("】");
            message.append("\n请登录控制台查看具体情况。");
        } else {
            // 全部正常情况
            message.append("\n所有账号均正常运行，请继续加油！");
        }

        // 添加一个空行分隔
        message.append("\n\n");

        // 抢机统计情况，每项一行
        message.append("📊 抢机统计：");

        if (regions > 0L) {
            message.append("\n实例区域：【").append(regions).append("】个");
        }

        if (totalAttempts > 0L) {
            message.append("\n抢机尝试：【").append(totalAttempts).append("】次");
        }

        if (successCount > 0L) {
            message.append("\n成功次数：【").append(successCount).append("】次");
        }

        // 鼓励性结语
        message.append("\n\n继续加油，勇往直前！✨\n" +
                "#每日通知\n" + COMMON_LINKS);

        return message.toString();
    }

    /**
     * 密码重置验证码模板
     */
    public static final String MESSAGE_PASSWORD_RESET_CODE_TEMPLATE = " ————密码重置验证码———— \n" +
            "Oci-Start机器人提醒你：\n" +
            "用户【%s】正在执行密码重置操作\n" +
            "\n" +
            "*验证码为:*\n" +
            "%s\n" +
            "\n" +
            "验证码有效期5分钟，请尽快认证\n" +
            "⚠️ 安全提示：请勿泄漏验证码给他人\n" +
            "#密码重置\n";

    /**
     * 新密码发送模板
     */
    public static final String MESSAGE_NEW_PASSWORD_TEMPLATE = "————密码重置成功————\n" +
            "Oci-Start机器人提醒你：\n" +
            "✅ 您的密码重置成功\n" +
            "\n" +
            "登录信息:\n" +
            "-----------------------------------\n" +
            "用户名: %s\n" +
            "新密码: %s\n" +
            "-----------------------------------\n" +
            "\n" +
            "请立即登录并修改为您的个人密码\n" +
            "安全提示：请妥善保管新密码，避免泄露\n" +
            "#密码重置\n";

    public static final String MESSAGE_CONSOLE_PASSWORD_RESET_WITH_PASSWORD_TEMPLATE_SUBJECT = "控制台密码重置成功";
    public static final String MESSAGE_CONSOLE_PASSWORD_RESET_WITH_PASSWORD_TEMPLATE = "————"+MESSAGE_CONSOLE_PASSWORD_RESET_WITH_PASSWORD_TEMPLATE_SUBJECT+"————\n" +
            "Oci-Start机器人提醒你：\n" +
            "✅ Oracle Cloud控制台密码重置成功\n" +
            "\n" +
            "登录信息:\n" +
            "-----------------------------------\n" +
            "租户名称: %s\n" +
            "登录用户: %s\n" +
            "临时密码: %s\n" +
            "重置时间: %s\n" +
            "-----------------------------------\n" +
            "首次登录时需要修改临时密码\n" +
            "临时密码有效期：7天\n" +
            "请立即登录Oracle Cloud控制台验证\n" +
            "安全提示：请勿将临时密码泄露给他人\n" +
            "#控制台密码重置\n";


    /**
     * VPS离线通知模板
     */
    public static final String MESSAGE_VPS_OFFLINE_TEMPLATE = "————VPS离线通知———— ️\n" +
            "Oci-Start机器人提醒你：\n" +
            "租户：【%s】\n" +
            "区域：【%s】\n" +
            "实例IP：【%s】\n" +
            "实例名称：【%s】\n" +
            "\n" +
            "检测到该实例已离线\n" +
            "检测时间：%s\n" +
            "\n" +
            "#VPS离线\n";

    /**
     * VPS恢复在线通知模板
     */
    public static final String MESSAGE_VPS_ONLINE_TEMPLATE = " ————VPS恢复在线———— \n" +
            "Oci-Start机器人提醒你：\n" +
            "租户：【%s】\n" +
            "区域：【%s】\n" +
            "实例IP：【%s】\n" +
            "实例名称：【%s】\n" +
            "\n" +
            "该实例已恢复在线\n" +
            "\n" +
            "#VPS恢复\n";

    /**
     * DD系统安装成功通知模板
     */
    public static final String MESSAGE_DD_SUCCESS_TEMPLATE = " ————DD系统安装成功———— \n" +
            "Oci-Start机器人提醒你：\n" +
            "时间: " + DateTimeUtils.getCurrentDateTime() + "\n\n" +
            "系统重装信息:\n" +
            "-----------------------------------\n" +
            "租户【%s】\n" +
            "实例名称: %s\n" +
            "实例IP: %s\n" +
            "系统类型: %s\n" +
            "系统版本: %s\n" +
            "访问用户: root\n" +
            "新设密码: %s\n" +
            "原设密码: %s\n" +
            "-----------------------------------\n\n" +
            "✅ 系统安装已完成\n" +
            "如果未触发重启操作,请手动重启后使用上述信息登录验证新系统\n" +
            "#DD系统安装\n";

    /**
     * DD系统安装失败通知模板
     */
    public static final String MESSAGE_DD_FAILED_TEMPLATE = " ————DD系统安装失败———— \n" +
            "Oci-Start机器人提醒你：\n" +
            "时间: " + DateTimeUtils.getCurrentDateTime() + "\n\n" +
            "系统重装信息:\n" +
            "-----------------------------------\n" +
            "租户【%s】\n" +
            "实例名称: %s\n" +
            "实例IP: %s\n" +
            "系统类型: %s\n" +
            "系统版本: %s\n" +
            "-----------------------------------\n\n" +
            "❌ 系统安装失败\n" +
            "失败原因: %s\n" +
            "#DD系统安装失败\n";

    /**
     * DD系统安装中通知模板
     */
    public static final String MESSAGE_DD_INSTALLING_TEMPLATE = " ————DD系统安装中———— \n" +
            "Oci-Start机器人提醒你：\n" +
            "时间: " + DateTimeUtils.getCurrentDateTime() + "\n\n" +
            "系统重装信息:\n" +
            "-----------------------------------\n" +
            "租户【%s】\n" +
            "实例名称: %s\n" +
            "实例IP: %s\n" +
            "系统类型: %s\n" +
            "系统版本: %s\n" +
            "-----------------------------------\n\n" +
            "系统安装进行中\n" +
            "请勿关闭或重启实例\n" +
            "安装可能需要5-15分钟，请耐心等待\n" +
            "安装完成后将发送通知\n" +
            "#DD系统安装\n";

    /**
     * 数据导出验证码模板
     */
    public static final String MESSAGE_DATA_EXPORT_CODE_TEMPLATE = " ————数据导出验证———— \n" +
            "Oci-Start机器人提醒你：\n" +
            "用户【%s】正在执行租户数据导出操作\n" +
            "\n" +
            "*验证码为:*\n" +
            "%s\n" +
            "\n" +
            "验证码有效期5分钟，请尽快认证\n" +
            "安全提示：导出文件包含租户敏感信息，请妥善保管验证码及导出文件\n" +
            "#数据导出\n";


    /**
     * 版本更新提醒模板
     */
    public static final String MESSAGE_VERSION_UPDATE_TEMPLATE_SUBJECT = "发现新版本";
    public static final String MESSAGE_VERSION_UPDATE_TEMPLATE = "———— "+ MESSAGE_VERSION_UPDATE_TEMPLATE_SUBJECT +" ————\n" +
            "Oci-Start 发现可用更新！\n" +
            "版本信息:\n" +
            "-----------------------------------\n" +
            "发布版本: 【%s】\n" +
            "发布时间: " + DateTimeUtils.getCurrentDateTime() + "\n" +
            "-----------------------------------\n" +
            "更新内容:\n" +
            "%s\n" +
            "-----------------------------------\n" +
            "请更新获取最新功能。\n" +
            "#版本更新\n" + COMMON_LINKS;

    /**
     * 抢机任务异常终止提醒（严重错误）
     */
    public static final String MESSAGE_CONFIG_TASK_ERROR_SUBJECT = "抢机任务异常停止";
    public static final String MESSAGE_CONFIG_TASK_ERROR_TEMPLATE = "————" + MESSAGE_CONFIG_TASK_ERROR_SUBJECT + "————\n" +
            "Oci-Start机器人紧急提醒你：\n" +
            "租户【%s】的区域【%s】开机停止\n" +
            "停止原因：【%s】\n" +
            "时间: " + DateTimeUtils.getCurrentDateTime() + "\n" +
            "该任务已自动停止，请检查配置或账号状态后重新开启。\n" +
            "#任务停止\n" + COMMON_LINKS;


    public static final String MYSQL_CREATE_SUCCESS_TEMPLATE_SUBJECT = "MySQL实例创建成功通知";
    public static final String MYSQL_CREATE_SUCCESS_TEMPLATE =
            "   🐬 ————MySQL实例创建成功通知———— 🐬\n" +
                    "状态: 已成功启动\n" +
                    "时间: %s\n" +
                    "租户: %s\n" +
                    "实例信息:\n" +
                    "-----------------------------------\n" +
                    "所在区域: %s\n" +
                    "MySQL 版本: %s\n" +
                    "内网地址: %s\n" +
                    "公网地址: %s\n" +
                    "管理用户: %s\n" +
                    "初始密码: %s \n" +
                    "连接端口: %s \n" +
                    "存储空间: %s GB\n" +
                    "-----------------------------------\n" +
                    "✅ 数据库已就绪，使用上述信息连接验证\n" +
                    "#MySQL创建成功\n";

    /**
     * MySQL 账密重置成功通知模板
     */
    public static final String MYSQL_AUTH_RESET_SUCCESS_TEMPLATE_SUBJECT = "MySQL账密重置通知";
    public static final String MYSQL_AUTH_RESET_SUCCESS_TEMPLATE =
            "    ————MySQL账密重置通知———— \n\n" +
                    "状态: 账密已更新 ✅\n" +
                    "时间: %s\n" +
                    "租户: %s\n" +
                    "实例信息:\n" +
                    "-----------------------------------\n" +
                    "实例名称: %s\n" +
                    "管理用户: %s\n" +
                    "新初始密码: %s \n" +
                    "-----------------------------------\n" +
                    "❗ 提醒：原管理密码已失效。\n" +
                    "请使用上方新凭据登录您的数据库。\n" +
                    "#MySQL账密重置\n";

    /**
     * 抢机任务超时告警模板（非终止错误）
     */
    public static final String MESSAGE_CONFIG_TASK_TIMEOUT_SUBJECT = "抢机请求超时告警";
    public static final String MESSAGE_CONFIG_TASK_TIMEOUT_TEMPLATE = "———— " + MESSAGE_CONFIG_TASK_TIMEOUT_SUBJECT + " ————\n" +
            "Oci-Start 机器人监测到网络波动：\n" +
            "租户：【%s】\n" +
            "区域：【%s】\n" +
            "状态：请求超时 (Timeout)\n" +
            "原因：【响应缓慢或网络解析异常】\n" +
            "时间：" + DateTimeUtils.getCurrentDateTime() + "\n" +
            "-----------------------------------\n" +
            "#任务告警 #超时重试\n" + COMMON_LINKS;

    /**
     * 资源负载过高告警模板
     */
    public static final String MESSAGE_RESOURCE_ALARM_TEMPLATE_SUBJECT = "资源负载告警";
    public static final String MESSAGE_RESOURCE_ALARM_TEMPLATE = "————  " + MESSAGE_RESOURCE_ALARM_TEMPLATE_SUBJECT + " ————\n" +
            "Oci-Start 机器人检测到实例负载异常：\n" +
            "时间: " + DateTimeUtils.getCurrentDateTime() + "\n" +
            "租户: 【%s】\n" +
            "区域: 【%s】\n" +
            "IP地址: %s\n" +
            "-----------------------------------\n" +
            "告警内容: \n" +
            "%s\n" +
            "-----------------------------------\n" +
            "#资源告警 #负载过高\n";
}
